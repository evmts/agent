/**
 * WebUI - High-level TypeScript wrapper for the webui FFI bindings.
 *
 * Provides an ergonomic API for creating native desktop windows
 * that render web content using the system's installed browsers.
 */

import {
  symbols,
  ptrToString,
  Browser,
  Runtime,
  Config,
  type BrowserType,
  type RuntimeType,
  type ConfigType,
} from "./ffi";
import { ptr, } from "bun:ffi";

export { Browser, Runtime, Config };

export interface WindowOptions {
  /** Window width in pixels */
  width?: number;
  /** Window height in pixels */
  height?: number;
  /** Minimum window width */
  minWidth?: number;
  /** Minimum window height */
  minHeight?: number;
  /** Window X position */
  x?: number;
  /** Window Y position */
  y?: number;
  /** Start window hidden */
  hidden?: boolean;
  /** Enable kiosk/fullscreen mode */
  kiosk?: boolean;
  /** Preferred browser */
  browser?: BrowserType;
  /** Use WebView instead of browser */
  webview?: boolean;
  /** Custom server port */
  port?: number;
  /** Browser profile name */
  profileName?: string;
  /** Browser profile path */
  profilePath?: string;
  /** Make the window publicly accessible */
  public?: boolean;
  /** Proxy server URL */
  proxy?: string;
  /** JavaScript runtime (for .js/.ts files) */
  runtime?: RuntimeType;
  /** Root folder for serving files */
  rootFolder?: string;
  /** Window icon (SVG content) */
  icon?: string;
  /** Icon MIME type */
  iconType?: string;
}

/**
 * Represents a WebUI window.
 */
export class Window {
  private id: bigint;
  private destroyed = false;

  constructor(options: WindowOptions = {}) {
    this.id = symbols.webui_new_window();
    this.applyOptions(options);
  }

  private applyOptions(options: WindowOptions) {
    if (options.width !== undefined && options.height !== undefined) {
      this.setSize(options.width, options.height);
    }

    if (options.minWidth !== undefined && options.minHeight !== undefined) {
      this.setMinimumSize(options.minWidth, options.minHeight);
    }

    if (options.x !== undefined && options.y !== undefined) {
      this.setPosition(options.x, options.y);
    }

    if (options.hidden !== undefined) {
      this.setHidden(options.hidden);
    }

    if (options.kiosk !== undefined) {
      this.setKiosk(options.kiosk);
    }

    if (options.port !== undefined) {
      this.setPort(options.port);
    }

    if (options.profileName !== undefined || options.profilePath !== undefined) {
      this.setProfile(options.profileName ?? "", options.profilePath ?? "");
    }

    if (options.public !== undefined) {
      this.setPublic(options.public);
    }

    if (options.proxy !== undefined) {
      this.setProxy(options.proxy);
    }

    if (options.runtime !== undefined) {
      this.setRuntime(options.runtime);
    }

    if (options.rootFolder !== undefined) {
      this.setRootFolder(options.rootFolder);
    }

    if (options.icon !== undefined) {
      this.setIcon(options.icon, options.iconType ?? "image/svg+xml");
    }
  }

  /**
   * Get the raw window ID (for advanced usage).
   */
  get windowId(): bigint {
    return this.id;
  }

  /**
   * Display the window with HTML content, a file path, or a URL.
   * @param content - HTML string, file path, or URL
   * @returns true if the browser launched successfully
   */
  show(content: string): boolean {
    this.ensureNotDestroyed();
    const buffer = Buffer.from(`${content}\0`, "utf8");
    return symbols.webui_show(this.id, ptr(buffer));
  }

  /**
   * Display the window with a specific browser.
   * @param content - HTML string, file path, or URL
   * @param browser - Browser to use
   * @returns true if the browser launched successfully
   */
  showBrowser(content: string, browser: BrowserType): boolean {
    this.ensureNotDestroyed();
    const buffer = Buffer.from(`${content}\0`, "utf8");
    return symbols.webui_show_browser(this.id, ptr(buffer), BigInt(browser));
  }

  /**
   * Display the window using WebView instead of a browser.
   * @param content - HTML string, file path, or URL
   * @returns true if WebView launched successfully
   */
  showWebView(content: string): boolean {
    this.ensureNotDestroyed();
    const buffer = Buffer.from(`${content}\0`, "utf8");
    return symbols.webui_show_wv(this.id, ptr(buffer));
  }

  /**
   * Navigate to a URL.
   * @param url - URL to navigate to
   */
  navigate(url: string): void {
    this.ensureNotDestroyed();
    const buffer = Buffer.from(`${url}\0`, "utf8");
    symbols.webui_navigate(this.id, ptr(buffer));
  }

  /**
   * Set window size.
   */
  setSize(width: number, height: number): void {
    this.ensureNotDestroyed();
    symbols.webui_set_size(this.id, width, height);
  }

  /**
   * Set minimum window size.
   */
  setMinimumSize(width: number, height: number): void {
    this.ensureNotDestroyed();
    symbols.webui_set_minimum_size(this.id, width, height);
  }

  /**
   * Set window position.
   */
  setPosition(x: number, y: number): void {
    this.ensureNotDestroyed();
    symbols.webui_set_position(this.id, x, y);
  }

  /**
   * Set window visibility.
   */
  setHidden(hidden: boolean): void {
    this.ensureNotDestroyed();
    symbols.webui_set_hide(this.id, hidden);
  }

  /**
   * Enable or disable kiosk/fullscreen mode.
   */
  setKiosk(enabled: boolean): void {
    this.ensureNotDestroyed();
    symbols.webui_set_kiosk(this.id, enabled);
  }

  /**
   * Set a custom server port.
   * @returns true if the port was set successfully
   */
  setPort(port: number): boolean {
    this.ensureNotDestroyed();
    return symbols.webui_set_port(this.id, BigInt(port));
  }

  /**
   * Get the current server port.
   */
  getPort(): number {
    this.ensureNotDestroyed();
    return Number(symbols.webui_get_port(this.id));
  }

  /**
   * Set browser profile.
   */
  setProfile(name: string, path: string): void {
    this.ensureNotDestroyed();
    const nameBuffer = Buffer.from(`${name}\0`, "utf8");
    const pathBuffer = Buffer.from(`${path}\0`, "utf8");
    symbols.webui_set_profile(this.id, ptr(nameBuffer), ptr(pathBuffer));
  }

  /**
   * Set proxy server.
   */
  setProxy(proxyUrl: string): void {
    this.ensureNotDestroyed();
    const buffer = Buffer.from(`${proxyUrl}\0`, "utf8");
    symbols.webui_set_proxy(this.id, ptr(buffer));
  }

  /**
   * Make the window publicly accessible.
   */
  setPublic(enabled: boolean): void {
    this.ensureNotDestroyed();
    symbols.webui_set_public(this.id, enabled);
  }

  /**
   * Set JavaScript runtime.
   */
  setRuntime(runtime: RuntimeType): void {
    this.ensureNotDestroyed();
    symbols.webui_set_runtime(this.id, BigInt(runtime));
  }

  /**
   * Set root folder for serving files.
   * @returns true if the folder was set successfully
   */
  setRootFolder(path: string): boolean {
    this.ensureNotDestroyed();
    const buffer = Buffer.from(`${path}\0`, "utf8");
    return symbols.webui_set_root_folder(this.id, ptr(buffer));
  }

  /**
   * Set window icon.
   */
  setIcon(icon: string, iconType: string = "image/svg+xml"): void {
    this.ensureNotDestroyed();
    const iconBuffer = Buffer.from(`${icon}\0`, "utf8");
    const typeBuffer = Buffer.from(`${iconType}\0`, "utf8");
    symbols.webui_set_icon(this.id, ptr(iconBuffer), ptr(typeBuffer));
  }

  /**
   * Execute JavaScript asynchronously.
   */
  run(script: string): void {
    this.ensureNotDestroyed();
    const buffer = Buffer.from(`${script}\0`, "utf8");
    symbols.webui_run(this.id, ptr(buffer));
  }

  /**
   * Execute JavaScript and wait for the result.
   * @param script - JavaScript code to execute
   * @param timeout - Timeout in seconds (default: 30)
   * @returns The result string, or null on error/timeout
   */
  script(script: string, timeout: number = 30): string | null {
    this.ensureNotDestroyed();
    const scriptBuffer = Buffer.from(`${script}\0`, "utf8");
    const bufferSize = 8192;
    const resultBuffer = Buffer.alloc(bufferSize);

    const success = symbols.webui_script(
      this.id,
      ptr(scriptBuffer),
      BigInt(timeout),
      ptr(resultBuffer),
      BigInt(bufferSize)
    );

    if (!success) return null;

    // Find null terminator
    let end = resultBuffer.indexOf(0);
    if (end === -1) end = bufferSize;
    return resultBuffer.toString("utf8", 0, end);
  }

  /**
   * Get the window URL.
   */
  getUrl(): string | null {
    this.ensureNotDestroyed();
    const urlPtr = symbols.webui_get_url(this.id);
    if (!urlPtr) return null;
    return ptrToString(urlPtr);
  }

  /**
   * Start the server without opening a browser window.
   * @param content - HTML content or file path
   * @returns The server URL
   */
  startServer(content: string): string | null {
    this.ensureNotDestroyed();
    const buffer = Buffer.from(`${content}\0`, "utf8");
    const urlPtr = symbols.webui_start_server(this.id, ptr(buffer));
    if (!urlPtr) return null;
    return ptrToString(urlPtr);
  }

  /**
   * Check if the window is shown.
   */
  isShown(): boolean {
    this.ensureNotDestroyed();
    return symbols.webui_is_shown(this.id);
  }

  /**
   * Get the best available browser.
   */
  getBestBrowser(): BrowserType {
    this.ensureNotDestroyed();
    return Number(symbols.webui_get_best_browser(this.id)) as BrowserType;
  }

  /**
   * Get parent process ID.
   */
  getParentProcessId(): number {
    this.ensureNotDestroyed();
    return Number(symbols.webui_get_parent_process_id(this.id));
  }

  /**
   * Get child (browser) process ID.
   */
  getChildProcessId(): number {
    this.ensureNotDestroyed();
    return Number(symbols.webui_get_child_process_id(this.id));
  }

  /**
   * Delete browser profile associated with this window.
   */
  deleteProfile(): void {
    this.ensureNotDestroyed();
    symbols.webui_delete_profile(this.id);
  }

  /**
   * Close the window but keep the window object for reuse.
   */
  close(): void {
    this.ensureNotDestroyed();
    symbols.webui_close(this.id);
  }

  /**
   * Destroy the window and free all resources.
   */
  destroy(): void {
    if (this.destroyed) return;
    symbols.webui_destroy(this.id);
    this.destroyed = true;
  }

  private ensureNotDestroyed() {
    if (this.destroyed) {
      throw new Error("Window has been destroyed");
    }
  }
}

/**
 * Global WebUI functions.
 */
export const webui = {
  /**
   * Wait until all windows are closed.
   */
  wait(): void {
    symbols.webui_wait();
  },

  /**
   * Close all windows and exit.
   */
  exit(): void {
    symbols.webui_exit();
  },

  /**
   * Set the connection timeout in seconds.
   * Use 0 for infinite timeout.
   */
  setTimeout(seconds: number): void {
    symbols.webui_set_timeout(BigInt(seconds));
  },

  /**
   * Set a global configuration option.
   */
  setConfig(option: ConfigType, status: boolean): void {
    symbols.webui_set_config(BigInt(option), status);
  },

  /**
   * Set the default root folder for all windows.
   */
  setDefaultRootFolder(path: string): boolean {
    const buffer = Buffer.from(`${path}\0`, "utf8");
    return symbols.webui_set_default_root_folder(ptr(buffer));
  },

  /**
   * Set TLS certificate.
   * @param cert - Certificate PEM content (or empty for self-signed)
   * @param key - Private key PEM content (or empty for self-signed)
   */
  setTlsCertificate(cert: string, key: string): boolean {
    const certBuffer = Buffer.from(`${cert}\0`, "utf8");
    const keyBuffer = Buffer.from(`${key}\0`, "utf8");
    return symbols.webui_set_tls_certificate(ptr(certBuffer), ptr(keyBuffer));
  },

  /**
   * Check if a browser is installed.
   */
  browserExists(browser: BrowserType): boolean {
    return symbols.webui_browser_exist(BigInt(browser));
  },

  /**
   * Delete all browser profiles.
   */
  deleteAllProfiles(): void {
    symbols.webui_delete_all_profiles();
  },

  /**
   * Get a free network port.
   */
  getFreePort(): number {
    return Number(symbols.webui_get_free_port());
  },

  /**
   * Open a URL in the default browser.
   */
  openUrl(url: string): void {
    const buffer = Buffer.from(`${url}\0`, "utf8");
    symbols.webui_open_url(ptr(buffer));
  },

  /**
   * Check if the application is still running.
   */
  isAppRunning(): boolean {
    return symbols.webui_interface_is_app_running();
  },

  /**
   * Clean up all resources.
   * Call this at application exit.
   */
  clean(): void {
    symbols.webui_clean();
  },

  /**
   * Encode a string to Base64.
   */
  encode(str: string): string | null {
    const buffer = Buffer.from(`${str}\0`, "utf8");
    const resultPtr = symbols.webui_encode(ptr(buffer));
    if (!resultPtr) return null;
    const result = ptrToString(resultPtr);
    symbols.webui_free(resultPtr);
    return result;
  },

  /**
   * Decode a Base64 string.
   */
  decode(str: string): string | null {
    const buffer = Buffer.from(`${str}\0`, "utf8");
    const resultPtr = symbols.webui_decode(ptr(buffer));
    if (!resultPtr) return null;
    const result = ptrToString(resultPtr);
    symbols.webui_free(resultPtr);
    return result;
  },
};
