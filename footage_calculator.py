#!/usr/bin/env python3
"""Footage Calculator — scan a folder and total video/audio durations."""

import os
import subprocess
import shutil
import threading
import tkinter as tk
from tkinter import filedialog, ttk

# ── File extension categories ──────────────────────────────────────────────

VIDEO_EXTS = {
    ".mp4", ".mov", ".avi", ".mkv", ".wmv", ".flv", ".webm", ".m4v",
    ".mpg", ".mpeg", ".3gp", ".ts", ".mts", ".m2ts", ".vob", ".ogv",
    ".mxf", ".r3d", ".braw", ".prores",
}
AUDIO_EXTS = {
    ".mp3", ".wav", ".aac", ".flac", ".ogg", ".wma", ".m4a",
    ".aiff", ".aif", ".opus",
}
IMAGE_EXTS = {
    ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif",
    ".webp", ".heic", ".heif", ".raw", ".cr2", ".nef", ".arw", ".psd",
}


def classify(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in VIDEO_EXTS:
        return "video"
    if ext in AUDIO_EXTS:
        return "audio"
    if ext in IMAGE_EXTS:
        return "image"
    return "other"


def get_duration(path):
    """Return duration in seconds via ffprobe, or None on failure."""
    try:
        result = subprocess.run(
            [
                "ffprobe", "-v", "quiet",
                "-show_entries", "format=duration",
                "-of", "csv=p=0", path,
            ],
            capture_output=True, text=True, timeout=30,
        )
        val = result.stdout.strip()
        if val and val != "N/A":
            return float(val)
    except (subprocess.TimeoutExpired, ValueError, OSError):
        pass
    return None


def format_duration(seconds):
    """Format seconds into HH:MM:SS or MM:SS."""
    total = int(round(seconds))
    h, remainder = divmod(total, 3600)
    m, s = divmod(remainder, 60)
    if h > 0:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


# ── GUI ────────────────────────────────────────────────────────────────────

class FootageCalculator:
    def __init__(self, root):
        self.root = root
        self.root.title("Footage Calculator")
        self.root.resizable(True, True)
        self.root.minsize(480, 400)
        self.scanning = False

        # ── Top controls ───────────────────────────────────────────────
        ctrl = ttk.Frame(root, padding=12)
        ctrl.pack(fill="x")

        row_folder = ttk.Frame(ctrl)
        row_folder.pack(fill="x", pady=(0, 6))
        ttk.Label(row_folder, text="Folder:").pack(side="left")
        self.folder_var = tk.StringVar()
        self.folder_entry = ttk.Entry(row_folder, textvariable=self.folder_var)
        self.folder_entry.pack(side="left", fill="x", expand=True, padx=(6, 6))
        ttk.Button(row_folder, text="Browse…", command=self.browse).pack(side="left")

        self.recursive_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(ctrl, text="Include subfolders", variable=self.recursive_var).pack(anchor="w")

        self.show_other_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(ctrl, text="Show other file types (audio/images)", variable=self.show_other_var).pack(anchor="w")

        self.scan_btn = ttk.Button(ctrl, text="Scan Folder", command=self.start_scan)
        self.scan_btn.pack(pady=(8, 0))

        # ── Separator ──────────────────────────────────────────────────
        ttk.Separator(root).pack(fill="x", padx=12)

        # ── Results area ───────────────────────────────────────────────
        self.results_frame = ttk.Frame(root, padding=12)
        self.results_frame.pack(fill="both", expand=True)
        self.results_label = ttk.Label(
            self.results_frame, text="Select a folder and click Scan.",
            justify="left", wraplength=440,
        )
        self.results_label.pack(anchor="nw", fill="both", expand=True)

        # ── Status bar ─────────────────────────────────────────────────
        self.status_var = tk.StringVar()
        ttk.Label(root, textvariable=self.status_var, padding=(12, 4)).pack(fill="x")

    # ── Actions ────────────────────────────────────────────────────────

    def browse(self):
        path = filedialog.askdirectory()
        if path:
            self.folder_var.set(path)

    def start_scan(self):
        folder = self.folder_var.get().strip()
        if not folder or not os.path.isdir(folder):
            self.results_label.config(text="Please select a valid folder.")
            return
        if not shutil.which("ffprobe"):
            self.results_label.config(
                text="ffprobe not found.\n\n"
                     "Install FFmpeg via Homebrew:\n"
                     "  brew install ffmpeg"
            )
            return
        self.scanning = True
        self.scan_btn.config(state="disabled")
        self.results_label.config(text="")
        self.status_var.set("Collecting files…")
        threading.Thread(target=self.scan, args=(folder,), daemon=True).start()

    def scan(self, folder):
        recursive = self.recursive_var.get()

        # Collect all files
        files = []
        if recursive:
            for dirpath, _, filenames in os.walk(folder):
                for f in filenames:
                    files.append(os.path.join(dirpath, f))
        else:
            for f in os.listdir(folder):
                full = os.path.join(folder, f)
                if os.path.isfile(full):
                    files.append(full)

        total_files = len(files)
        if total_files == 0:
            self.root.after(0, self._finish, {}, "No files found in this folder.")
            return

        # Classify and probe
        stats = {
            "video": {"count": 0, "duration": 0.0, "unknown": 0},
            "audio": {"count": 0, "duration": 0.0, "unknown": 0},
            "image": {"count": 0},
            "other": {"count": 0},
        }

        for i, path in enumerate(files, 1):
            if not self.scanning:
                break
            cat = classify(path)
            stats[cat]["count"] += 1

            if cat in ("video", "audio"):
                dur = get_duration(path)
                if dur is not None:
                    stats[cat]["duration"] += dur
                else:
                    stats[cat]["unknown"] += 1

            # Update progress on the main thread
            self.root.after(0, self.status_var.set,
                            f"Scanning… ({i}/{total_files} files)")

        self.root.after(0, self._finish, stats, None)

    def _finish(self, stats, message):
        self.scanning = False
        self.scan_btn.config(state="normal")
        self.status_var.set("")

        if message:
            self.results_label.config(text=message)
            return

        show_other = self.show_other_var.get()
        lines = []

        # Video (always shown)
        v = stats["video"]
        lines.append("── Video Files ──")
        if v["count"] == 0:
            lines.append("No video files found")
        else:
            dur_str = format_duration(v["duration"])
            parts = [f'{v["count"]} file{"s" if v["count"] != 1 else ""}', f"Total: {dur_str}"]
            if v["unknown"]:
                parts.append(f'{v["unknown"]} with unknown duration')
            lines.append("  ".join(parts))
        lines.append("")

        # Audio
        if show_other:
            a = stats["audio"]
            lines.append("── Audio Files ──")
            if a["count"] == 0:
                lines.append("No audio files found")
            else:
                dur_str = format_duration(a["duration"])
                parts = [f'{a["count"]} file{"s" if a["count"] != 1 else ""}', f"Total: {dur_str}"]
                if a["unknown"]:
                    parts.append(f'{a["unknown"]} with unknown duration')
                lines.append("  ".join(parts))
            lines.append("")

            # Images
            img = stats["image"]
            lines.append("── Image Files ──")
            if img["count"] == 0:
                lines.append("No image files found")
            else:
                lines.append(f'{img["count"]} file{"s" if img["count"] != 1 else ""}')
            lines.append("")

            # Other
            o = stats["other"]
            lines.append("── Other Files ──")
            if o["count"] == 0:
                lines.append("No other files found")
            else:
                lines.append(f'{o["count"]} file{"s" if o["count"] != 1 else ""}')

        self.results_label.config(text="\n".join(lines))


if __name__ == "__main__":
    root = tk.Tk()
    FootageCalculator(root)
    root.mainloop()
