# Plue

A git wrapper application with a web interface, REST API, and PostgreSQL database backend.

## Features

- **CLI Interface**: Command-line tool for git operations
- **REST API**: HTTP server with CRUD endpoints for user management
- **Database Integration**: PostgreSQL backend with migration support
- **Web Interface**: SolidJS single-page application
- **Docker Support**: Full containerization with docker-compose orchestration

## Quick Start

### Using Docker (Recommended)

```bash
# Start all services
docker-compose up -d

# Run health checks
docker-compose run --rm healthcheck python /app/scripts/healthcheck.py

# View logs
docker-compose logs -f
```

Services will be available at:
- Web UI: http://localhost:3000
- API: http://localhost:8000
- PostgreSQL: localhost:5432

### Local Development

```bash
# Build the application
zig build

# Run tests
zig build test

# Run the CLI
zig build run -- --help

# Run the server
zig build run -- server
```

## API Endpoints

- `GET /health` - Health check endpoint
- `GET /users` - List all users
- `POST /users` - Create a new user (JSON body: `{"name": "username"}`)
- `GET /users/:name` - Get a specific user
- `PUT /users/:name` - Update a user (JSON body: `{"name": "newname"}`)
- `DELETE /users/:name` - Delete a user

## Architecture

```
plue/
├── src/
│   ├── main.zig          # CLI entry point
│   ├── commands/         # CLI commands
│   ├── server/           # HTTP server implementation
│   ├── database/         # Database access layer
│   └── gui/              # SolidJS web interface
├── scripts/
│   ├── migrate.py        # Database migrations
│   └── healthcheck.py    # End-to-end health checks
└── docker/
    ├── Dockerfile        # Multi-stage build
    └── docker-compose.yml # Service orchestration
```

## Dependencies

- **Zig 0.14.0**: Systems programming language
- **httpz**: HTTP server framework
- **pg.zig**: PostgreSQL client library
- **zig-clap**: Command-line argument parser
- **SolidJS**: Reactive UI framework
- **PostgreSQL 16**: Database server

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

[License information to be added]