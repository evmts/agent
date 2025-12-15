package embedded

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"time"
)

// ServerProcess manages the lifecycle of the embedded Python server.
type ServerProcess struct {
	cmd        *exec.Cmd
	binaryPath string
	port       int
	cancel     context.CancelFunc
}

// StartServer extracts and starts the embedded Python server.
// Returns the server process handle and URL.
func StartServer(ctx context.Context) (*ServerProcess, string, error) {
	// Find an available port
	port, err := findFreePort()
	if err != nil {
		return nil, "", fmt.Errorf("failed to find free port: %w", err)
	}

	// Extract the server binary
	binaryPath, err := ExtractServer()
	if err != nil {
		return nil, "", fmt.Errorf("failed to extract server: %w", err)
	}

	// Create a cancellable context for the process
	procCtx, cancel := context.WithCancel(ctx)

	// Start the server process
	cmd := exec.CommandContext(procCtx, binaryPath)
	cmd.Env = append(os.Environ(),
		fmt.Sprintf("PORT=%d", port),
		"HOST=127.0.0.1",
	)
	cmd.Stdout = nil // Suppress output
	cmd.Stderr = nil

	// Set platform-specific process attributes
	setProcAttr(cmd)

	if err := cmd.Start(); err != nil {
		CleanupServer(binaryPath)
		cancel()
		return nil, "", fmt.Errorf("failed to start server: %w", err)
	}

	serverURL := fmt.Sprintf("http://127.0.0.1:%d", port)

	// Wait for the server to be ready
	if err := waitForServer(serverURL, 30*time.Second); err != nil {
		cmd.Process.Kill()
		CleanupServer(binaryPath)
		cancel()
		return nil, "", fmt.Errorf("server failed to start: %w", err)
	}

	return &ServerProcess{
		cmd:        cmd,
		binaryPath: binaryPath,
		port:       port,
		cancel:     cancel,
	}, serverURL, nil
}

// Stop gracefully stops the server process and cleans up.
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

	// Clean up the extracted binary
	return CleanupServer(s.binaryPath)
}

// Port returns the port the server is running on.
func (s *ServerProcess) Port() int {
	return s.port
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
