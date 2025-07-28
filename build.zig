const std = @import("std");

// Asset generation step for GUI
const GenerateAssetsStep = struct {
    step: std.Build.Step,
    dist_path: []const u8,
    out_path: []const u8,

    fn init(b: *std.Build, dist_path: []const u8, out_path: []const u8) *GenerateAssetsStep {
        const self = b.allocator.create(GenerateAssetsStep) catch @panic("OOM");
        self.* = GenerateAssetsStep{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "generate assets",
                .owner = b,
                .makeFn = make,
            }),
            .dist_path = b.dupe(dist_path),
            .out_path = b.dupe(out_path),
        };
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const self: *GenerateAssetsStep = @fieldParentPtr("step", step);
        const b = step.owner;
        const allocator = b.allocator;

        
        // Ensure the output directory exists
        if (std.fs.path.dirname(self.out_path)) |dir_path| {
            std.fs.cwd().makePath(dir_path) catch |err| switch (err) {
                error.PathAlreadyExists => {}, // This is fine
                else => {
                    std.log.err("Failed to create directory: {s}, error: {}", .{ dir_path, err });
                    return err;
                },
            };
        }
        
        var file = try std.fs.cwd().createFile(self.out_path, .{});
        defer file.close();

        var writer = file.writer();

        try writer.writeAll("// This file is auto-generated. Do not edit manually.\n");
        try writer.writeAll("const std = @import(\"std\");\n\n");
        try writer.writeAll("const Self = @This();\n\n");
        try writer.writeAll("path: []const u8,\n");
        try writer.writeAll("content: []const u8,\n");
        try writer.writeAll("mime_type: []const u8,\n");
        try writer.writeAll("response: [:0]const u8,\n\n");

        try writer.writeAll("pub fn init(\n");
        try writer.writeAll("    comptime path: []const u8,\n");
        try writer.writeAll("    comptime content: []const u8,\n");
        try writer.writeAll("    comptime mime_type: []const u8,\n");
        try writer.writeAll(") Self {\n");
        try writer.writeAll("    var buf: [20]u8 = undefined;\n");
        try writer.writeAll("    const n = std.fmt.bufPrint(&buf, \"{d}\", .{content.len}) catch unreachable;\n");
        try writer.writeAll("    const content_length = buf[0..n.len];\n");
        try writer.writeAll("    const response = \"HTTP/1.1 200 OK\\n\" ++\n");
        try writer.writeAll("        \"Content-Type: \" ++ mime_type ++ \"\\n\" ++\n");
        try writer.writeAll("        \"Content-Length: \" ++ content_length ++ \"\\n\" ++\n");
        try writer.writeAll("        \"\\n\" ++\n");
        try writer.writeAll("        content;\n");
        try writer.writeAll("    return Self{\n");
        try writer.writeAll("        .path = path,\n");
        try writer.writeAll("        .content = content,\n");
        try writer.writeAll("        .mime_type = mime_type,\n");
        try writer.writeAll("        .response = response,\n");
        try writer.writeAll("    };\n");
        try writer.writeAll("}\n\n");

        try writer.writeAll("pub const not_found_asset = Self.init(\n");
        try writer.writeAll("    \"/notfound.html\",\n");
        try writer.writeAll("    \"<div>Page not found</div>\",\n");
        try writer.writeAll("    \"text/html\",\n");
        try writer.writeAll(");\n\n");

        try writer.writeAll("pub const assets = [_]Self{\n");

        var dir = try std.fs.cwd().openDir(self.dist_path, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;

            const mime_type = get_mime_type(entry.basename);
            const path = try std.fmt.allocPrint(allocator, "/{s}", .{entry.path});
            defer allocator.free(path);

            try writer.print("    Self.init(\n", .{});
            try writer.print("        \"{s}\",\n", .{path});
            // Make path relative to assets.zig location (which will be in src/generated/)
            // From src/generated/ we need to go ../gui/dist/ to reach the assets
            const relative_path = try std.fmt.allocPrint(allocator, "../gui/dist/{s}", .{entry.path});
            defer allocator.free(relative_path);
            try writer.print("        @embedFile(\"{s}\"),\n", .{relative_path});
            try writer.print("        \"{s}\",\n", .{mime_type});
            try writer.print("    ),\n", .{});
        }

        try writer.writeAll("};\n\n");

        try writer.writeAll("pub fn get_asset(path: []const u8) Self {\n");
        try writer.writeAll("    for (assets) |asset| {\n");
        try writer.writeAll("        if (std.mem.eql(u8, asset.path, path)) {\n");
        try writer.writeAll("            return asset;\n");
        try writer.writeAll("        }\n");
        try writer.writeAll("    }\n");
        try writer.writeAll("    return not_found_asset;\n");
        try writer.writeAll("}\n");
    }

    fn get_mime_type(filename: []const u8) []const u8 {
        if (std.mem.endsWith(u8, filename, ".html")) return "text/html";
        if (std.mem.endsWith(u8, filename, ".js")) return "application/javascript";
        if (std.mem.endsWith(u8, filename, ".css")) return "text/css";
        if (std.mem.endsWith(u8, filename, ".svg")) return "image/svg+xml";
        if (std.mem.endsWith(u8, filename, ".png")) return "image/png";
        if (std.mem.endsWith(u8, filename, ".jpg") or std.mem.endsWith(u8, filename, ".jpeg")) return "image/jpeg";
        if (std.mem.endsWith(u8, filename, ".gif")) return "image/gif";
        if (std.mem.endsWith(u8, filename, ".ico")) return "image/x-icon";
        if (std.mem.endsWith(u8, filename, ".woff")) return "font/woff";
        if (std.mem.endsWith(u8, filename, ".woff2")) return "font/woff2";
        if (std.mem.endsWith(u8, filename, ".ttf")) return "font/ttf";
        if (std.mem.endsWith(u8, filename, ".otf")) return "font/otf";
        if (std.mem.endsWith(u8, filename, ".json")) return "application/json";
        if (std.mem.endsWith(u8, filename, ".xml")) return "application/xml";
        if (std.mem.endsWith(u8, filename, ".pdf")) return "application/pdf";
        if (std.mem.endsWith(u8, filename, ".txt")) return "text/plain";
        return "application/octet-stream";
    }
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Add webui dependency (used by both main exe and GUI exe)
    const webui = b.dependency("webui", .{
        .target = target,
        .optimize = optimize,
        .dynamic = false,
        .@"enable-tls" = false,
        .verbose = .err,
    });

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Modules can depend on one another using the `std.Build.Module.addImport` function.
    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a
    // file path. In this case, we set up `exe_mod` to import `lib_mod`.
    exe_mod.addImport("plue_lib", lib_mod);
    
    const clap = b.dependency("clap", .{});
    exe_mod.addImport("clap", clap.module("clap"));
    
    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("zap", zap.module("zap"));
    
    const pg = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("pg", pg.module("pg"));

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "plue",
        .root_module = lib_mod,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "plue",
        .root_module = exe_mod,
    });

    // Link webui library to main executable (needed for GUI integration)
    exe.linkLibrary(webui.artifact("webui"));
    exe.linkLibC();
    if (target.result.os.tag == .macos) {
        exe.linkFramework("WebKit");
    }

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // GUI asset generation (for main executable)
    // First, check if npm is installed and build the Solid app
    const npm_check = b.addSystemCommand(&[_][]const u8{ "which", "npm" });
    npm_check.addCheck(.{ .expect_stdout_match = "npm" });

    // Install npm dependencies for GUI
    const npm_install = b.addSystemCommand(&[_][]const u8{ "npm", "install" });
    npm_install.setCwd(b.path("src/gui"));
    npm_install.step.dependOn(&npm_check.step);

    // Build the Solid app
    const npm_build = b.addSystemCommand(&[_][]const u8{ "npm", "run", "build" });
    npm_build.setCwd(b.path("src/gui"));
    npm_build.step.dependOn(&npm_install.step);

    // Generate assets from the built Solid app  
    const generate_assets = GenerateAssetsStep.init(b, "src/gui/dist", "src/generated/assets.zig");
    generate_assets.step.dependOn(&npm_build.step);

    // Make main executable depend on asset generation
    exe.step.dependOn(&generate_assets.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    
    // Add dependencies to lib_unit_tests since it imports modules that need them
    lib_unit_tests.root_module.addImport("zap", zap.module("zap"));
    lib_unit_tests.root_module.addImport("pg", pg.module("pg"));
    
    // Link webui library to lib tests (needed for GUI tests)
    lib_unit_tests.linkLibrary(webui.artifact("webui"));
    lib_unit_tests.linkLibC();
    if (target.result.os.tag == .macos) {
        lib_unit_tests.linkFramework("WebKit");
    }

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });
    
    // Add dependencies to exe_unit_tests since it imports modules that need them
    exe_unit_tests.root_module.addImport("zap", zap.module("zap"));
    exe_unit_tests.root_module.addImport("pg", pg.module("pg"));
    exe_unit_tests.root_module.addImport("clap", clap.module("clap"));
    
    // Link webui library to exe tests (needed for GUI tests)
    exe_unit_tests.linkLibrary(webui.artifact("webui"));
    exe_unit_tests.linkLibC();
    if (target.result.os.tag == .macos) {
        exe_unit_tests.linkFramework("WebKit");
    }

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
