# Contributing to Plue

## Development Resources

### Zig Documentation
- [Zig Language Documentation](https://ziglang.org/documentation/master/) - Official Zig documentation
- [Zig Standard Library](https://ziglang.org/documentation/master/std/) - Standard library reference

### Dependencies
- [zig-clap GitHub](https://github.com/Hejsil/zig-clap) - Command line argument parser
- [zig-clap Generated Docs](https://hejsil.github.io/zig-clap/) - API reference documentation
- [zap GitHub](https://github.com/zigzap/zap) - Blazingly fast web framework built on facil.io
- [pg.zig GitHub](https://github.com/karlseguin/pg.zig) - PostgreSQL client library

## Development Setup

### Prerequisites
1. Install Zig 0.14.0 or later
2. Install Docker and Docker Compose (for database and integration testing)
3. Install Node.js 20+ (for web UI development)

### Local Development
```bash
# Clone the repository
git clone <repository-url>
cd plue

# Build the project
zig build

# Run tests
zig build test

# Run the CLI
zig build run -- --help

# Run the server locally
DATABASE_URL=postgresql://plue:plue_password@localhost:5432/plue zig build run -- server
```

### Docker Development
```bash
# Start all services
docker-compose -f infra/docker/docker-compose.yml up -d

# Run database migrations
docker-compose -f infra/docker/docker-compose.yml run --rm db-migrate

# Run health checks
docker-compose -f infra/docker/docker-compose.yml run --rm healthcheck python /app/scripts/healthcheck.py

# View logs
docker-compose -f infra/docker/docker-compose.yml logs -f api-server

# Rebuild after changes
docker-compose -f infra/docker/docker-compose.yml build api-server
docker-compose -f infra/docker/docker-compose.yml up -d api-server
```

### Web UI Development
```bash
cd src/gui
npm install
npm run dev  # Development server with hot reload
npm run build  # Production build
```

## Code Standards

Follow the coding standards defined in `CLAUDE.md`, including:
- Single responsibility functions
- Memory-conscious allocation patterns
- Tests included in source files
- Immediate build verification after changes
- Proper memory management with defer patterns
- Use of allocator for all dynamic memory

## Testing

### Unit Tests
- All modules include tests in the same file
- Run with `zig build test`
- Database tests will skip if PostgreSQL is not available

### Integration Tests
- Health check script tests full stack functionality
- Verifies CRUD operations through REST API
- Tests web UI serving and rendering

### Manual Testing
```bash
# Create a user
curl -X POST http://localhost:8000/users \
  -H "Content-Type: application/json" \
  -d '{"name": "testuser"}'

# List users
curl http://localhost:8000/users

# Get specific user
curl http://localhost:8000/users/testuser

# Update user
curl -X PUT http://localhost:8000/users/testuser \
  -H "Content-Type: application/json" \
  -d '{"name": "newname"}'

# Delete user
curl -X DELETE http://localhost:8000/users/newname
```

## Project Structure

```
plue/
├── src/
│   ├── main.zig          # CLI entry point
│   ├── root.zig          # Library exports
│   ├── commands/
│   │   ├── init.zig      # Git init wrapper
│   │   ├── status.zig    # Git status wrapper
│   │   └── server.zig    # HTTP server command
│   ├── server/
│   │   └── server.zig    # HTTP server with REST API
│   ├── database/
│   │   └── dao.zig       # Data Access Object for PostgreSQL
│   └── gui/              # SolidJS web interface
├── scripts/
│   ├── migrate.py        # Database migration tool
│   └── healthcheck.py    # End-to-end health verification
├── infra/                # Infrastructure code
│   ├── docker/           # Docker configurations
│   │   ├── Dockerfile
│   │   ├── docker-compose.yml
│   │   └── nginx.conf
│   └── ...               # Terraform modules
└── build.zig            # Build configuration
```

## Database Migrations

Migrations are managed by `scripts/migrate.py`:

```bash
# Run migrations (in Docker)
docker-compose -f infra/docker/docker-compose.yml run --rm db-migrate

# Run migrations locally
python scripts/migrate.py up

# Rollback migrations
python scripts/migrate.py down
```

## Build Commands

- `zig build` - Build the project in debug mode
- `zig build -Doptimize=ReleaseSafe` - Build optimized with safety checks
- `zig build -Doptimize=ReleaseFast` - Build optimized for speed
- `zig build -Doptimize=ReleaseSmall` - Build optimized for size
- `zig build test` - Run all tests
- `zig build run` - Run the application
- `zig build run -- [args]` - Run with arguments

## Common Issues

### Database Connection
If you see "Failed to connect to database", ensure PostgreSQL is running:
```bash
docker-compose -f infra/docker/docker-compose.yml up -d postgres
docker-compose -f infra/docker/docker-compose.yml run --rm db-migrate
```

### Port Conflicts
If ports 3000, 8000, or 5432 are in use, modify `infra/docker/docker-compose.yml` to use different ports.

### Memory Leaks
Always use defer patterns for cleanup:
```zig
const thing = try allocator.create(Thing);
defer allocator.destroy(thing);
```

## Submitting Changes

1. Ensure all tests pass: `zig build && zig build test`
2. Run the health check: `docker-compose -f infra/docker/docker-compose.yml run --rm healthcheck python /app/scripts/healthcheck.py`
3. Follow conventional commit format: `feat: Add new feature`
4. Update documentation if adding new features
5. Submit pull request with clear description