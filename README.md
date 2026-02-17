# RGB Screen React
An app for RGB handheld devices running [MuOS](https://muos.dev), that matches the RGB colors to what's on the screen in realtime.

![preview](https://github.com/user-attachments/assets/446e0747-2492-4a80-8cec-c3b29ec7928e)
> The preview above is [Cab Ride](https://www.lexaloffle.com/bbs/?pid=86966#p).

https://github.com/user-attachments/assets/ef946204-35de-4c2c-955d-9ccb7d998325
> The tech demo above is [mer ork](https://www.lexaloffle.com/bbs/?pid=152206), running natively on MuOS with Pico-8 RasPi. Volume up!

### ⭐️ Features
- **Direct framebuffer reading**: colors are read directly from the system framebuffer
- **Aspect ratio awareness**: sampling density scales with aspect ratio
- **Margin exclusion**: screen margins are excluded to avoid fetching black bars
- **Saturation-weighted average**: vivid and saturated colors have higher priority
- **Adaptive saturation boost**: saturation is only increased for dull colors
- **Power efficient**: framebuffer reading requires very low CPU usage
- **Stick detection**: color output adapts to devices with one or two RGB sticks
- **Smooth integration**: perfectly integrates with existing MuOS power saving settings
- **Fire and forget**: already tuned and ready to run, easy to customize for advanced users

### 📐 Compatibility
**This app is built for MuOS Jacaranda and might not work with previous versions of MuOS.** The code is based on the original *RGB Controller* app bundled with MuOS, so it's expected to work on all Linux devices that can run MuOS and have RGB sticks (Anbernic devices, TrimUI devices).

### 📦 Installation
Download the latest package from [Releases](https://github.com/DanjelRicci/RGB-Screen-React/releases) and place it into either `mmc/ARCHIVE` or `sdcard/ARCHIVE`. Boot MuOS, navigate to Applications > Archive Manager, select the package you just added, and wait for the installation to finish.

### ▶️ Usage
In MuOS, navigate to Applications and launch RGB Screen React. Use the controller to enable or disable the Screen React mode and change the LED brightness. Press L1+R1 to quit the app. The original RGB Controller app will show `Unknown` mode after Screen React is enabled: this is not a bug and you can just change back to any of the other modes.

### ⚙️ Background process
The app uses a background process included in `rgb_screen_react.sh`, responsible for fetching the screen colors and sending them to the RGB LEDs. That script is automatically added and removed from `mmc/MUOS/init`, and the background process is automatically launched and terminated when necessary.

### 📊 Performance
Due to the low power of the target devices, the background process has been tuned to keep performance usage to the minimum. This is achieved by sampling a sparse and staggered grid of pixels across the framebuffer, rather than operating on the entire framebuffer at once, and by running the sampling at a low refresh rate. The background process stops early when it detects a device with no RGB sticks, or when the Screen React mode is disabled.

Running the shell `top` command shows a very consistent 2% CPU usage from `rgb_screen_react.sh` with default settings and while playing other content, on a RG CubeXX *(H700 quad-core ARM Cortex-A53 at 1.5GHz)*. Reading the framebuffer has been tested with different solutions: per-pixel, ImageMagick, ffmpeg. After evaluating the performance of each solution, per-pixel turned out to be the fastest if used with moderation.

### 🔧 Tuning
A number of variables can be found at the top of `applications/RGB Screen React/rgb_screen_react.sh`, with explanatory comments. These variables have been already tuned to get a good compromise between speed and quality, but feel free to adjust the settings to your preference. Keep in mind that increasing the sample count or reducing the time interval between samples will noticeably increase the CPU usage.

## Disclaimer and credits
RGB Screen React is feature complete and I don't plan on updating it, unless strictly necessary due to critical bugs or possible compatibility changes with future MuOS updates.

This package has been built using [Claude AI](https://claude.ai/new) under my complete supervision. I used AI both because my knowledge didn't cover anything yet about Linux, shell and [LÖVE](https://www.love2d.org), and because I was eager to get it done quickly. Despite using my current coding knowledge to adjust and fine tune the code, using AI to create anything from scratch is not something I thought I would ever do, especially for such a small project. I cannot help but feel bad about it, so I hope this app can at least bring some joy to those who are fascinated by RGB lighting as much as I am.

Inspired by [bias lighting](https://en.wikipedia.org/wiki/Bias_lighting) and from the [Bifrost app](https://github.com/Pollux-MoonBench/Bifrost) by @Pollux-MoonBench: I had it on my AYN Thor and wanted to fill the gap for Anbernic devices my own way.

The LÖVE frontend app is a modified and simplified version of the *RGB Controller* app made by *JanTrueno*, bundled with MuOS.

Special thanks to XongleBongle, AntiKk, corey, Bitter Bizarro and the [rest of the crew](https://muos.dev/crew) for that beast that is MuOS.
