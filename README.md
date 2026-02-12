# RGB Screen React
An app for RGB handheld devices running [MuOS](https://muos.dev), that matches the RGB colors to what's on the screen.

### ⭐️ Specifications
- **Direct framebuffer reading**: colors are read directly from the system framebuffer
- **Aspect ratio awareness**: sampling density scales correctly with the aspect ratio
- **Margin exclusion**: screen margins are excluded to avoid fetching black bars
- **Saturation-weighted average**: vivid and saturated colors have higher priority
- **Adaptive saturation boost**: saturation is only increased for dull colors
- **Power efficient**: low CPU usage in background, sleeps when the screen is dimmed or off
- **Fire and forget**: already tuned and ready to run, easy to customize for advanced users

### 📦 Installation
This app is built around MuOS Jacaranda release and might not work with previous versions of MuOS.

Download the latest package from Releases and place it into either `mmc/ARCHIVE` or `sdcard/ARCHIVE`. Boot MuOS, navigate to Applications > Archive Manager, select the package you just added, and wait for the installation to finish.

### ▶️ Usage
In MuOS, navigate to Applications and launch RGB Screen React. Use the controller to enable or disable the Screen React mode and change the brightness. Press L1+R1 to quit the app.

### ⚙️ Background process
In order to work, this package will also install a script called `rgb_screen_react.sh` in `mmc/MUOS/init`, which is responsible to fetch the screen colors and send them to the RGB LEDs. The script will launch its process at system boot or when the Screen React mode is enabled from the app. The process is terminated when it detects that Screen React mode is disabled.

### 📊 Performance
The background process has been tuned to keep performance usage to the minimum necessary, keeping in mind the low power of the target devices. This is achieved by sampling a limited, staggered grid of pixels across the framebuffer rather than operating on the entire framebuffer at once. When testing on RGCubeXX (H700 quad-core ARM Cortex-A53 at 1.5GHz), `top` command shows a 2% CPU usage with the Screen React mode on, while playing other content.

The screen reading feature has been tested with different tools: direct read, ImageMagick, ffmpeg. After evaluating the performance of each method, reading the framebuffer directly turned out to be the best compromise between speed and quality.

### 🔧 Tuning
A number variables can be found at the top of `rgb_screen_react.sh`, with explanatory comments. These variables have been already tuned to get a good compromise between speed and quality, but feel free to test with them to find the settings that work best for you.

## Disclaimer and credits
RGB Screen React is feature complete and I don't plan on updating it, unless strictly necessary due to bugs or possible compatibility changes with future MuOS updates.

This package has been built using [Claude AI](https://claude.ai/new), both because my current coding knowledge didn't cover anything yet about Linux, shell and [LÖVE](https://www.love2d.org), and because I was eager to get it done quickly. Despite using my prior coding knowledge to adjust and fine tune the app, using AI to code from scratch is not something I thought I would ever do, especially for such a small package. I cannot help but feel bad about it, so I hope this app can at least bring some joy to those who are fascinated by RGB lighting as much as I am.

Inspired from [Bifrost by Pollux-MoonBench](https://github.com/Pollux-MoonBench/Bifrost). I had that on my AYN Thor and wanted to fill the gap for Anbernic devices as best as I could.

The LÖVE frontend app is a modified and simplified version of the *RGB Controller* app made by *JanTrueno*, bundled with MuOS. Both the app and the `rgb_screen_reach.sh` script are made with Claude AI under my full supervision.

Special thanks to XongleBongle, AntiKk, corey, Bitter Bizarro and the [rest of the crew](https://muos.dev/crew) for that beast that is MuOS.