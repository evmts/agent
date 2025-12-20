/**
 * Simple test script for WebUI bindings.
 *
 * Run with: bun run native/test.ts
 */

import { Window, webui, Browser } from "./index";

console.log("WebUI Test");
console.log("===========\n");

// Check available browsers
console.log("Checking browsers:");
for (const [name, id] of Object.entries(Browser)) {
  if (typeof id === "number" && id > 0 && id < 13) {
    const exists = webui.browserExists(id);
    if (exists) {
      console.log(`  [x] ${name}`);
    }
  }
}
console.log();

// Create window
console.log("Creating window...");
const win = new Window({
  width: 1000,
  height: 700,
});

const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Plue Native Test</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #0d0d0d;
      color: #e0e0e0;
      font-family: ui-monospace, 'SF Mono', 'Cascadia Code', monospace;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 2rem;
    }
    h1 {
      font-size: 3rem;
      margin-bottom: 1rem;
      background: linear-gradient(135deg, #fff 0%, #888 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .info {
      background: #1a1a1a;
      border: 1px solid #333;
      padding: 2rem;
      border-radius: 8px;
      max-width: 600px;
      width: 100%;
    }
    .info p {
      margin: 0.5rem 0;
      line-height: 1.6;
    }
    .info code {
      background: #262626;
      padding: 0.2rem 0.5rem;
      border-radius: 4px;
      font-size: 0.9em;
    }
    button {
      margin-top: 1.5rem;
      padding: 0.75rem 1.5rem;
      background: #333;
      border: 1px solid #444;
      color: #fff;
      font-family: inherit;
      font-size: 1rem;
      border-radius: 4px;
      cursor: pointer;
      transition: all 0.2s;
    }
    button:hover {
      background: #444;
      border-color: #555;
    }
  </style>
</head>
<body>
  <h1>Plue Native</h1>
  <div class="info">
    <p>WebUI bindings are working correctly.</p>
    <p>Platform: <code>${process.platform}</code></p>
    <p>Architecture: <code>${process.arch}</code></p>
    <p>Bun version: <code>${Bun.version}</code></p>
    <button onclick="closeWindow()">Close Window</button>
  </div>
  <script>
    function closeWindow() {
      // This will call back to the Bun process
      window.close();
    }
  </script>
</body>
</html>
`;

console.log("Showing window with Chrome...");
let success = win.showBrowser(html, Browser.Chrome);

if (!success) {
  console.log("Chrome failed, trying any browser...");
  success = win.show(html);
}

if (success) {
  console.log("Window opened successfully!");
  console.log("Close the browser window to exit.\n");
  webui.wait();
  console.log("Window closed.");
} else {
  console.log("Failed to open window.");
  console.log("This might happen if no compatible browser is found.");
}

// Cleanup
win.destroy();
webui.clean();

console.log("Test complete!");
