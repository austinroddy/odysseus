# Odysseus for macOS (native app)

A genuine native macOS app for Odysseus: its own Dock icon, menu bar, and
window, with a bundled backend so end users don't need Python, a venv, or
Docker installed at all. This is different from the repo-root
`build-macos-app.sh`, which is a thin launcher script that drives this
repo's own dev venv and opens a Chrome app-window — useful for a quick local
wrapper, but not something you can hand to someone else's Mac.

## How it works

- `macos/backend/` — a PyInstaller spec that freezes the existing FastAPI
  backend (`app.py` and everything under `core/`, `src/`, `routes/`,
  `services/`) into a single standalone executable. Nothing about the
  backend's own code changes for this — it's the same app, just packaged
  differently. See "Backend changes" below for the two small, generally
  applicable edits this did require.
- `macos/app/` — a Swift Package (`swift build`, no `.xcodeproj` — same
  convention as `swift/odysseus-mlx-image-bridge`, and it can still be
  opened directly in Xcode via "Open Package.swift") implementing a small
  SwiftUI/AppKit shell:
  - `BackendManager` spawns the frozen backend as a child process, waits for
    it to report ready, and stops it cleanly on quit.
  - `WebViewContainer` embeds the **existing, unmodified** web frontend
    (`static/`) in a native `WKWebView`, with the native-shell glue the
    frontend can't provide on its own: routing `window.open`/external links
    correctly (in-app for the app's own pages, the system browser for
    everything else), handling file downloads/exports, and granting
    microphone access for voice input.
- `macos/scripts/build.sh` — orchestrates both of the above into a real
  `Odysseus.app` (and `Odysseus.dmg`).

The frontend itself is untouched. If/when you restyle the UI later, that's
CSS/JS work in `static/` — it has nothing to do with anything in this
directory.

## Building

Prerequisites:
- Xcode command line tools (`xcode-select --install`) for `swift`/`xcrun`.
- A Python environment with the backend's dependencies and PyInstaller
  installed:
  ```bash
  python3 -m venv venv && source venv/bin/activate
  pip install -r requirements.txt pyinstaller
  ```

Then, from the repo root:
```bash
./macos/scripts/build.sh
```

This produces `macos/dist/Odysseus.app` and `macos/dist/Odysseus.dmg`. Run
it with `open macos/dist/Odysseus.app`.

Signing is ad-hoc by default, so this works with zero setup for local use or
CI. For a real Developer ID + notarized build, create a gitignored
`macos/Local.env` (never committed — see `macos/.gitignore`):

```bash
# macos/Local.env
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARIZE_PROFILE="your-notarytool-keychain-profile"
```

`NOTARIZE_PROFILE` refers to a profile stored via
`xcrun notarytool store-credentials`, which walks you through providing your
Apple ID / an app-specific password or an App Store Connect API key —
that's an Apple-account step you do yourself in your own terminal, not
something baked into this repo or script.

## Runtime layout

- App data: `~/Library/Application Support/Odysseus/` (set via
  `ODYSSEUS_DATA_DIR`, same env var the backend already reads in every other
  deployment mode — nothing backend-specific changed here).
- Backend log: `~/Library/Application Support/Odysseus/logs/backend.log`.
- Port: tries `7860` first (this repo's existing macOS convention —
  `start-macos.sh` already avoids `7000` because of AirPlay Receiver), falls
  back to an OS-assigned free port if that's taken.
- Auth: unmodified — first launch shows the normal first-run admin setup
  page inside the app window, and the session persists across relaunches
  (the embedded `WKWebView` keeps a persistent cookie store), so you only
  log in once.

## Backend changes

Two small, non-macOS-specific changes were needed in the backend itself,
both scoped to fixing something that only breaks under a PyInstaller freeze
(they don't change behavior for Docker/dev/Windows at all):

- `src/runtime_paths.py` gained `get_script_subprocess_args()`. Built-in MCP
  tool servers (memory/RAG/image-gen/email) run as `sys.executable
  <script>` subprocesses. Under a freeze, `sys.executable` is the frozen app
  itself, not a bare interpreter, so that would just relaunch the whole app
  instead of the intended script. The frozen entrypoint
  (`macos/backend/mac_entrypoint.py`) supports a hidden `--run-script <path>`
  mode that runs the given script in-process via `runpy` instead — same
  interpreter, so it already has every package the main app has, no extra
  bundled runtime needed. `get_script_subprocess_args()` returns the right
  `(command, args)` for whichever mode is active.
- `src/builtin_mcp.py` and `src/mcp_manager.py` use that helper instead of
  hardcoding `sys.executable`.

## Known limitations

- **Cookbook's local model-serving** still expects Homebrew-installed
  `tmux`/`llama.cpp` on `PATH`, same as `start-macos.sh` today — this app
  doesn't bundle or install those. Cookbook's remote-server (SSH) serving
  path is unaffected.
- **RAG / semantic memory** needs a reachable ChromaDB server (default
  `localhost:8100`) for vector search; without one it falls back to keyword
  search, which is the same graceful-degradation behavior the backend
  already has outside this app — nothing regressed, just not bundled here.
- **Mac App Store distribution** isn't set up. This app spawns a local
  server subprocess, which spawns further subprocesses (MCP servers,
  optionally Cookbook's local serving), and talks to IMAP/SMTP/CalDAV —
  all of which are a much harder fit for App Sandbox than for a plain
  Developer ID build. Developer ID (this build) is the near-term target.
