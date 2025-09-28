# Fix-Flac-Folder

**Batch FLAC integrity tester and auto-repair script for Windows (PowerShell).**

This script recursively scans a folder for `.flac` files, verifies their integrity using the official `flac.exe` tool, and attempts to automatically repair any broken files.

---

## How it works

- Runs `flac.exe -t` to test every file.  
- If a file is corrupt:
  1. **First attempt:** remux/re-encode with FFmpeg (preserves tags and cover art).  
  2. **Fallback attempt:** decode with `flac.exe --decode-through-errors`, then re-encode.  
- If the repaired file passes verification, it replaces the original (optional `.bak` backup kept).  
- If all attempts fail, the file is moved into a `_FAILED` quarantine folder.  
- Generates a CSV log of all actions taken.  

---

## Features

- Fully automated, recursive folder scan  
- Keeps backups of originals (optional)  
- Quarantine for hopelessly corrupted files  
- Works with large libraries  

---

## Requirements

- Windows with [flac.exe](https://xiph.org/flac/) and [ffmpeg.exe](https://ffmpeg.org/) available in `PATH`  
- PowerShell 5+ (comes with Windows 10/11)  

---

## Usage

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Fix-Flac-Folder.ps1 -Path "D:\Music\Broken FLACs" -KeepBackups -QuarantineFailed

