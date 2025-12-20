# Plue Native App (Zig)

Native desktop window for Plue using [zig-webui](https://github.com/webui-dev/zig-webui).

## Building

```bash
cd tools/webui
zig build
```

The binary will be at `zig-out/bin/plue`.

## Usage

1. Start the Astro dev server:
```bash
bun run dev
```

2. Run the native app:
```bash
zig build run
# or directly:
./zig-out/bin/plue
```

## Options

```
--width <px>     Window width (default: 1400)
--height <px>    Window height (default: 900)
--port <port>    Astro dev server port (default: 5173)
--no-wait        Don't wait for server to be ready
-w, --webview    Use WebView instead of browser
-h, --help       Show this help message
```

## Release Build

```bash
zig build -Doptimize=ReleaseFast
```
