# Signora for Windows

Signora on Windows is a native **WinUI 3** application, not a port of the Android
UI. The frontend uses Fluent controls, Mica, a native title bar, XAML settings,
and Win2D for the camera surface and landmark overlay. The camera, MediaPipe,
and model inference stay in the Python engine because those libraries are
Python-first.

```
┌──────────────────────────────┐        localhost HTTP        ┌──────────────────────┐
│  Signora.Windows.exe         │  <── /video (MJPEG) ───────  │  Python engine       │
│  WinUI 3 + Win2D             │  <── /api/status (JSON) ───  │  MediaPipe + MLP     │
│  native controls, transcript │  ──  /api/command (JSON) ──> │  camera + Piper TTS  │
└──────────────────────────────┘                              └──────────────────────┘
```

The engine streams clean frames. The WinUI app draws the skeleton and hands in
Win2D at native resolution, so the overlay stays crisp and the UI stays in
control of the visual design.

## One-click install (stock Windows laptop)

1. Copy or clone this repository onto the Windows laptop.
2. Double-click **`Pixel-Install.cmd`** for the game-style installer, or
   **`Setup-Windows.cmd`** for the plain one.
3. The script provisions:
   - Visual C++ runtime (when permitted)
   - a user-local Python 3.11 runtime through `uv`
   - PyTorch CPU, MediaPipe, OpenCV, and the Signora package
   - the neural model and Piper voice assets
   - a user-local .NET 8 SDK
   - the self-contained WinUI 3 app
   - a desktop shortcut to `Signora.Windows.exe`
4. It launches the native app when the build succeeds.

For the guided installer with prompts, double-click **`Install-Signora.cmd`**.

Installer flags:
```powershell
.\setup-windows.ps1 -Pixel      # animated pixel-game console
.\setup-windows.ps1 -NoLaunch
.\setup-windows.ps1 -NoShortcut
.\setup-windows.ps1 -SkipModels
.\setup-windows.ps1 -Silent     # no output except errors
```

No Python, OpenCV, .NET, or Visual Studio is required on the target machine
before starting. An internet connection is required during setup.

If PowerShell blocks the script, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1
```

Build output and compiler errors are written to `publish.log` in the repository
root.

## Developer build

On a Windows machine with the repository already prepared:

```powershell
cd windows
.\build.ps1
.\dist\Signora\Signora.Windows.exe
```

The build is self-contained. `signora-root.txt` next to the executable tells the
app where the Python project lives. You can override it with `SIGNORA_ROOT`, and
override the interpreter with `SIGNORA_PYTHON`.

## Engine bridge

The frontend launches:

```
<venv>\Scripts\python.exe -m signora.cli native --mode isl --port 8899
```

Available endpoints:

| Endpoint | Meaning |
| --- | --- |
| `GET /video` | MJPEG camera stream |
| `GET /api/status` | landmarks, pose, active sign, confidence, dwell, transcript, FPS |
| `POST /api/command` | `{"action":"space"}` / `backspace` / `clear` / `speak` / `set` |
| `GET /api/health` | startup readiness |

The bridge can be smoke-tested without a camera:

```powershell
$env:PYTHONPATH = "src"
.\.venv\Scripts\python.exe -m signora.cli native --mode isl --fake-camera --port 8899
```

Then open `http://127.0.0.1:8899/api/status` and `http://127.0.0.1:8899/video`.

## Settings

Settings are stored at `%LOCALAPPDATA%\Signora\settings.json`:

- default mode (ISL / ASL / Body)
- quality profile (`high` uses BlazePose Full and 960 px hand inference)
- camera index
- mirror, speech feedback
- dwell and confidence threshold

Apply settings by restarting the Live session. The engine is intentionally
restarted per mode so MediaPipe graphs are never left in a mixed state.

## Training

The Train page imports `.npy` classes into `data\isl_spatial` and runs
`scripts\train_isl.py --spatial --exclude SUII_MOTION` while streaming the log
into the UI. `SUII_MOTION` stays excluded so the baseline checkpoint cannot
reintroduce it.

## Troubleshooting

- **Black preview**: try another camera index in Settings. Close Teams/Zoom or
  any app that may hold the camera.
- **Low FPS**: set quality to Balanced. This uses BlazePose Lite at 320 px.
- **Engine fails to start**: run `signora native --mode isl` from the install
  directory to see the Python error, or check the log line under the video.
- **ASL selected but no signs**: the ASL weights are downloaded on first use.
  Ensure the machine is online for that first launch.
- **Setup window closes after "Press any key"**: the script stopped before
  finishing. Re-run it and read `install-error.log` in the repository root; it
  records the failing line, command, and stack trace.
- **The app flashes and exits**: `%LOCALAPPDATA%\Signora\startup-error.log`
  holds the exception, and a dialog shows it on screen. Mica is applied only on
  Windows 11, so Windows 10 uses the default backdrop.
