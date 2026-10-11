<img src="docs/icon.png" width="128" alt="S|R">

# ScreenItRecorder

A small macOS menu bar app that records **every display to its own file**, with your
microphone in each file. Drop the files into Final Cut Pro and sync them on the audio.

- One `.mov` per display: HEVC (`hvc1`), about 2560×1440, 30 fps, plus AAC mic audio.
- The same mic track is in every file, so **Synchronize Clips** in FCP lines them up. A clap at the start is a good backup.
- **Camera (optional):** choose a camera in the menu (default **None**). It records 1080p HEVC at 30 fps (matches the screens); **Camera Frame Rate** offers every rate the camera supports, e.g. 50/60 for slow motion
  with the same mic track to `camera.mov`. The camera starts first, so it never misses the clap.
- **Green / blue screen:** press **⌃⌥G** (anywhere) to cover every display with a solid key
  colour, so you can key other footage onto the screens later. Press ⌃⌥G or Esc to remove it.
  Choose in Settings: pure green `#00FF00` (default), chroma green `#00B140`, pure blue
  `#0000FF` or chroma blue `#0047BB`. Use blue when something green (a mic, a plant) is in
  front of the screens. The recording stores the exact value.
  By default it also dims the displays to 40% while green is on (configurable), so the green
  does not flood the room. Only the backlight changes, so the file keeps the exact colour.
  (Dimming uses Apple's private DisplayServices framework; it works on Apple displays.)
- **Settings window** (menu → Settings…): all options, the shortcuts, and a live check of the
  Screen Recording, Camera and Microphone permissions with buttons to fix them.
- Captures in sRGB, so the colours in the file match the screen and the file's BT.709 tag.
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
tools/make-local-signing-cert.sh   # once per Mac: keeps permissions across rebuilds
./build.sh --install               # builds, replaces /Applications/ScreenItRecorder.app, relaunches
```

Click **S|R** in the menu bar, choose your microphone, then click **Start Recording**, or press **⌃⌥⇧R** anywhere to start and stop.
(⌃⌥R is taken by Final Cut Pro's Custom Speed.)
The first time, macOS asks for Screen Recording, Microphone and (if you use one) Camera permission.

`build.sh` signs with the local identity from `tools/make-local-signing-cert.sh` when it
exists. Without it, the build is signed ad hoc, and macOS forgets the permissions after every
rebuild. To sign a build that you share with other people, use your Developer ID:

```sh
SIGN_ID="Developer ID Application: <your name> (<team id>)" ./build.sh
```

Smoke test without the UI (records 5 s, then quits; add `--green` to record over the green screen):

```sh
build/ScreenItRecorder.app/Contents/MacOS/ScreenItRecorder --test 5
```

## Command-line alternative

`rec` does the same with `ffmpeg` (`brew install ffmpeg`). Press Ctrl-C to stop.
`widgets off|on|status` toggles the desktop widgets by hand.

## License

MIT
