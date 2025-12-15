.PHONY: build run test clean fmt lint deps

# Build the binary
build:
	go build -o claude-tui .

# Run the TUI
run: build
	./claude-tui

# Run with custom backend
run-dev: build
	BACKEND_URL=http://localhost:8000 ./claude-tui

# Run tests
test:
	go test ./...

# Clean build artifacts
clean:
	rm -f claude-tui

# Format code
fmt:
	go fmt ./...

# Run linter
lint:
	golangci-lint run

# Install/update dependencies
deps:
	go mod tidy
