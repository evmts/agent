/**
 * Downloads the webui prebuilt library for the current platform.
 */

import { existsSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";

const WEBUI_VERSION = "2.5.0-beta.3";
const BASE_URL = `https://github.com/webui-dev/webui/releases/download/${WEBUI_VERSION}`;

const PLATFORM_MAP: Record<string, { archive: string; lib: string }> = {
  "darwin-arm64": {
    archive: "webui-macos-clang-arm64.zip",
    lib: "webui-2.dylib",
  },
  "darwin-x64": {
    archive: "webui-macos-clang-x64.zip",
    lib: "webui-2.dylib",
  },
  "linux-x64": {
    archive: "webui-linux-gcc-x64.zip",
    lib: "webui-2.so",
  },
  "linux-arm64": {
    archive: "webui-linux-gcc-arm64.zip",
    lib: "webui-2.so",
  },
  "win32-x64": {
    archive: "webui-windows-msvc-x64.zip",
    lib: "webui-2.dll",
  },
};

async function main() {
  const platform = process.platform;
  const arch = process.arch;
  const key = `${platform}-${arch}`;

  const config = PLATFORM_MAP[key];
  if (!config) {
    console.error(`Unsupported platform: ${key}`);
    console.error(`Supported platforms: ${Object.keys(PLATFORM_MAP).join(", ")}`);
    process.exit(1);
  }

  const libDir = join(import.meta.dirname, "..", "lib");
  const libPath = join(libDir, config.lib);

  // Skip if already downloaded
  if (existsSync(libPath)) {
    console.log(`WebUI library already exists at ${libPath}`);
    return;
  }

  await mkdir(libDir, { recursive: true });

  const archiveUrl = `${BASE_URL}/${config.archive}`;
  const archivePath = join(libDir, config.archive);

  console.log(`Downloading WebUI ${WEBUI_VERSION} for ${key}...`);
  console.log(`URL: ${archiveUrl}`);

  // Download the archive
  const response = await fetch(archiveUrl);
  if (!response.ok) {
    throw new Error(`Failed to download: ${response.status} ${response.statusText}`);
  }

  const arrayBuffer = await response.arrayBuffer();
  await Bun.write(archivePath, arrayBuffer);
  console.log(`Downloaded to ${archivePath}`);

  // Extract the archive
  console.log("Extracting archive...");
  const proc = Bun.spawn(["unzip", "-o", archivePath, "-d", libDir], {
    stdout: "inherit",
    stderr: "inherit",
  });
  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    throw new Error(`Failed to extract archive: exit code ${exitCode}`);
  }

  // Find and move the library file
  // The archive structure is usually: webui-<platform>/libwebui-2.dylib
  const extractedDir = join(libDir, config.archive.replace(".zip", ""));
  const extractedLib = join(extractedDir, config.lib);

  if (existsSync(extractedLib)) {
    const { rename } = await import("node:fs/promises");
    await rename(extractedLib, libPath);
    console.log(`Moved library to ${libPath}`);
  } else {
    // Try to find it recursively
    const findProc = Bun.spawn(["find", libDir, "-name", config.lib], {
      stdout: "pipe",
    });
    const output = await new Response(findProc.stdout).text();
    const foundPath = output.trim().split("\n")[0];

    if (foundPath && existsSync(foundPath)) {
      const { rename } = await import("node:fs/promises");
      await rename(foundPath, libPath);
      console.log(`Moved library to ${libPath}`);
    } else {
      console.error(`Could not find ${config.lib} in extracted archive`);
      console.log("Archive contents:");
      Bun.spawn(["ls", "-la", libDir], { stdout: "inherit" });
    }
  }

  // Cleanup
  const { rm } = await import("node:fs/promises");
  await rm(archivePath, { force: true });
  await rm(extractedDir, { recursive: true, force: true }).catch(() => {});

  console.log("WebUI library ready!");
}

main().catch((err) => {
  console.error("Failed to download WebUI:", err);
  process.exit(1);
});
