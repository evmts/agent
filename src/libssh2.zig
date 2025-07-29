const std = @import("std");

pub const include_dir = "deps/libssh2/include";

// All libssh2 source files (using mbedTLS backend)
const srcs = &.{
    "deps/libssh2/src/agent.c",
    "deps/libssh2/src/bcrypt_pbkdf.c", 
    "deps/libssh2/src/blowfish.c",
    "deps/libssh2/src/channel.c",
    "deps/libssh2/src/comp.c",
    "deps/libssh2/src/crypt.c",
    "deps/libssh2/src/global.c",
    "deps/libssh2/src/hostkey.c",
    "deps/libssh2/src/keepalive.c",
    "deps/libssh2/src/kex.c",
    "deps/libssh2/src/knownhost.c",
    "deps/libssh2/src/mac.c",
    "deps/libssh2/src/mbedtls.c", // mbedTLS backend
    "deps/libssh2/src/misc.c",
    "deps/libssh2/src/packet.c",
    "deps/libssh2/src/pem.c",
    "deps/libssh2/src/publickey.c",
    "deps/libssh2/src/scp.c",
    "deps/libssh2/src/session.c",
    "deps/libssh2/src/sftp.c",
    "deps/libssh2/src/transport.c",
    "deps/libssh2/src/userauth.c",
    "deps/libssh2/src/version.c",
    // Skip platform-specific files we don't need:
    // - agent_win.c (Windows only)
    // - wincng.c (Windows CNG backend)
    // - openssl.c (OpenSSL backend - we use mbedTLS)
    // - libgcrypt.c (libgcrypt backend)
    // - os400qc3.c (OS/400 specific)
};

pub const Library = struct {
    step: *std.Build.Step.Compile,
    build: *std.Build,

    pub fn link(self: Library, other: *std.Build.Step.Compile) void {
        other.addIncludePath(self.build.path(include_dir));
        other.linkLibrary(self.step);
    }
};

pub fn create(
    b: *std.Build, 
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) Library {
    const lib = b.addStaticLibrary(.{
        .name = "ssh2",
        .target = target,
        .optimize = optimize,
    });

    // Add include paths
    lib.addIncludePath(b.path(include_dir));
    lib.addIncludePath(b.path("deps/libssh2/src")); // For internal headers
    lib.addIncludePath(b.path("deps/libssh2_config")); // For libssh2_config.h

    // Add all source files
    lib.addCSourceFiles(.{ .files = srcs, .flags = &.{} });
    lib.linkLibC();

    // Configure for mbedTLS backend
    lib.root_module.addCMacro("LIBSSH2_MBEDTLS", "1");

    // Platform-specific configuration
    if (target.result.os.tag == .windows) {
        lib.root_module.addCMacro("_CRT_SECURE_NO_DEPRECATE", "1");
        lib.root_module.addCMacro("HAVE_LIBCRYPT32", "1");
        lib.root_module.addCMacro("HAVE_WINSOCK2_H", "1");
        lib.root_module.addCMacro("HAVE_IOCTLSOCKET", "1");
        lib.root_module.addCMacro("HAVE_SELECT", "1");
        lib.root_module.addCMacro("LIBSSH2_DH_GEX_NEW", "1");

        if (target.result.abi.isGnu()) {
            lib.root_module.addCMacro("HAVE_UNISTD_H", "1");
            lib.root_module.addCMacro("HAVE_INTTYPES_H", "1");
            lib.root_module.addCMacro("HAVE_SYS_TIME_H", "1");
            lib.root_module.addCMacro("HAVE_GETTIMEOFDAY", "1");
        }
    } else {
        // Unix-like systems (Linux, macOS, etc.)
        lib.root_module.addCMacro("HAVE_UNISTD_H", "1");
        lib.root_module.addCMacro("HAVE_INTTYPES_H", "1");
        lib.root_module.addCMacro("HAVE_STDLIB_H", "1");
        lib.root_module.addCMacro("HAVE_SYS_SELECT_H", "1");
        lib.root_module.addCMacro("HAVE_SYS_UIO_H", "1");
        lib.root_module.addCMacro("HAVE_SYS_SOCKET_H", "1");
        lib.root_module.addCMacro("HAVE_SYS_IOCTL_H", "1");
        lib.root_module.addCMacro("HAVE_SYS_TIME_H", "1");
        lib.root_module.addCMacro("HAVE_SYS_UN_H", "1");
        lib.root_module.addCMacro("HAVE_LONGLONG", "1");
        lib.root_module.addCMacro("HAVE_GETTIMEOFDAY", "1");
        lib.root_module.addCMacro("HAVE_INET_ADDR", "1");
        lib.root_module.addCMacro("HAVE_POLL", "1");
        lib.root_module.addCMacro("HAVE_SELECT", "1");
        lib.root_module.addCMacro("HAVE_SOCKET", "1");
        lib.root_module.addCMacro("HAVE_STRTOLL", "1");
        lib.root_module.addCMacro("HAVE_SNPRINTF", "1");
        lib.root_module.addCMacro("HAVE_O_NONBLOCK", "1");
    }

    return Library{ .step = lib, .build = b };
}