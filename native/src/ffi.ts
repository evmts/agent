/**
 * WebUI FFI bindings for Bun.
 *
 * This module provides low-level FFI bindings to the webui C library.
 * For a higher-level API, use the WebUI class from ./webui.ts
 */

import { dlopen, FFIType, type ptr, CString, } from "bun:ffi";
import { join } from "node:path";

// Platform-specific library name
const libName =
  process.platform === "win32"
    ? "webui-2.dll"
    : process.platform === "darwin"
      ? "webui-2.dylib"
      : "webui-2.so";

const libPath = join(import.meta.dirname, "..", "lib", libName);

// Browser enum values
export const Browser = {
  NoBrowser: 0,
  AnyBrowser: 1,
  Chrome: 2,
  Firefox: 3,
  Edge: 4,
  Safari: 5,
  Chromium: 6,
  Opera: 7,
  Brave: 8,
  Vivaldi: 9,
  Epic: 10,
  Yandex: 11,
  ChromiumBased: 12,
  WebView: 13,
} as const;

export type BrowserType = (typeof Browser)[keyof typeof Browser];

// Runtime enum values
export const Runtime = {
  None: 0,
  Deno: 1,
  NodeJS: 2,
  Bun: 3,
} as const;

export type RuntimeType = (typeof Runtime)[keyof typeof Runtime];

// Event types
export const EventType = {
  Disconnected: 0,
  Connected: 1,
  MouseClick: 2,
  Navigation: 3,
  Callback: 4,
} as const;

export type EventTypeValue = (typeof EventType)[keyof typeof EventType];

// Config options
export const Config = {
  ShowWaitConnection: 0,
  UiEventBlocking: 1,
  FolderMonitor: 2,
  MultiClient: 3,
  UseHttps: 4,
} as const;

export type ConfigType = (typeof Config)[keyof typeof Config];

// Load the library
const lib = dlopen(libPath, {
  // Window management
  webui_new_window: {
    args: [],
    returns: FFIType.u64,
  },
  webui_new_window_id: {
    args: [FFIType.u64],
    returns: FFIType.u64,
  },
  webui_get_new_window_id: {
    args: [],
    returns: FFIType.u64,
  },
  webui_destroy: {
    args: [FFIType.u64],
    returns: FFIType.void,
  },
  webui_close: {
    args: [FFIType.u64],
    returns: FFIType.void,
  },

  // Display
  webui_show: {
    args: [FFIType.u64, FFIType.cstring],
    returns: FFIType.bool,
  },
  webui_show_browser: {
    args: [FFIType.u64, FFIType.cstring, FFIType.u64],
    returns: FFIType.bool,
  },
  webui_show_wv: {
    args: [FFIType.u64, FFIType.cstring],
    returns: FFIType.bool,
  },
  webui_navigate: {
    args: [FFIType.u64, FFIType.cstring],
    returns: FFIType.void,
  },

  // Window configuration
  webui_set_size: {
    args: [FFIType.u64, FFIType.u32, FFIType.u32],
    returns: FFIType.void,
  },
  webui_set_minimum_size: {
    args: [FFIType.u64, FFIType.u32, FFIType.u32],
    returns: FFIType.void,
  },
  webui_set_position: {
    args: [FFIType.u64, FFIType.u32, FFIType.u32],
    returns: FFIType.void,
  },
  webui_set_hide: {
    args: [FFIType.u64, FFIType.bool],
    returns: FFIType.void,
  },
  webui_set_kiosk: {
    args: [FFIType.u64, FFIType.bool],
    returns: FFIType.void,
  },
  webui_set_port: {
    args: [FFIType.u64, FFIType.u64],
    returns: FFIType.bool,
  },
  webui_get_port: {
    args: [FFIType.u64],
    returns: FFIType.u64,
  },

  // Profile & Browser
  webui_set_profile: {
    args: [FFIType.u64, FFIType.cstring, FFIType.cstring],
    returns: FFIType.void,
  },
  webui_set_proxy: {
    args: [FFIType.u64, FFIType.cstring],
    returns: FFIType.void,
  },
  webui_get_best_browser: {
    args: [FFIType.u64],
    returns: FFIType.u64,
  },
  webui_browser_exist: {
    args: [FFIType.u64],
    returns: FFIType.bool,
  },
  webui_delete_profile: {
    args: [FFIType.u64],
    returns: FFIType.void,
  },
  webui_delete_all_profiles: {
    args: [],
    returns: FFIType.void,
  },

  // Event loop
  webui_wait: {
    args: [],
    returns: FFIType.void,
  },
  webui_exit: {
    args: [],
    returns: FFIType.void,
  },
  webui_is_shown: {
    args: [FFIType.u64],
    returns: FFIType.bool,
  },

  // JavaScript
  webui_run: {
    args: [FFIType.u64, FFIType.cstring],
    returns: FFIType.void,
  },
  webui_script: {
    args: [FFIType.u64, FFIType.cstring, FFIType.u64, FFIType.ptr, FFIType.u64],
    returns: FFIType.bool,
  },

  // Binding (using interface version for FFI compatibility)
  webui_interface_bind: {
    args: [FFIType.u64, FFIType.cstring, FFIType.function],
    returns: FFIType.u64,
  },
  webui_interface_set_response: {
    args: [FFIType.u64, FFIType.u64, FFIType.cstring],
    returns: FFIType.void,
  },
  webui_interface_is_app_running: {
    args: [],
    returns: FFIType.bool,
  },

  // Content & Server
  webui_start_server: {
    args: [FFIType.u64, FFIType.cstring],
    returns: FFIType.ptr,
  },
  webui_set_root_folder: {
    args: [FFIType.u64, FFIType.cstring],
    returns: FFIType.bool,
  },
  webui_set_default_root_folder: {
    args: [FFIType.cstring],
    returns: FFIType.bool,
  },
  webui_get_url: {
    args: [FFIType.u64],
    returns: FFIType.ptr,
  },

  // Configuration
  webui_set_timeout: {
    args: [FFIType.u64],
    returns: FFIType.void,
  },
  webui_set_config: {
    args: [FFIType.u64, FFIType.bool],
    returns: FFIType.void,
  },
  webui_set_runtime: {
    args: [FFIType.u64, FFIType.u64],
    returns: FFIType.void,
  },
  webui_set_public: {
    args: [FFIType.u64, FFIType.bool],
    returns: FFIType.void,
  },

  // TLS
  webui_set_tls_certificate: {
    args: [FFIType.cstring, FFIType.cstring],
    returns: FFIType.bool,
  },

  // Icon
  webui_set_icon: {
    args: [FFIType.u64, FFIType.cstring, FFIType.cstring],
    returns: FFIType.void,
  },

  // Process info
  webui_get_parent_process_id: {
    args: [FFIType.u64],
    returns: FFIType.u64,
  },
  webui_get_child_process_id: {
    args: [FFIType.u64],
    returns: FFIType.u64,
  },

  // Memory
  webui_malloc: {
    args: [FFIType.u64],
    returns: FFIType.ptr,
  },
  webui_free: {
    args: [FFIType.ptr],
    returns: FFIType.void,
  },

  // Utility
  webui_clean: {
    args: [],
    returns: FFIType.void,
  },
  webui_encode: {
    args: [FFIType.cstring],
    returns: FFIType.ptr,
  },
  webui_decode: {
    args: [FFIType.cstring],
    returns: FFIType.ptr,
  },
  webui_get_free_port: {
    args: [],
    returns: FFIType.u64,
  },
  webui_open_url: {
    args: [FFIType.cstring],
    returns: FFIType.void,
  },
});

export const symbols = lib.symbols;

/**
 * Convert a pointer to a string
 */
export function ptrToString(pointer: ReturnType<typeof ptr>): string | null {
  if (!pointer) return null;
  return new CString(pointer).toString();
}

/**
 * Close the library and free resources
 */
export function close() {
  lib.close();
}
