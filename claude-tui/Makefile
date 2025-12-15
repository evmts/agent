.PHONY: build run mock test clean

# Build the binary
build:
	go build -o claude-tui .

# Run the TUI (assumes mock server is running)
run: build
	./claude-tui

# Run the mock server
mock: build
	./claude-tui -mock

# Run with mock server (starts mock in background, then TUI)
dev: build
	@echo "Starting mock server..."
	@./claude-tui -mock & sleep 1 && ./claude-tui; kill $$!

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

# Install dependencies
deps:
	go mod tidy
