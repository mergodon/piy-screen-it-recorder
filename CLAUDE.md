# piy-screen-it-recorder — ScreenItRecorder

- **Public repo (MIT).** Everything committed is published. No fleet hosts, IPs, or personal paths in code or docs.
- **Exception to the observer rule (mate, 2026-10-11):** this Mac app is built and tested ON the
  observer Mac — a macOS app cannot build on the Linux dev boxes.
- Build: `./build.sh` (SwiftPM + Command Line Tools, no Xcode). Verify: `…/MacOS/ScreenItRecorder --test <s>`
  then `ffprobe` the files in `~/Movies/ScreenItRecorder/`. Delete test recordings after — they contain screen content.
- Run the `--test` binary from the terminal: TCC then uses the terminal's Screen Recording + Mic grant.
  `open`-ing an ad-hoc build re-prompts after every rebuild.
- `rec` / `widgets` are the ffmpeg CLI fallback; keep their behaviour in step with the app.
