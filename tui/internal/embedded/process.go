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
)

// ServerProcess manages the lifecycle of the Python server.
type ServerProcess struct {
	cmd    *exec.Cmd
	port   int
	cancel context.CancelFunc
}

// StartServer starts the Python server.
// Returns the server process handle and URL.
func StartServer(ctx context.Context) (*ServerProcess, string, error) {
	// Find an available port
	port, err := findFreePort()
	if err != nil {
		return nil, "", fmt.Errorf("failed to find free port: %w", err)
	}

	// Find Python executable
	pythonCmd := findPython()
	if pythonCmd == "" {
		return nil, "", fmt.Errorf("python not found in PATH (tried python3, python)")
	}

	// Find main.py
	mainPy := findMainPy()
	if mainPy == "" {
		return nil, "", fmt.Errorf("main.py not found (checked relative to executable and working directory)")
	}

	// Create a cancellable context for the process
	procCtx, cancel := context.WithCancel(ctx)

	// Start the server process
	cmd := exec.CommandContext(procCtx, pythonCmd, mainPy)
	cmd.Env = append(os.Environ(),
		fmt.Sprintf("PORT=%d", port),
		"HOST=127.0.0.1",
	)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	// Set platform-specific process attributes
	setProcAttr(cmd)

	if err := cmd.Start(); err != nil {
		cancel()
		return nil, "", fmt.Errorf("failed to start server: %w", err)
	}

	serverURL := fmt.Sprintf("http://127.0.0.1:%d", port)

	// Wait for the server to be ready
	if err := waitForServer(serverURL, 30*time.Second); err != nil {
		cmd.Process.Kill()
		cancel()
		return nil, "", fmt.Errorf("server failed to start: %w", err)
	}

	return &ServerProcess{
		cmd:    cmd,
		port:   port,
		cancel: cancel,
	}, serverURL, nil
}

// Stop gracefully stops the server process.
func (s *ServerProcess) Stop() error {
	if s == nil {
		return nil
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
		case <-time.After(5 * time.Second):
			// Force kill if still running
			s.cmd.Process.Kill()
		}
	}

	return nil
}

// Port returns the port the server is running on.
func (s *ServerProcess) Port() int {
	return s.port
}

// findPython finds the Python executable.
func findPython() string {
	for _, name := range []string{"python3", "python"} {
		if path, err := exec.LookPath(name); err == nil {
			return path
		}
	}
	return ""
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
	client := &http.Client{Timeout: 2 * time.Second}
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		resp, err := client.Get(url + "/health")
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == 200 {
				return nil
			}
		}
		time.Sleep(100 * time.Millisecond)
	}

	return fmt.Errorf("server did not become ready within %v", timeout)
}
