//! Plue Monorepo Build System
//!
//! Unified build orchestration for all components:
//! - Zig server (server/)
//! - Astro frontend (root)
//! - Cloudflare Workers (edge/)
//! - Terminal UI (tui/)
//! - Rust FFI (server/jj-ffi/, snapshot/)
//!
//! Run `zig build --help` to see all available steps.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ==========================================================================
    // BUILD STEPS
    // ==========================================================================

    // Server (Zig) - builds via dependency
    const server_step = b.step("server", "Build Zig server only");
    const server_build = b.addSystemCommand(&.{ "zig", "build", "-Doptimize=ReleaseFast" });
    server_build.setCwd(b.path("server"));
    server_step.dependOn(&server_build.step);

    // Web (Astro) - bun run build
    const web_step = b.step("web", "Build Astro frontend only");
    const web_build = b.addSystemCommand(&.{ "bun", "run", "build" });
    web_step.dependOn(&web_build.step);

    // Edge (Cloudflare Workers)
    const edge_step = b.step("edge", "Build Cloudflare Worker only");
    const edge_build = b.addSystemCommand(&.{ "bun", "run", "build" });
    edge_build.setCwd(b.path("edge"));
    edge_step.dependOn(&edge_build.step);

    // TUI
    const tui_step = b.step("tui", "Build TUI only");
    const tui_build = b.addSystemCommand(&.{ "bun", "run", "build" });
    tui_build.setCwd(b.path("tui"));
    tui_step.dependOn(&tui_build.step);

    // Default step: build all native artifacts (not Docker)
    const build_all = b.step("all", "Build everything (native only, no Docker)");
    build_all.dependOn(server_step);
    build_all.dependOn(web_step);
    build_all.dependOn(edge_step);
    build_all.dependOn(tui_step);
    b.default_step = build_all;

    // ==========================================================================
    // RUN STEPS
    // ==========================================================================

    // Run docker compose (postgres only)
    const run_docker = b.addSystemCommand(&.{ "docker", "compose", "up", "-d", "postgres" });
    const run_docker_step = b.step("run:docker", "Start Docker services (postgres)");
    run_docker_step.dependOn(&run_docker.step);

    // Run Zig server only
    const run_server_cmd = b.addSystemCommand(&.{ "zig", "build", "run" });
    run_server_cmd.setCwd(b.path("server"));
    const run_server_step = b.step("run:server", "Run Zig server only");
    run_server_step.dependOn(&run_server_cmd.step);

    // Run Astro dev server only
    const run_web_cmd = b.addSystemCommand(&.{ "bun", "run", "dev" });
    const run_web_step = b.step("run:web", "Run Astro dev server only");
    run_web_step.dependOn(&run_web_cmd.step);

    // Run full dev environment (docker + server + web)
    // Note: This starts docker first, then runs server
    const run_step = b.step("run", "Run full dev environment (docker + server)");
    run_step.dependOn(run_docker_step);
    // Server runs after docker is up
    const run_server_after_docker = b.addSystemCommand(&.{ "zig", "build", "run" });
    run_server_after_docker.setCwd(b.path("server"));
    run_server_after_docker.step.dependOn(&run_docker.step);
    run_step.dependOn(&run_server_after_docker.step);

    // ==========================================================================
    // TEST STEPS
    // ==========================================================================

    // Zig tests - server
    const test_server = b.addSystemCommand(&.{ "zig", "build", "test" });
    test_server.setCwd(b.path("server"));
    const test_server_step = b.step("test:server", "Run server Zig tests");
    test_server_step.dependOn(&test_server.step);

    // Zig tests - core
    const test_core = b.addSystemCommand(&.{ "zig", "build", "test" });
    test_core.setCwd(b.path("core"));
    const test_core_step = b.step("test:core", "Run core Zig tests");
    test_core_step.dependOn(&test_core.step);

    // All Zig tests
    const test_zig_step = b.step("test:zig", "Run all Zig tests");
    test_zig_step.dependOn(test_server_step);
    test_zig_step.dependOn(test_core_step);

    // TypeScript tests (vitest in edge)
    const test_edge = b.addSystemCommand(&.{ "bun", "run", "test" });
    test_edge.setCwd(b.path("edge"));
    const test_edge_step = b.step("test:edge", "Run Edge worker tests");
    test_edge_step.dependOn(&test_edge.step);

    // TypeScript tests - all (placeholder for when more TS tests exist)
    const test_ts_step = b.step("test:ts", "Run all TypeScript tests");
    test_ts_step.dependOn(test_edge_step);

    // Rust tests - run from jj/, prompt-parser/, and snapshot directories
    const test_rust_jj = b.addSystemCommand(&.{ "cargo", "test" });
    test_rust_jj.setCwd(b.path("jj"));
    const test_rust_prompt = b.addSystemCommand(&.{ "cargo", "test" });
    test_rust_prompt.setCwd(b.path("prompt-parser"));
    const test_rust_snapshot = b.addSystemCommand(&.{ "cargo", "test" });
    test_rust_snapshot.setCwd(b.path("snapshot"));
    const test_rust_step = b.step("test:rust", "Run all Rust tests");
    test_rust_step.dependOn(&test_rust_jj.step);
    test_rust_step.dependOn(&test_rust_prompt.step);
    test_rust_step.dependOn(&test_rust_snapshot.step);

    // E2E tests (Playwright)
    const test_e2e = b.addSystemCommand(&.{ "bun", "run", "test:e2e" });
    const test_e2e_step = b.step("test:e2e", "Run Playwright E2E tests");
    test_e2e_step.dependOn(&test_e2e.step);

    // All tests (excluding E2E by default - they require running services)
    const test_all_step = b.step("test", "Run ALL unit tests (Zig + TS + Rust)");
    test_all_step.dependOn(test_zig_step);
    test_all_step.dependOn(test_ts_step);
    test_all_step.dependOn(test_rust_step);

    // ==========================================================================
    // LINT STEPS
    // ==========================================================================

    // Zig format check (acts as lint)
    const lint_zig = b.addSystemCommand(&.{ "zig", "fmt", "--check", "server", "core", "db" });
    const lint_zig_step = b.step("lint:zig", "Check Zig formatting");
    lint_zig_step.dependOn(&lint_zig.step);

    // TypeScript lint (eslint via package.json)
    const lint_ts = b.addSystemCommand(&.{ "bun", "run", "lint:check" });
    const lint_ts_step = b.step("lint:ts", "Lint TypeScript with ESLint");
    lint_ts_step.dependOn(&lint_ts.step);

    // Rust lint (clippy)
    const lint_rust_jj = b.addSystemCommand(&.{ "cargo", "clippy", "--manifest-path", "jj/Cargo.toml", "--", "-D", "warnings" });
    const lint_rust_prompt = b.addSystemCommand(&.{ "cargo", "clippy", "--manifest-path", "prompt-parser/Cargo.toml", "--", "-D", "warnings" });
    const lint_rust_snapshot = b.addSystemCommand(&.{ "cargo", "clippy", "--manifest-path", "snapshot/Cargo.toml", "--", "-D", "warnings" });
    const lint_rust_step = b.step("lint:rust", "Lint Rust with Clippy");
    lint_rust_step.dependOn(&lint_rust_jj.step);
    lint_rust_step.dependOn(&lint_rust_prompt.step);
    lint_rust_step.dependOn(&lint_rust_snapshot.step);

    // All lint
    const lint_all_step = b.step("lint", "Lint ALL code (Zig + TS + Rust)");
    lint_all_step.dependOn(lint_zig_step);
    lint_all_step.dependOn(lint_ts_step);
    lint_all_step.dependOn(lint_rust_step);

    // ==========================================================================
    // FORMAT STEPS
    // ==========================================================================

    // Zig format
    const format_zig = b.addSystemCommand(&.{ "zig", "fmt", "server", "core", "db" });
    const format_zig_step = b.step("format:zig", "Format Zig code");
    format_zig_step.dependOn(&format_zig.step);

    // TypeScript format (eslint --fix)
    const format_ts = b.addSystemCommand(&.{ "bun", "run", "lint" });
    const format_ts_step = b.step("format:ts", "Format TypeScript with ESLint --fix");
    format_ts_step.dependOn(&format_ts.step);

    // Rust format
    const format_rust_jj = b.addSystemCommand(&.{ "cargo", "fmt", "--manifest-path", "jj/Cargo.toml" });
    const format_rust_prompt = b.addSystemCommand(&.{ "cargo", "fmt", "--manifest-path", "prompt-parser/Cargo.toml" });
    const format_rust_snapshot = b.addSystemCommand(&.{ "cargo", "fmt", "--manifest-path", "snapshot/Cargo.toml" });
    const format_rust_step = b.step("format:rust", "Format Rust code");
    format_rust_step.dependOn(&format_rust_jj.step);
    format_rust_step.dependOn(&format_rust_prompt.step);
    format_rust_step.dependOn(&format_rust_snapshot.step);

    // All format
    const format_all_step = b.step("format", "Format ALL code (Zig + TS + Rust)");
    format_all_step.dependOn(format_zig_step);
    format_all_step.dependOn(format_ts_step);
    format_all_step.dependOn(format_rust_step);

    // Format check (all)
    const format_check_step = b.step("format:check", "Check formatting without modifying");
    format_check_step.dependOn(lint_zig_step); // zig fmt --check
    // Add biome check if needed

    // ==========================================================================
    // CI STEPS
    // ==========================================================================

    // Quick check (format + lint + typecheck)
    const typecheck = b.addSystemCommand(&.{ "bun", "run", "type-check" });
    const check_step = b.step("check", "Quick validation (format:check + lint + typecheck)");
    check_step.dependOn(lint_all_step);
    check_step.dependOn(&typecheck.step);

    // Full CI pipeline
    const ci_step = b.step("ci", "Full CI pipeline (lint + test + build)");
    ci_step.dependOn(lint_all_step);
    ci_step.dependOn(test_all_step);
    ci_step.dependOn(build_all);

    // ==========================================================================
    // UTILITY STEPS
    // ==========================================================================

    // Clean all build artifacts
    const clean = b.addSystemCommand(&.{
        "rm", "-rf",
        "zig-out",
        "zig-cache",
        ".zig-cache",
        "server/zig-out",
        "server/zig-cache",
        "server/.zig-cache",
        "core/zig-out",
        "core/zig-cache",
        "dist",
        "edge/dist",
        "tui/dist",
    });
    const clean_step = b.step("clean", "Clean all build artifacts");
    clean_step.dependOn(&clean.step);

    // Install all dependencies
    const deps_bun = b.addSystemCommand(&.{ "bun", "install" });
    const deps_step = b.step("deps", "Install all dependencies (bun install)");
    deps_step.dependOn(&deps_bun.step);

    // Database migration
    const db_migrate = b.addSystemCommand(&.{ "bun", "run", "db:migrate" });
    const db_migrate_step = b.step("db:migrate", "Run database migrations");
    db_migrate_step.dependOn(&db_migrate.step);

    // Database seed
    const db_seed = b.addSystemCommand(&.{ "bun", "run", "test:e2e:seed" });
    const db_seed_step = b.step("db:seed", "Seed database with test data");
    db_seed_step.dependOn(&db_seed.step);

    // Docker build
    const docker_build = b.addSystemCommand(&.{ "docker", "compose", "build" });
    const docker_step = b.step("docker", "Build Docker images");
    docker_step.dependOn(&docker_build.step);

    // Docker up all
    const docker_up_all = b.addSystemCommand(&.{ "docker", "compose", "up", "-d" });
    const docker_up_step = b.step("docker:up", "Start all Docker services");
    docker_up_step.dependOn(&docker_up_all.step);

    // Docker down
    const docker_down = b.addSystemCommand(&.{ "docker", "compose", "down" });
    const docker_down_step = b.step("docker:down", "Stop all Docker services");
    docker_down_step.dependOn(&docker_down.step);

    // ==========================================================================
    // HELP (printed when running just `zig build`)
    // ==========================================================================
    _ = target;
    _ = optimize;
}
