# piy-screen-it-recorder — Screen It Recorder

- Name: **Screen It Recorder** everywhere a user reads it. `ScreenItRecorder` stays only where
  renaming costs something: bundle id + executable (TCC grants are keyed on them), the Swift
  target, and `~/Movies/ScreenItRecorder` (existing recordings live there).

- **Public repo (MIT).** Everything committed is published. No fleet hosts, IPs, or personal paths in code or docs.
- **Exception to the observer rule (mate, 2026-10-11):** this Mac app is built and tested ON the
  observer Mac — a macOS app cannot build on the Linux dev boxes.
- Build + install: `./build.sh --install` (SwiftPM + Command Line Tools, no Xcode → no SwiftUI
  macros: no `@State`/`@Observable`, use `ObservableObject`). Signs with the local
  "ScreenItRecorder Local Signing" identity so TCC grants survive rebuilds — never fall back to
  ad hoc on mate's Mac: that silently revoked his Screen Recording grant mid-session (2026-10-11). Verify: `"build/Screen It Recorder.app/Contents/MacOS/ScreenItRecorder" --test <s>`
  then `ffprobe` the files in `~/Movies/ScreenItRecorder/`. Delete test recordings after — they contain screen content.
- Run the `--test` binary from the terminal: TCC then uses the terminal's Screen Recording + Mic grant.
  `open`-ing an ad-hoc build re-prompts after every rebuild.
- `rec` / `widgets` are the ffmpeg CLI fallback; keep their behaviour in step with the app.
- Tests share mate's prefs domain (`com.mergodon.ScreenItRecorder`). Read a key before a test
  writes it and restore that value after — never `delete` or reset to a default. Never
  `--install` (it quits the app) while his colour screen is up: check for layer-1000 windows first.

## Cross-repo

Never edit these from here; file issues with `gh issue create -R <owner/repo>`.

- **`mergodon/promptityourself-web`** — the PIY site; owns this project's page
  (`src/content/projects/`). Page request: issue #116 (2026-10-11).
