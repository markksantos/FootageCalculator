<div align="center">

# 🎬 Footage Calculator

**Scan a folder and instantly total your video footage duration.**

![Python](https://img.shields.io/badge/Python-3.9+-3776AB?style=for-the-badge&logo=python&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![tkinter](https://img.shields.io/badge/tkinter-GUI-blue?style=for-the-badge)
![FFmpeg](https://img.shields.io/badge/FFmpeg-007808?style=for-the-badge&logo=ffmpeg&logoColor=white)

[Features](#-features) · [Getting Started](#-getting-started) · [How It Works](#-how-it-works) · [File Categories](#-file-categories) · [License](#-license)

</div>

---

## ✨ Features

- **Instant Duration Totals** — Point at any folder and get the total runtime of all video files in seconds
- **Recursive Scanning** — Toggle subfolder scanning to total an entire project or just one directory
- **Multi-Format Support** — Recognizes 20+ video formats including .mp4, .mov, .mkv, .r3d, .braw, .mxf, and more
- **Audio & Image Counts** — Optionally shows audio file durations and image/other file counts alongside video totals
- **Responsive UI** — Scanning runs in a background thread so the app never freezes, with live progress updates
- **Zero Python Dependencies** — Uses only tkinter (built-in) and ffprobe (FFmpeg CLI)
- **Native macOS Feel** — Clean, minimal interface that stays out of your way

---

## 🚀 Getting Started

### Prerequisites

- Python 3.9+
- FFmpeg (for `ffprobe`)

```bash
brew install ffmpeg
```

### Running

```bash
git clone https://github.com/markksantos/FootageCalculator.git
cd FootageCalculator
python3 footage_calculator.py
```

No `pip install`, no virtual environment, no setup — just run it.

---

## 🏗️ How It Works

1. **Browse** to a folder containing video files
2. **Click Scan** — the app walks the directory and classifies every file by extension
3. **ffprobe** is called on each video and audio file to extract its duration
4. **Results** are displayed with formatted totals (MM:SS or HH:MM:SS)

Duration detection uses:
```bash
ffprobe -v quiet -show_entries format=duration -of csv=p=0 <file>
```

Files that ffprobe can't read are counted but marked with unknown duration.

---

## 📂 File Categories

| Category | Extensions |
|----------|-----------|
| Video | .mp4, .mov, .avi, .mkv, .wmv, .flv, .webm, .m4v, .mpg, .mpeg, .3gp, .ts, .mts, .m2ts, .vob, .ogv, .mxf, .r3d, .braw, .prores |
| Audio | .mp3, .wav, .aac, .flac, .ogg, .wma, .m4a, .aiff, .aif, .opus |
| Image | .jpg, .jpeg, .png, .gif, .bmp, .tiff, .tif, .webp, .heic, .heif, .raw, .cr2, .nef, .arw, .psd |
| Other | Everything else (counted, not analyzed) |

---

## 📄 License

MIT License © 2026 Mark Santos

---

<div align="center">

Built with ❤️ by [NoSleepLab](https://nosleeplab.com)

</div>
