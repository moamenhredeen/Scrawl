# ZigDraw

A minimal, fast drawing app built with **Zig**, **raylib**, and **raygui**. Infinite canvas, multiple tools, undo/redo, light/dark themes, and binary file save/load.

## Features

- **6 drawing tools** — Select, Rectangle, Ellipse, Line, Arrow, Freehand
- **Infinite canvas** — Pan (middle-click or Space+drag) and zoom (scroll wheel)
- **Multi-select** — Shift+click to toggle, rubber-band marquee selection, drag multiple shapes
- **Undo/Redo** — Ctrl+Z / Ctrl+Y (up to 50 states)
- **Light/Dark theme** — Toggle from the toolbar
- **Save/Load** — Binary `.zdraw` format with Ctrl+S / Ctrl+O command bar
- **Tab completion** — File path autocomplete in the save/load command bar
- **8 color presets** and **5 stroke widths**
- **Cross-platform** — Windows, Linux, macOS

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `V` | Select tool |
| `R` | Rectangle tool |
| `O` | Ellipse tool |
| `L` | Line tool |
| `A` | Arrow tool |
| `P` | Pen (freehand) tool |
| `Ctrl+Z` | Undo |
| `Ctrl+Y` | Redo |
| `Ctrl+S` | Save (direct if file open, otherwise prompts) |
| `Ctrl+O` | Open file |
| `Delete` | Delete selected shapes |
| `Escape` | Cancel drawing / reset tool / deselect |
| `Space+Drag` | Pan canvas |
| `Scroll` | Zoom in/out |
| `Tab` | Autocomplete path in command bar |

## Building

Requires [Zig 0.15.2](https://ziglang.org/download/).

```sh
zig build run
```

Cross-compile for other targets:

```sh
zig build -Dtarget=x86_64-windows
zig build -Dtarget=x86_64-linux
zig build -Dtarget=aarch64-macos
```

## Tech Stack

- [Zig 0.15.2](https://ziglang.org/)
- [raylib](https://www.raylib.com/) via [raylib-zig](https://github.com/raylib-zig/raylib-zig)
- [raygui](https://github.com/raysan5/raygui) — immediate-mode GUI

## License

MIT
