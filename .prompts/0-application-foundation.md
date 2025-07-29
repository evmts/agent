# 0: Application Foundation Setup

## Goal

Establish the complete foundational infrastructure for "Plue", a Gitea-inspired Git service. This includes a command-line interface (CLI), a desktop GUI, a containerized development environment using Docker, and a basic HTTP API server.

## Technical Requirements

- **Backend:** Zig
- **CLI Parser:** `zig-clap`
- **Frontend:** SolidJS with TypeScript, Vite, and Tailwind CSS
- **GUI Window:** WebUI
- **Containerization:** Docker and Docker Compose
- **HTTP Server:** `httpz`
- **Database:** PostgreSQL (via Docker)

---

### Phase 1: CLI & Project Structure

1.  **Initialize Project:** Start with a standard `zig init` project structure.
2.  **CLI Commands:**
    -   Implement a root command using `zig-clap`.
    -   Create a `start` subcommand that will launch the GUI application.
    -   Create a `server` subcommand that will run the standalone HTTP API server.
3.  **Graceful Shutdown:** Both `start` and `server` commands must handle `SIGINT` and `SIGTERM` for graceful shutdown.
4.  **Directory Structure:**
    -   `src/commands/`: For CLI command implementations.
    -   `src/gui/`: For the SolidJS frontend application.
    -   `src/server/`: For the HTTP server implementation.
    -   `src/generated/`: For auto-generated files (e.g., embedded assets).

### Phase 2: GUI Integration

1.  **Frontend Setup:**
    -   Initialize a standard SolidJS project in `src/gui/` using `npm create vite@latest`.
    -   Configure it with TypeScript, SWC, and Tailwind CSS.
2.  **WebUI Wrapper:**
    -   Integrate the WebUI library to create a native desktop window.
    -   The `start` command should initialize and run the WebUI event loop.
3.  **Asset Embedding:**
    -   Create a custom build step in `build.zig`.
    -   This step must run `npm install` and `npm run build` in `src/gui/`.
    -   It must then take the compiled frontend assets from `src/gui/dist/` and embed them into a Zig source file (`src/generated/assets.zig`).
    -   The GUI window will serve these embedded assets.

### Phase 3: Dockerized Development Environment

1.  **Dockerfile:**
    -   Create a multi-stage `Dockerfile`.
    -   **Builder Stage:** Use a Zig image to build the application binary.
    -   **Final Stage:** Use a minimal base image (e.g., Debian slim) and copy the compiled binary into it.
2.  **Docker Compose:**
    -   Create a `docker-compose.yml` file with the following services:
        -   `postgres`: A PostgreSQL 16 database service.
        -   `api-server`: Runs the compiled Zig application using the `server` command. Must be built from the `Dockerfile`.
        -   `web`: An Nginx service to act as a reverse proxy or serve a static site (placeholder for now).
        -   `healthcheck`: A service that runs a script to check the health of the `api-server` and `postgres` services.
3.  **Configuration:**
    -   The `api-server` must be accessible on port `8000`.
    -   The `postgres` service should have a persistent volume for data.
    -   Use environment variables for database credentials.

### Phase 4: HTTP API Server

1.  **HTTP Server Implementation:**
    -   Use the `httpz` library to create an HTTP server in `src/server/server.zig`.
    -   The `server` subcommand should start this server.
2.  **Configuration:**
    -   The server must listen on `0.0.0.0:8000` to be accessible within the Docker network.
3.  **Endpoints:**
    -   Implement a `GET /` endpoint that returns a simple "Hello World" message.
    -   Implement a `GET /health` endpoint that returns a "healthy" status, which the `healthcheck` service will use.

## Success Criteria

1.  Running `zig build` successfully compiles the application, including the frontend asset embedding step.
2.  Running `zig build test` passes all tests.
3.  Running `zig run src/main.zig -- start` launches the desktop GUI window displaying the SolidJS application.
4.  Running `zig run src/main.zig -- server` starts the HTTP server.
5.  Running `docker-compose up --build` successfully starts all services.
6.  The `healthcheck` service reports that the `api-server` and `postgres` services are healthy.
7.  Making a `curl http://localhost:8000/health` request to the running container returns a `200 OK` with the body "healthy".