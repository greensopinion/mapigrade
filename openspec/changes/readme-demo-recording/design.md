## Context

The demo's flyover is a pure function of the time since it started and of the viewport size (D118), and its warm-up checkbox plays the whole flyover, about 5 min 45 s, before the run. Playing, the warm-up and the panel's settings are all driven by clicks today. The window's size comes from `MainMenu.xib`, and `MainFlutterWindow.swift` doesn't change it.

The package's public API gives the demo what the recording mode needs: `onStyleLoaded` on `MapigradeLayer`, and `LayerMetrics`, whose rendered frame count stops increasing when the map is at rest.

On this Mac, ImageMagick (with the Helvetica Neue font from `/System/Library/Fonts/HelveticaNeue.ttc`) and `rsvg-convert` are installed, and ffmpeg (with `libx264`) is installed from Homebrew. The macOS demo runs in the App Sandbox (`Release.entitlements`).

## Goals / Non-Goals

**Goals:**

- One command makes `packages/demo/build/readme_demo.mp4`, with no input during the run, in about 2 minutes after the build.
- Two runs on the same Mac give videos whose camera moves at the same times; the tiles and the frame rates in the panel can differ.
- A missing tool or permission fails the script before it builds.

**Non-Goals:**

- Byte-identical videos from one run to the next.
- Uploading the video: GitHub has no API for attachments.
- Running the script in CI: it needs a logged-in GUI session and Screen Recording permission.
- Choosing the clip by any parameter other than its length.

## Decisions

### D144. The recording mode is an environment variable read when the demo starts

`MAPIGRADE_DEMO_RECORDING_SECONDS=<L>` turns the mode on. Swift reads it with `ProcessInfo.processInfo.environment` in `MainFlutterWindow.awakeFromNib` and sets the content size to 1280 × 720 points before Flutter lays out. It makes the window borderless, because the capture showed the rounded corners of a titled window as black pixels in the bottom corners. It also sets `isRestorable` to false: macOS window state restoration otherwise set the frame of an earlier launch after `awakeFromNib`. `applicationDidFinishLaunching` of the app delegate wasn't called when the binary was started from a shell, so it can't do the resize. Dart reads it with `Platform.environment` from `dart:io`.

Alternatives: a `--dart-define` is visible only to Dart, so Swift would need a method channel to get the size, and the script would need a separate build. Launch arguments need Swift to pass them on to the Dart entrypoint. The environment variable reaches both sides, and the script runs the ordinary release build. The App Sandbox doesn't remove environment variables from a process that the script starts.

### D145. The recording sequence lives in `FlyoverPlayer`, with a warm-up of a given length

`FlyoverPlayer.play` takes the warm-up length as a `Duration?` instead of a `bool`: null means no warm-up, `flyover.duration` is today's checkbox, and the recording mode passes L + 1 s. A new phase, `waiting`, follows the warm-up in the recording mode: the player sets the camera to `cameraAt(Duration.zero)`, stops its ticker, and starts the run when `start()` is called. The panel shows "Waiting to start" in that phase.

The checkbox keeps passing the whole duration, so the "Warm-up pass" requirement and its scenario are unchanged.

Alternative: a separate recording controller around the player. It would duplicate the phase handling that the panel already reads, for one extra phase.

### D146. Ready means the map is at rest at the start

After the camera moves to the start, the screen reads `LayerMetrics.snapshot()` every 100 ms and writes `ready` once `renderedFrames` hasn't changed for 1 s, the same definition of "at rest" that the metrics display uses. At rest, the map has rendered the tiles that loaded, so the first frames of the clip don't show tiles that are still loading. The timeout is 30 s.

Alternative: a fixed pause. It can't tell whether the tiles have loaded, and a pause that is long enough on a slow network is too long on a fast one.

### D147. `ready` and `go` over standard output and standard input

The demo writes `ready` with `stdout.writeln` and flushes it, and reads lines from `stdin` with `utf8.decoder` and `LineSplitter`. `print` isn't used, because in a release build it goes to the system log, not to standard output. The capture helper starts the demo's binary (`mapigrade_demo.app/Contents/MacOS/mapigrade_demo`) directly, not with `open`, so that it owns both pipes.

Whether a Flutter macOS release app started this way gets the pipes as its standard output and standard input is task 1.1. If it doesn't, the fallback is two files in a temporary directory that the script names in a second environment variable: the demo creates `ready`, and polls for `go` every 10 ms.

### D148. The Swift helper captures with ScreenCaptureKit and runs the demo

`capture_window.swift` has two commands.

- `check`: calls `CGPreflightScreenCaptureAccess()`. When it returns false, it calls `CGRequestScreenCaptureAccess()`, which adds the app that runs the script to the Screen Recording list or shows the prompt, and exits with status 2.
- `record <demo binary> <L> <output.mov>`: starts the demo with the variable, waits for `ready`, then finds the demo's window in `SCShareableContent` by the process id. It captures with `SCContentFilter(desktopIndependentWindow:)`, which records the window even where other windows cover it, with `sourceRect` set to the content area (from the frame's height minus 720 points at the top, which is 0 for the borderless window of D144), `width` and `height` set to the content size times `pointPixelScale`, `showsCursor` false, and `minimumFrameInterval` of 1/60 s. It writes the frames with `AVAssetWriter` as HEVC at a high bit rate. When the first complete frame arrives, it writes `go` to the demo. It stops when a frame's presentation time is L s after the first frame's, closes the file, and terminates the demo.

The script compiles the helper with `swiftc` into a temporary directory on each run, so that no binary is committed and the helper always matches its source. Screen Recording permission belongs to the app that started the script, which macOS treats as responsible for the helper's process.

Alternatives: `screencapture -v -R` records a screen rectangle, so another window over the demo or a move of the demo's window spoils the clip, and it can't tell the demo when the first frame was captured. Capturing in the app with `RepaintBoundary.toImage` was rejected during exploration because the panel's frame rates wouldn't be real.

### D149. The script orchestrates; ffmpeg cuts nothing

`record_readme.sh` sets `L=30`, then:

1. checks for `ffmpeg` with `libx264`, `magick`, `rsvg-convert`, `swiftc` and `flutter`; for each one that is missing it prints the install command. On macOS the plugin gets the FFI through Swift Package Manager, so a missing FFI makes `flutter build` fail with its own message;
2. compiles the helper and runs `check`;
3. runs `flutter build macos --release` in `packages/demo`;
4. runs `record` into a temporary directory;
5. makes the card (D150) and encodes (D151) into a temporary file;
6. moves the result to `packages/demo/build/readme_demo.mp4`, which `packages/demo/.gitignore` already ignores.

A `trap` on exit removes the temporary directory and terminates the demo if the helper didn't. The helper's first frame is the clip's first frame, so the encode doesn't need to cut the start.

### D150. The title card is a transparent PNG at the video's size

`rsvg-convert` renders `assets/mapigrade.svg`, and ImageMagick composes a 1280 × 720 PNG: a rounded panel of the color of the demo's panel at 97 % opacity with a soft shadow, below the demo's panel so that it doesn't cover it, with the logo, "Mapigrade demo" in Helvetica-Neue-Bold, and the subtitle in Helvetica-Neue. ffmpeg fades the card's alpha out from 2.5 s to 3.5 s and places it over the capture after scaling, so that the text is rendered at the video's size instead of being scaled down with the map.

The camera holds at the start for the first 3 s of the run (D118), so the card covers a still map and is gone as the camera turns onto the route.

### D151. Encoding

ffmpeg reads the capture, applies `fps=60` and `scale=1280:720:flags=lanczos` with the capture's BT.709 matrix, places the card, and encodes with `libx264` (`-preset slow`, `-profile:v high`, `yuv420p`, BT.709 tags, `-movflags +faststart`, no audio) for L s. The script tries CRF 24, then 25, then 26, and keeps the first result of at most 10,000,000 bytes. If none is small enough, it fails and leaves the video file as it was, with the sizes in its message.

During exploration we encoded the 30 s capture at 1280 × 720:

| Clip | fps | CRF | Size |
|---|---|---|---|
| 30 s | 30 | 22 | 15.3 MB |
| 30 s | 60 | 22 | 17.3 MB |
| 30 s | 60 | 27 | 8.4 MB |
| 20 s | 60 | 24 | 9.2 MB |
| 20 s | 60 | 25 | 7.9 MB |

60 fps costs about 12 % more than 30 fps, because consecutive frames differ less, and it matches the ~58 fps of the capture. Crops at CRF 22, 25 and 27 showed no visible difference in labels, the route or the rider marker. We chose 20 s at CRF 24.

Alternatives: an animated WebP, which plays without a click and loops, was 50 MB for 30 s at 20 fps and quality 75. YouTube can't play in a README, because GitHub removes `<iframe>`. HEVC is smaller, but some browsers don't play it.

### D152. Publishing and documentation

GitHub plays a video in a README only from an attachment URL (`https://github.com/user-attachments/assets/<id>`) on a line of its own. We upload the MP4 by dragging it into an editor on github.com, and put the URL in `README.md` below its first paragraph. The video doesn't play on its own; the README shows its first frame, the title card, until the reader starts it. GitHub doesn't list, version or delete attachments, so the script is what we keep: when the URL stops working or the demo changes, we make the video again and upload it.

`CONTRIBUTING.md` gets a section on making and publishing the video: the one-time setup (Homebrew packages, Screen Recording permission and the restart of the app that runs the script), the command, and the upload. `packages/demo/README.md` describes the environment variable.

## Risks / Trade-offs

- [`stdin` or `stdout` doesn't reach a Flutter macOS release app started from the helper] → Task 1.1 checks it first; D147 names the fallback.
- [One warm-up pass leaves tiles unloaded, because MapLibre Native cancels requests for tiles that leave the view] → The camera of the run is the camera of the warm-up, so the run requests the same tiles, and the on-disk cache keeps them between runs. Task 4.2 checks the frames of the first video. If tiles are missing, the recording mode can play the warm-up more than once.
- [macOS asks again for Screen Recording permission, or resets it] → `check` runs before the build, so the script fails in seconds with the instructions instead of after the warm-up.
- [The demo's window is on another Space or minimized, and ScreenCaptureKit gets no frames from it] → The demo activates when it starts, so its window opens on the current Space. If no frame arrives within 10 s after the capture starts, the helper fails with that reason.
- [The capture costs frames on the GPU, so the panel's frame rates are lower than without it] → Hardware HEVC encoding at 2560 × 1440 and 60 fps is light on Apple silicon. The clip shows the frame rates under capture.
- [OpenFreeMap changes its style or tiles] → The next video shows the change. The videos don't have to match each other.
- [A GitHub attachment URL stops working, and GitHub gives no way to manage attachments] → Make the video again with the script and upload it; the README's URL is the only reference.
- [Tiles or the network make a video larger than at the first run] → The CRF steps of D151 leave room; a run that can't get under the limit fails with the sizes.

## Open Questions

- The panel's opacity and color on the card, and the exact layout of the logo and the text: they are chosen when the card is first rendered and looked at.
