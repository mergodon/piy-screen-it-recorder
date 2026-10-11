<img src="docs/icon.png" width="128" alt="S|R">

# ScreenItRecorder

A small macOS menu bar app that records **every display to its own file**, with your
microphone in each file. Drop the files into Final Cut Pro and sync them on the audio.

- One `.mov` per display: HEVC (`hvc1`), about 2560×1440, 30 fps, plus AAC mic audio.
- The same mic track is in every file, so **Synchronize Clips** in FCP lines them up. A clap at the start is a good backup.
- Hides your desktop widgets while it records and puts them back after.
- Keeps the display awake while it records.
- Refuses to start with less than 10 GB free.
- If you quit or log out during a recording, it saves the files first.

Recordings go to `~/Movies/ScreenItRecorder/<date_time>/screen0.mov`, `screen1.mov`, …

## Requirements

- macOS 15 or later (uses ScreenCaptureKit's `SCRecordingOutput`).
- Swift 6 toolchain. The Command Line Tools are enough; you do not need Xcode.

## Build and run

```sh
./build.sh
open build/ScreenItRecorder.app
```

Click **S|R** in the menu bar, choose your microphone, then click **Start Recording** (⌘R).
The first time, macOS asks for Screen Recording and Microphone permission.

`build.sh` signs the app ad hoc. macOS then asks for permission again after each rebuild.
To sign with your Developer ID:

```sh
SIGN_ID="Developer ID Application: <your name> (<team id>)" ./build.sh
```

Smoke test without the UI (records 5 s, then quits):

```sh
build/ScreenItRecorder.app/Contents/MacOS/ScreenItRecorder --test 5
```

## Command-line alternative

`rec` does the same with `ffmpeg` (`brew install ffmpeg`). Press Ctrl-C to stop.
`widgets off|on|status` toggles the desktop widgets by hand.

## License

MIT
