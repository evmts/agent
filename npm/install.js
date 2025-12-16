#!/usr/bin/env node

const https = require("https");
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
const zlib = require("zlib");

const REPO = "williamcory/agent";
const BINARY_NAME = "agent";

const PLATFORM_MAP = {
  darwin: "darwin",
  linux: "linux",
};

const ARCH_MAP = {
  x64: "amd64",
  arm64: "arm64",
};

function getPlatformArch() {
  const platform = PLATFORM_MAP[process.platform];
  const arch = ARCH_MAP[process.arch];

  if (!platform) {
    throw new Error(`Unsupported platform: ${process.platform}`);
  }
  if (!arch) {
    throw new Error(`Unsupported architecture: ${process.arch}`);
  }

  return `${platform}-${arch}`;
}

function getPackageVersion() {
  const packageJson = JSON.parse(
    fs.readFileSync(path.join(__dirname, "package.json"), "utf8")
  );
  return packageJson.version;
}

function getBinaryPath() {
  return path.join(__dirname, "bin", BINARY_NAME);
}

function downloadFile(url) {
  return new Promise((resolve, reject) => {
    const request = (url) => {
      https
        .get(url, (response) => {
          if (response.statusCode === 302 || response.statusCode === 301) {
            request(response.headers.location);
            return;
          }

          if (response.statusCode !== 200) {
            reject(new Error(`Failed to download: ${response.statusCode}`));
            return;
          }

          const chunks = [];
          response.on("data", (chunk) => chunks.push(chunk));
          response.on("end", () => resolve(Buffer.concat(chunks)));
          response.on("error", reject);
        })
        .on("error", reject);
    };

    request(url);
  });
}

async function extractTarGz(buffer, destPath) {
  const tmpDir = path.join(__dirname, ".tmp");
  const tmpTarGz = path.join(tmpDir, "archive.tar.gz");
  const tmpTar = path.join(tmpDir, "archive.tar");

  fs.mkdirSync(tmpDir, { recursive: true });

  try {
    fs.writeFileSync(tmpTarGz, buffer);

    const decompressed = zlib.gunzipSync(buffer);
    fs.writeFileSync(tmpTar, decompressed);

    execSync(`tar -xf "${tmpTar}" -C "${tmpDir}"`, { stdio: "pipe" });

    const files = fs.readdirSync(tmpDir);
    const binaryFile = files.find(
      (f) => f.startsWith("agent-") && !f.endsWith(".tar") && !f.endsWith(".gz")
    );

    if (!binaryFile) {
      throw new Error("Binary not found in archive");
    }

    const binDir = path.dirname(destPath);
    fs.mkdirSync(binDir, { recursive: true });

    fs.copyFileSync(path.join(tmpDir, binaryFile), destPath);
    fs.chmodSync(destPath, 0o755);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

async function main() {
  const platformArch = getPlatformArch();
  const version = getPackageVersion();
  const binaryPath = getBinaryPath();

  if (fs.existsSync(binaryPath)) {
    console.log(`@tevm/agent: Binary already exists at ${binaryPath}`);
    return;
  }

  const tarballName = `agent-${platformArch}.tar.gz`;
  const url = `https://github.com/${REPO}/releases/download/v${version}/${tarballName}`;

  console.log(`@tevm/agent: Downloading ${tarballName} for v${version}...`);

  try {
    const buffer = await downloadFile(url);
    console.log(`@tevm/agent: Extracting to ${binaryPath}...`);
    await extractTarGz(buffer, binaryPath);
    console.log(`@tevm/agent: Installation complete!`);
  } catch (error) {
    console.error(`@tevm/agent: Failed to install: ${error.message}`);
    console.error(
      `@tevm/agent: You may need to download manually from https://github.com/${REPO}/releases`
    );
    process.exit(1);
  }
}

main();
