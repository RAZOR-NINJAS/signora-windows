# Signora Installation Guide

This guide covers complete automated and manual installation methods for Linux, macOS, and Windows.

---

## 1. Quick Automated Install (Recommended)

### Linux & macOS
Run the one-line bootstrap in your terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/RAZOR-NINJAS/signora/main/install.sh | bash
```

### Windows 10 & 11 (Native WinUI 3 App, Non-Admin / Barebones Laptop)
Double-click `Install-Signora.cmd` in the repository root, or run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```
The bootstrap provisions Python 3.11, OpenCV, MediaPipe, PyTorch CPU, the model
assets, a user-local .NET 8 SDK, and the self-contained WinUI 3 app. No Python,
OpenCV, or Visual Studio is required before starting.

---

## 2. Manual Installation by Operating System

### Arch Linux / Omarchy
```bash
# 1. Install system prerequisites
sudo pacman -S --needed git python python-pip

# 2. Clone repository
git clone https://github.com/RAZOR-NINJAS/signora.git
cd signora

# 3. Create virtual environment using Python 3.11 or 3.12
python -m venv .venv
source .venv/bin/activate

# 4. Install CPU-only PyTorch and project dependencies
pip install --upgrade pip
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
pip install -e .

# 5. Fetch model weights & verify
python scripts/fetch_models.py
signora doctor
```

### Ubuntu & Debian
```bash
# 1. Install prerequisites (Python 3.11 required for MediaPipe wheels)
sudo apt update
sudo apt install -y git python3.11 python3.11-venv python3-pip

# 2. Clone and enter repo
git clone https://github.com/RAZOR-NINJAS/signora.git
cd signora

# 3. Setup venv
python3.11 -m venv .venv
source .venv/bin/activate

# 4. Install dependencies
pip install --upgrade pip
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
pip install -e .

# 5. Fetch weights
python scripts/fetch_models.py
signora doctor
```

### Windows One-Shot Setup
From the repository root on a stock Windows 10/11 laptop, double-click
`Pixel-Install.cmd` for the animated pixel-game installer, or run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1 -Pixel
```
This provisions Python 3.11, PyTorch CPU, MediaPipe, OpenCV, the model assets,
a user-local .NET 8 SDK, publishes the native WinUI 3 app, creates a desktop
shortcut, and launches it. No preinstalled Python, OpenCV, or Visual Studio is
required. The build log is written to `publish.log`.

For the guided installer with prompts, double-click `Install-Signora.cmd`.

### Windows Manual Setup
```powershell
# 1. Clone or download Signora
git clone https://github.com/RAZOR-NINJAS/signora.git
cd signora

# 2. Create venv with Python 3.11
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1

# 3. Install CPU PyTorch and dependencies
pip install --upgrade pip
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
pip install -e .

# 4. Download models
python scripts\fetch_models.py

# 5. Verify
.\signora.bat doctor

# 6. Build and launch the native WinUI 3 app
cd windows
.\build.ps1
.\dist\Signora\Signora.Windows.exe
```

The native app is the primary Windows experience. The `signora.bat` launcher
remains available as a terminal fallback.

---

## 3. Verifying the Installation

Run the built-in diagnostic doctor:
```bash
signora doctor
```
Expected output:
```
All core systems are operational and ready for use!
```
If any check reports `FAIL`, follow the printed actionable recommendation or consult [TROUBLESHOOTING.md](file:///home/vaibhav/Projects/signora/docs/TROUBLESHOOTING.md).
