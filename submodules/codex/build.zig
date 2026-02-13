const std = @import("std");

pub fn build(b: *std.Build) void {
    const cargo_build = b.addSystemCommand(&.{
        "sh",
        "-c",
        "if [ ! -f Cargo.toml ]; then echo 'ERROR: submodules/codex is not initialized (missing Cargo.toml).' >&2; exit 1; fi; if ! command -v cargo >/dev/null 2>&1; then echo 'ERROR: cargo not found. Install Rust toolchain: https://rustup.rs/' >&2; exit 1; fi; cargo build --release --locked",
    });

    b.getInstallStep().dependOn(&cargo_build.step);

    const check_step = b.step("check", "Build codex artifacts via cargo");
    check_step.dependOn(&cargo_build.step);
}
