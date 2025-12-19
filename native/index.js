const { existsSync, readFileSync } = require('fs');
const { join } = require('path');

const { platform, arch } = process;

let nativeBinding = null;
let loadError = null;

function isMusl() {
  // For Node 10
  if (!process.report || typeof process.report.getReport !== 'function') {
    try {
      const lddPath = require('child_process').execSync('which ldd').toString().trim();
      return readFileSync(lddPath, 'utf8').includes('musl');
    } catch {
      return true;
    }
  } else {
    const { glibcVersionRuntime } = process.report.getReport().header;
    return !glibcVersionRuntime;
  }
}

switch (platform) {
  case 'darwin':
    switch (arch) {
      case 'x64':
        try {
          nativeBinding = require('./jj-native.darwin-x64.node');
        } catch (e) {
          loadError = e;
        }
        break;
      case 'arm64':
        try {
          nativeBinding = require('./jj-native.darwin-arm64.node');
        } catch (e) {
          loadError = e;
        }
        break;
      default:
        throw new Error(`Unsupported architecture on macOS: ${arch}`);
    }
    break;
  case 'linux':
    switch (arch) {
      case 'x64':
        if (isMusl()) {
          try {
            nativeBinding = require('./jj-native.linux-x64-musl.node');
          } catch (e) {
            loadError = e;
          }
        } else {
          try {
            nativeBinding = require('./jj-native.linux-x64-gnu.node');
          } catch (e) {
            loadError = e;
          }
        }
        break;
      case 'arm64':
        if (isMusl()) {
          try {
            nativeBinding = require('./jj-native.linux-arm64-musl.node');
          } catch (e) {
            loadError = e;
          }
        } else {
          try {
            nativeBinding = require('./jj-native.linux-arm64-gnu.node');
          } catch (e) {
            loadError = e;
          }
        }
        break;
      default:
        throw new Error(`Unsupported architecture on Linux: ${arch}`);
    }
    break;
  default:
    throw new Error(`Unsupported OS: ${platform}, architecture: ${arch}`);
}

if (!nativeBinding) {
  if (loadError) {
    throw loadError;
  }
  throw new Error('Failed to load native binding');
}

const { JjWorkspace, isJjWorkspace, isGitRepo } = nativeBinding;

module.exports.JjWorkspace = JjWorkspace;
module.exports.isJjWorkspace = isJjWorkspace;
module.exports.isGitRepo = isGitRepo;
