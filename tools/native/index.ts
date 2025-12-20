/**
 * @plue/native - Native desktop window wrapper using WebUI.
 *
 * This module provides a native window implementation that renders
 * web content using the system's installed browsers via the WebUI library.
 *
 * @example
 * ```typescript
 * import { Window, webui, Browser } from "@plue/native";
 *
 * const window = new Window({
 *   width: 1200,
 *   height: 800,
 *   center: true,
 * });
 *
 * // Show a URL
 * window.show("http://localhost:4321");
 *
 * // Or show HTML directly
 * window.show("<html><body><h1>Hello!</h1></body></html>");
 *
 * // Wait until window is closed
 * webui.wait();
 * ```
 */

export { Window, webui, Browser, Runtime, Config } from "./src/webui";
export type { WindowOptions } from "./src/webui";
export type { BrowserType, RuntimeType, ConfigType } from "./src/ffi";
