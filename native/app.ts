/**
 * Plue Native App Entry Point
 *
 * Launches the Astro frontend in a native WebUI window.
 * The Astro dev server must be running before starting this app.
 *
 * Usage:
 *   # Start Astro dev server first
 *   bun run dev
 *
 *   # Then in another terminal
 *   bun run native/app.ts
 *
 * Or use the combined command:
 *   bun run dev:native
 */

import { Window, webui, Browser } from "./index";
import { spawn } from "bun";

const ASTRO_PORT = 5173;
const API_PORT = 4000;
const ASTRO_URL = `http://localhost:${ASTRO_PORT}`;

interface AppOptions {
  /** Wait for the dev servers to be ready */
  waitForServer?: boolean;
  /** Start dev servers automatically */
  startServers?: boolean;
  /** Window width */
  width?: number;
  /** Window height */
  height?: number;
  /** Use WebView instead of browser */
  webview?: boolean;
  /** Preferred browser */
  browser?: keyof typeof Browser;
}

async function waitForServer(url: string, maxAttempts = 30): Promise<boolean> {
  console.log(`Waiting for ${url} to be ready...`);

  for (let i = 0; i < maxAttempts; i++) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        console.log(`Server at ${url} is ready!`);
        return true;
      }
    } catch {
      // Server not ready yet
    }
    await Bun.sleep(1000);
  }

  console.error(`Server at ${url} failed to start after ${maxAttempts} seconds`);
  return false;
}

async function startDevServers(): Promise<{ astro: ReturnType<typeof spawn>; api: ReturnType<typeof spawn> }> {
  console.log("Starting dev servers...");

  const projectRoot = new URL("..", import.meta.url).pathname;

  const astro = spawn({
    cmd: ["bun", "run", "dev"],
    cwd: projectRoot,
    stdout: "inherit",
    stderr: "inherit",
  });

  const api = spawn({
    cmd: ["bun", "run", "dev:api"],
    cwd: projectRoot,
    stdout: "inherit",
    stderr: "inherit",
  });

  return { astro, api };
}

async function main(options: AppOptions = {}) {
  const {
    waitForServer: shouldWait = true,
    startServers = false,
    width = 1400,
    height = 900,
    webview = false,
    browser,
  } = options;

  let servers: { astro: ReturnType<typeof spawn>; api: ReturnType<typeof spawn> } | null = null;

  // Start servers if requested
  if (startServers) {
    servers = await startDevServers();
  }

  // Wait for the Astro server to be ready
  if (shouldWait) {
    const ready = await waitForServer(ASTRO_URL);
    if (!ready) {
      console.error("Failed to connect to Astro dev server.");
      console.error(`Make sure the server is running: bun run dev`);
      process.exit(1);
    }
  }

  // Create the native window
  console.log("Creating native window...");

  const window = new Window({
    width,
    height,
  });

  // Set a nice icon
  const icon = `
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
      <rect width="100" height="100" fill="#1a1a1a"/>
      <text x="50" y="70" font-size="60" text-anchor="middle" fill="#fff">P</text>
    </svg>
  `;
  window.setIcon(icon.trim());

  // Show the window
  let success: boolean;

  if (webview) {
    console.log("Opening with WebView...");
    success = window.showWebView(ASTRO_URL);
  } else if (browser && browser in Browser) {
    console.log(`Opening with ${browser}...`);
    success = window.showBrowser(ASTRO_URL, Browser[browser as keyof typeof Browser]);
  } else {
    console.log("Opening with best available browser...");
    success = window.show(ASTRO_URL);
  }

  if (!success) {
    console.error("Failed to open browser window");
    process.exit(1);
  }

  console.log(`Plue is running at ${ASTRO_URL}`);
  console.log("Close the browser window to exit.");

  // Wait for the window to be closed
  webui.wait();

  console.log("Window closed. Cleaning up...");

  // Cleanup
  window.destroy();
  webui.clean();

  // Kill dev servers if we started them
  if (servers) {
    servers.astro.kill();
    servers.api.kill();
  }

  console.log("Goodbye!");
}

// Parse CLI arguments
const args = process.argv.slice(2);
const options: AppOptions = {};

for (let i = 0; i < args.length; i++) {
  const arg = args[i];

  if (arg === "--start-servers" || arg === "-s") {
    options.startServers = true;
  } else if (arg === "--no-wait") {
    options.waitForServer = false;
  } else if (arg === "--webview" || arg === "-w") {
    options.webview = true;
  } else if (arg === "--browser" || arg === "-b") {
    options.browser = args[++i] as keyof typeof Browser;
  } else if (arg === "--width") {
    options.width = parseInt(args[++i] ?? '0', 10);
  } else if (arg === "--height") {
    options.height = parseInt(args[++i] ?? '0', 10);
  } else if (arg === "--help" || arg === "-h") {
    console.log(`
Plue Native App

Usage: bun run native/app.ts [options]

Options:
  -s, --start-servers    Start dev servers automatically
  --no-wait              Don't wait for server to be ready
  -w, --webview          Use WebView instead of browser
  -b, --browser <name>   Use specific browser (Chrome, Firefox, Edge, Safari, etc.)
  --width <px>           Window width (default: 1400)
  --height <px>          Window height (default: 900)
  -h, --help             Show this help message

Examples:
  # Start with dev server already running
  bun run native/app.ts

  # Start servers and app together
  bun run native/app.ts --start-servers

  # Use Chrome specifically
  bun run native/app.ts --browser Chrome

  # Use WebView (requires webkit2gtk on Linux)
  bun run native/app.ts --webview
`);
    process.exit(0);
  }
}

main(options).catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
