# RGB Screen React — Architecture

Color-reactive RGB LED controller for MuOS handheld devices.
LÖVE 11.5 (Lua 5.1 / LuaJIT) frontend + shell script LED daemon.
Entry point: `RGB Screen React/rgbscreenreact/main.lua`.
Backend daemon: `RGB Screen React/rgb_screen_react.sh`.

**Note:** Despite the name, this is not a React.js project. "React" refers to the LEDs reacting to on-screen colors in real-time.

## Overview

Two-component system for MuOS devices (Anbernic, TrimUI) with RGB LED sticks:

1. **LÖVE UI** — A simple settings menu where the user toggles the feature on/off and adjusts brightness (1–10). Renders at 640x480 scaled to device resolution via the `push` library.
2. **Shell daemon** (`rgb_screen_react.sh`) — Runs in the background, samples the Linux framebuffer (`/dev/fb0`), computes a saturation-weighted average color, and drives the RGB LEDs via SYSFS or serial backend. Targets 2% CPU on ARM Cortex-A53 @ 1.5 GHz.

## Data Model

```
settings (global table, persisted to settings.txt)
  ├── mode        — 0=Off, 9=On (Screen React mode)
  └── brightness  — 1–10 (mapped to 0–255 for LED control)

menu (global table)
  └── {"Enabled", "Brightness"}

currentSelection  — index into menu (1-based)
```

Settings are persisted to `/run/muos/storage/theme/active/rgb/settings.txt` as `mode=<value>\nbrightness=<value>`.

## Module Map

### rgbscreenreact/ — LÖVE Application

| File | Owns |
|---|---|
| `main.lua` | Entry point, LÖVE lifecycle (`love.load`, `love.update`, `love.draw`), settings load/save, splash → menu transition, fade-in animation |
| `conf.lua` | LÖVE window config (640x480, no resize, vsync) |
| `draw.lua` | Rendering: animated gradient background (8-color palette, smoothstep lerp), menu items, icons, slider sprite, selection indicator, fade overlay |
| `input.lua` | Joystick/gamepad input: D-pad navigation, value changes, cooldown timer, triggers `command.run()` and `saveSettings()` on change |
| `tables.lua` | Global data structures: `settings`, `menu` tables |
| `command.lua` | Executes shell commands to start/stop the daemon and apply LED settings |
| `soundmanager.lua` | Loads and plays pixel-art UI sound effects (cursor, select) |
| `splash.lua` | MuOS logo splash: elastic scale-up (0.3s), hold, fade-out (0.2s), callback to start menu |
| `timer.lua` | Third-party tweening/coroutine library (MIT). Easing functions: linear, cubic, back, bounce, elastic, etc. |
| `push.lua` | Third-party resolution scaling library v0.4 (MIT). Maps 640x480 game space to actual device resolution |

### Shell Scripts

| File | Owns |
|---|---|
| `rgb_screen_react.sh` | Background daemon (~670 lines). Framebuffer sampling, saturation-weighted color averaging, adaptive color boosting, exponential LED smoothing, dual-stick support, battery/idle protection, SYSFS and serial LED backends |
| `mux_launch.sh` | MuOS launcher: environment setup, CPU governor, SDL config, gptokeyb2 keyboard mapping, launches `./love rgbscreenreact` |

### Assets

| Directory | Contents |
|---|---|
| `assets/fonts/` | Peaberry-Base.otf — pixel art font (used at 32px and 16px, nearest-neighbor filter) |
| `assets/sprites/` | background.png, brightness.png, enabled.png, muos.png (splash), slider.png (10-frame sprite sheet) |
| `assets/sounds/` | Pixel UI SFX Pack by JDSherbert (cursor, select sounds) |

### Runtime

| File | Purpose |
|---|---|
| `love` | LÖVE executable binary (Linux ARM) |
| `libs/liblove-11.5.so` | LÖVE shared library |
| `libs/libluajit-5.1.so.2` | LuaJIT shared library |
| `conf/love/rgbscreenreact/settings.txt` | Local development settings file |
| `mux_lang.ini` | Localization config |

## Signal Flow

```
User input (D-pad / gamepad)
  → input.lua (validates, updates currentSelection / settings)
    → command.lua (shell command to daemon)
      → rgb_screen_react.sh (controls LEDs)
    → saveSettings() (persists to settings.txt)
    → soundmanager (plays UI sound)
    → draw.lua (renders updated state)
```

## Key Pipelines

### Framebuffer Color Sampling (rgb_screen_react.sh)

```
/dev/fb0 (raw pixel data)
  → Staggered grid read (PIXELS_LONG_SIDE × aspect, 20% margin exclusion)
    → Per-pixel RGB extraction (byte offsets based on stride/bpp)
      → Saturation-weighted accumulation (vibrant colors have more influence)
        → Adaptive boost (only desaturated results get boosted)
          → Exponential smoothing (smooth LED transitions)
            → LED output (SYSFS or serial backend)
```

For dual-stick devices, left and right halves of the screen are sampled independently.

### LED Backend Auto-Detection

```
Check /sys/class/led_anim → SYSFS mode (brightness 0–60)
Check /dev/ttyS5 → Serial mode (115200 baud, checksum packets)
```

### Rendering Pipeline (draw.lua)

```
love.draw()
  ├─ renderBackground() → gradient mesh (8 colors, smoothstep transitions, 2s cycle)
  └─ push:start() (640x480 virtual canvas)
      ├─ Background sprite (centered, scaled)
      ├─ Menu items (text + icons + values)
      │   ├─ "Enabled" → "On"/"Off" text
      │   └─ "Brightness" → slider sprite (frame = brightness value)
      ├─ Selection indicator (white horizontal lines)
      └─ push:finish()
  └─ Fade overlay (black, alpha decreasing over 0.4s)
```

## Platform Integration

- **Target**: MuOS Linux (ARM) handheld gaming devices
- **Settings path**: `/run/muos/storage/theme/active/rgb/settings.txt`
- **Daemon install path**: `/run/muos/storage/init/rgb_screen_react.sh`
- **Device config**: `/opt/muos/device/config/board/stick` (single vs dual RGB sticks)
- **Battery low detection**: `/run/muos/overlay.battery` overlay file (created/removed by MuOS `lowpower.sh` daemon)
- **Idle detection**: `/run/muos/is_idle` flag (created by `DISPLAY_IDLE()` in `/opt/muos/script/var/func.sh`, removed by `DISPLAY_ACTIVE()`)
- **CPU governor**: Managed by `mux_launch.sh`

## Conventions

- All code in English
- Inline bracket style (Lua)
- Global state via shared tables (`settings`, `menu`, `currentSelection`)
- LÖVE lifecycle: `love.load()` → `love.update(dt)` → `love.draw()`
- 1-based indexing (Lua convention)
- Shell script uses POSIX-compatible constructs for MuOS compatibility
- Pixel art aesthetic: nearest-neighbor filtering on fonts and sprites
- Game resolution fixed at 640×480, scaled to device via `push` library

## Common Tasks → Files to Load

**Changing menu options or adding a new setting:**
`rgbscreenreact/tables.lua`, `rgbscreenreact/input.lua`, `rgbscreenreact/draw.lua`, `rgbscreenreact/main.lua` (save/load)

**Changing the UI appearance:**
`rgbscreenreact/draw.lua` (rendering), `rgbscreenreact/assets/sprites/` (images)

**Changing input handling:**
`rgbscreenreact/input.lua`

**Changing LED control commands:**
`rgbscreenreact/command.lua`, `rgb_screen_react.sh`

**Changing the color sampling algorithm:**
`rgb_screen_react.sh` (sampling loop, weighting, boosting)

**Changing LED smoothing or transition behavior:**
`rgb_screen_react.sh` (exponential smoothing parameters)

**Adding a new LED backend:**
`rgb_screen_react.sh` (detection logic, output functions)

**Changing splash screen:**
`rgbscreenreact/splash.lua`, `rgbscreenreact/assets/sprites/muos.png`

**Changing sound effects:**
`rgbscreenreact/soundmanager.lua`, `rgbscreenreact/assets/sounds/`

**Changing MuOS integration (launch, governor, paths):**
`mux_launch.sh`

**Changing settings persistence:**
`rgbscreenreact/main.lua` (`loadSettings`, `saveSettings`, `parseSettings`)

**Changing screen resolution/scaling:**
`rgbscreenreact/conf.lua`, `rgbscreenreact/push.lua` (third-party)

**Changing animation/tweening:**
`rgbscreenreact/timer.lua` (third-party), `rgbscreenreact/draw.lua` (gradient animation), `rgbscreenreact/splash.lua` (splash animation)
