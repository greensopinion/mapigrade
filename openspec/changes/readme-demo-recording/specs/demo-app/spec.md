## ADDED Requirements

### Requirement: Recording mode
The demo SHALL have a recording mode on macOS, which the environment variable `MAPIGRADE_DEMO_RECORDING_SECONDS=<L>` turns on when the demo starts, where L is the clip length in whole seconds and is greater than 0. Without the variable, the demo SHALL behave as the other requirements state. On iOS and Android the demo SHALL ignore the variable. When the variable is set to a value that isn't a whole number greater than 0, the demo SHALL write the reason to standard error and exit with a non-zero status.

In the recording mode the demo SHALL:

- show its window without a title bar and with square corners, with a content size of 1280 × 720 points, at launch;
- show the panel with the settings section collapsed, and keep the flyover status, the camera readout, the metrics and the statement that the routes are approximate;
- when the style has loaded and the stages have loaded, play a warm-up pass that covers the flyover from its start to L + 1 s, with the panel stating that it is warming up;
- after the warm-up pass, move the camera to the flyover's camera at time 0 and hold it there until the map is at rest, meaning that it renders no frame for 1 s;
- then write the line `ready` to standard output, and start the run, the flyover from time 0, when it reads the line `go` on standard input.

The run SHALL be the flyover that the other requirements describe, with the same camera at the same time for the same viewport size. The demo SHALL exit with a non-zero status and write the reason to standard error when the map isn't at rest within 30 s after the warm-up pass, when `go` doesn't arrive within 30 s after `ready`, or when the layer reports a failure.

#### Scenario: Launch in the recording mode
- **WHEN** the macOS demo is started with `MAPIGRADE_DEMO_RECORDING_SECONDS=30`
- **THEN** its window's content area is 1280 × 720 points, the settings section is collapsed, and the warm-up pass starts once the style and stages have loaded, without input

#### Scenario: Warm-up length
- **WHEN** the recording mode runs with L = 30
- **THEN** the warm-up pass plays the flyover from 0 s to 31 s and then moves the camera back to the start of stage 9 in Nice

#### Scenario: Ready and go
- **WHEN** the map is at rest at the start after the warm-up pass
- **THEN** the demo writes `ready` to standard output and doesn't move the camera until it reads `go` on standard input, and then it plays the flyover from time 0

#### Scenario: Go doesn't arrive
- **WHEN** 30 s pass after `ready` without `go` on standard input
- **THEN** the demo writes the reason to standard error and exits with a non-zero status

#### Scenario: Normal launch
- **WHEN** the demo is started without the variable
- **THEN** the window, the panel and the flyover behave as before, and the demo neither writes `ready` nor reads standard input

### Requirement: README recording
A script in `packages/demo/tool/` SHALL make the video that `README.md` shows, from the recording mode, with no input from the user while it runs, and SHALL write it to `packages/demo/build/readme_demo.mp4`. The script SHALL take the clip length L from one value in the script, 20 s, and pass it to the recording mode. The video SHALL be an H.264 MP4 without sound, 1280 × 720 pixels, 60 frames per second and L seconds long, made from a capture of the demo window's content area at the display's pixel size, and SHALL be at most 10,000,000 bytes, so that GitHub accepts it as an attachment on its free plan. The capture SHALL start before the run, and the run SHALL start when the capture has its first frame, so that the video starts with the still camera at the start and the camera starts to move at the same time in every video. The capture SHALL record the demo's window even when other windows cover it.

The video SHALL start with a title card over the map that shows the Mapigrade logo, the title "Mapigrade demo" and the subtitle "Flyover of the Tour de France Femmes avec Zwift 2026, stage 9, Nice", in Helvetica Neue. The card SHALL be fully shown until about 2.5 s and fade out by about 3.5 s.

Before it builds or starts the demo, the script SHALL check that the tools it needs are installed and that the app running it has Screen Recording permission. When one is missing, it SHALL state what is missing and how to get it, and exit with a non-zero status without changing the video file. The script SHALL replace the video file only when every step succeeded, and SHALL stop the demo when it exits. The script SHALL NOT upload the video.

#### Scenario: Make the video
- **WHEN** the script runs on a Mac that has the tools and the permission
- **THEN** it writes `packages/demo/build/readme_demo.mp4`, an H.264 MP4 of 1280 × 720 pixels, 20 s at 60 frames per second, at most 10,000,000 bytes, without input from the user

#### Scenario: Title card
- **WHEN** the first frame of the video is viewed
- **THEN** it shows the logo, "Mapigrade demo" and "Flyover of the Tour de France Femmes avec Zwift 2026, stage 9, Nice" over the map at the start of stage 9, and by 3.5 s the card is gone

#### Scenario: Covered window
- **WHEN** another window covers the demo's window during the run
- **THEN** the video shows the demo's window without the other window

#### Scenario: Permission missing
- **WHEN** the app that runs the script doesn't have Screen Recording permission
- **THEN** the script states which app needs it and where to grant it, exits with a non-zero status before it builds the demo, and leaves the video file as it was

#### Scenario: Tool missing
- **WHEN** ffmpeg isn't installed
- **THEN** the script states that ffmpeg is missing and the command to install it, exits with a non-zero status, and leaves the video file as it was

#### Scenario: Video too large
- **WHEN** the encoded video is over 10,000,000 bytes at every quality the script tries
- **THEN** the script states the sizes, exits with a non-zero status, and leaves the video file as it was
