## Why

The repository README shows the logo and describes the plugin, but it doesn't show the plugin running. We want a video of the demo's flyover at the top of the README, and we want to be able to make it again, for example after a change to the demo or the styles, without manual steps.

## What Changes

- A recording mode in the demo app, on macOS, that the environment variable `MAPIGRADE_DEMO_RECORDING_SECONDS` turns on when the demo starts. In this mode the demo makes its window borderless with a content size of 1280 × 720 points, collapses the settings section of the panel, and, when the style and the stages have loaded, plays a warm-up pass over the first part of the flyover only (the clip length plus 1 s). After the warm-up pass it moves the camera to the start of the flyover, waits until the map is at rest, writes `ready` to stdout, and starts the run when it reads `go` on stdin. It exits with an error if `go` doesn't arrive in time. Without the variable, the demo is unchanged.
- A script, `packages/demo/tool/record_readme.sh`, that makes the video with no manual steps: it checks for the tools it needs and for Screen Recording permission, builds the demo in release mode, starts it with the variable, captures its window, adds a title card, and encodes an MP4 into `packages/demo/build/`.
- A capture helper, `packages/demo/tool/capture_window.swift`, that finds the demo's window with ScreenCaptureKit, captures its content at 2560 × 1440 pixels while other windows cover it, writes `go` to the demo when the first frame arrives, and stops after the clip length.
- A title card over the first ~3.5 s of the clip, with the logo, "Mapigrade demo" and "Flyover of the Tour de France Femmes avec Zwift 2026, stage 9, Nice", in Helvetica Neue, fading out as the camera starts to move. The card is the video's first frame, which the README shows before the video plays.
- The video is an H.264 MP4, 1280 × 720 pixels, 20 s, 60 fps, under 10 MB, the limit for a video attachment on GitHub's free plan.
- We upload the video as a GitHub attachment, by dragging it into an editor on github.com, and `README.md` shows it with the attachment's URL. `CONTRIBUTING.md` describes how to make and publish it again, including the one-time setup.

Non-goals:

- No recording mode on iOS or Android.
- No recording inside the demo app: the capture stays outside it, as the `add-demo-app` change decided.
- No synthesized input: the demo plays on its own in the recording mode.
- No change to the warm-up checkbox, which still plays the whole flyover.
- No automated upload: GitHub has no API for attachments. No copy as a release asset, and no video in the repository.
- No animated image: during exploration, an animated WebP of 30 s at 20 fps was 50 MB at quality 75.
- No recording of other parts of the flyover.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `demo-app`: new requirements for the recording mode (window size, collapsed settings, the shortened warm-up pass, the pause at the start, and the `ready`/`go` exchange on stdout and stdin) and for the script that makes the README video.

## Impact

- Demo app: `lib/src/map_screen.dart`, `lib/src/flyover_player.dart` and a new `lib/src/recording.dart` (the recording mode, a warm-up pass of a given length, the pause), `macos/Runner/MainFlutterWindow.swift` (the borderless window and its size).
- New files: `packages/demo/tool/record_readme.sh`, `packages/demo/tool/capture_window.swift`.
- Tools on the machine that runs the script: ffmpeg, ImageMagick and `rsvg-convert` (from Homebrew), and the Xcode command line tools for `swiftc`. The script doesn't install them.
- Permission: Screen Recording for the app that runs the script (Terminal, iTerm or VS Code), granted once in System Settings.
- Network: a run loads the style and tiles from OpenFreeMap.
- Hosting: GitHub stores the video as an attachment, outside the repository; the script can make it again.
- Documentation: `README.md`, `CONTRIBUTING.md`, `packages/demo/README.md`.
- Interaction with `publish-readiness`: task 7.2 of that change also edits `README.md`, in other sections.
