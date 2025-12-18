package embedded

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/williamcory/agent/sdk/agent"
)

// ServerProcess manages the lifecycle of the Python server.
type ServerProcess struct {
	cmd    *exec.Cmd
	port   int
	cancel context.CancelFunc
	logger *agent.Logger
}

// StartServer starts the Python server.
// Returns the server process handle and URL.
func StartServer(ctx context.Context) (*ServerProcess, string, error) {
	return StartServerWithLogger(ctx, agent.GetLogger())
}

// StartServerWithLogger starts the Python server with a custom logger.
func StartServerWithLogger(ctx context.Context, logger *agent.Logger) (*ServerProcess, string, error) {
	return StartServerWithLoggerQuiet(ctx, logger, false)
}

// StartServerWithLoggerQuiet starts the Python server with a custom logger and optional quiet mode.
func StartServerWithLoggerQuiet(ctx context.Context, logger *agent.Logger, quiet bool) (*ServerProcess, string, error) {
	logger.Info("Starting embedded server...")

	// Find an available port
	port, err := findFreePort()
	if err != nil {
		logger.Error("Failed to find free port", "error", err.Error())
		return nil, "", fmt.Errorf("failed to find free port: %w", err)
	}
	logger.Debug("Found free port", "port", port)

	// Find main.py
	mainPy := findMainPy()
	if mainPy == "" {
		logger.Error("main.py not found")
		return nil, "", fmt.Errorf("main.py not found (checked relative to executable and working directory)")
	}
	logger.Debug("Found main.py", "path", mainPy)

	// Create a cancellable context for the process
	procCtx, cancel := context.WithCancel(ctx)

	// Start the server process using uv run
	cmd := exec.CommandContext(procCtx, "uv", "run", "python", mainPy)
	cmd.Env = append(os.Environ(),
		fmt.Sprintf("PORT=%d", port),
		"HOST=127.0.0.1",
		"DISABLE_LOGGING=true",
	)

	// In quiet mode (exec command), redirect server output to /dev/null
	if quiet {
		devNull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
		if err != nil {
			cancel()
			logger.Error("Failed to open /dev/null", "error", err.Error())
			return nil, "", fmt.Errorf("failed to open /dev/null: %w", err)
		}
		cmd.Stdout = devNull
		cmd.Stderr = devNull
	} else {
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
	}

	// Set platform-specific process attributes
	setProcAttr(cmd)

	logger.Debug("Starting Python process", "command", "uv run python "+mainPy)
	if err := cmd.Start(); err != nil {
		cancel()
		logger.Error("Failed to start server process", "error", err.Error())
		return nil, "", fmt.Errorf("failed to start server: %w", err)
	}
	logger.Debug("Process started", "pid", cmd.Process.Pid)

	serverURL := fmt.Sprintf("http://127.0.0.1:%d", port)

	// Wait for the server to be ready
	logger.Debug("Waiting for server health check...")
	if err := waitForServerWithLogger(serverURL, 30*time.Second, logger); err != nil {
		cmd.Process.Kill()
		cancel()
		logger.Error("Server health check failed", "error", err.Error())
		return nil, "", fmt.Errorf("server failed to start: %w", err)
	}

	logger.Info("Embedded server ready", "url", serverURL, "port", port)

	return &ServerProcess{
		cmd:    cmd,
		port:   port,
		cancel: cancel,
		logger: logger,
	}, serverURL, nil
}

// Stop gracefully stops the server process.
func (s *ServerProcess) Stop() error {
	if s == nil {
		return nil
	}

	if s.logger != nil {
		s.logger.Info("Stopping embedded server...")
	}

	// Cancel the context to signal shutdown
	if s.cancel != nil {
		s.cancel()
	}

	// Try graceful shutdown first
	if s.cmd != nil && s.cmd.Process != nil {
		// Send interrupt signal
		s.cmd.Process.Signal(os.Interrupt)

		// Wait briefly for graceful shutdown
		done := make(chan error, 1)
		go func() {
			done <- s.cmd.Wait()
		}()

		select {
		case <-done:
			// Process exited cleanly
			if s.logger != nil {
				s.logger.Debug("Server stopped gracefully")
			}
		case <-time.After(5 * time.Second):
			// Force kill if still running
			if s.logger != nil {
				s.logger.Warn("Server did not stop gracefully, force killing")
			}
			s.cmd.Process.Kill()
		}
	}

	if s.logger != nil {
		s.logger.Info("Embedded server stopped")
	}

	return nil
}

// Port returns the port the server is running on.
func (s *ServerProcess) Port() int {
	return s.port
}

// findMainPy finds main.py relative to the executable or working directory.
func findMainPy() string {
	// Check relative to executable
	if exe, err := os.Executable(); err == nil {
		dir := filepath.Dir(exe)
		candidates := []string{
			filepath.Join(dir, "..", "main.py"),
			filepath.Join(dir, "main.py"),
		}
		for _, p := range candidates {
			if _, err := os.Stat(p); err == nil {
				abs, _ := filepath.Abs(p)
				return abs
			}
		}
	}

	// Check relative to working directory
	if cwd, err := os.Getwd(); err == nil {
		candidates := []string{
			filepath.Join(cwd, "main.py"),
			filepath.Join(cwd, "..", "main.py"),
		}
		for _, p := range candidates {
			if _, err := os.Stat(p); err == nil {
				abs, _ := filepath.Abs(p)
				return abs
			}
		}
	}

	return ""
}

// findFreePort returns an available TCP port.
func findFreePort() (int, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port, nil
}

// waitForServer polls the health endpoint until the server is ready.
func waitForServer(url string, timeout time.Duration) error {
	return waitForServerWithLogger(url, timeout, agent.GetLogger())
}

// waitForServerWithLogger polls the health endpoint with logging.
func waitForServerWithLogger(url string, timeout time.Duration, logger *agent.Logger) error {
	client := &http.Client{Timeout: 2 * time.Second}
	deadline := time.Now().Add(timeout)
	attempts := 0

	for time.Now().Before(deadline) {
		attempts++
		resp, err := client.Get(url + "/health")
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == 200 {
				logger.Debug("Health check passed", "attempts", attempts)
				return nil
			}
		}
		time.Sleep(100 * time.Millisecond)
	}

	logger.Debug("Health check timed out", "attempts", attempts)
	return fmt.Errorf("server did not become ready within %v", timeout)
}
