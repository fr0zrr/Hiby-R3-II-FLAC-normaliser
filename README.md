# Hiby R3 II FLAC Normalizer

A PowerShell script to normalize FLAC audio files for optimal playback on the **Hiby R3 II Digital Audio Player**.

## What It Does

This script processes your FLAC music collection and normalizes the audio levels to ensure consistent volume across all your tracks. It's specifically optimized for the Hiby R3 II's audio characteristics, providing you with the best listening experience on your device.

### Key Features

- **ReplayGain Analysis**: Uses industry-standard loudness measurement
- **Hiby R3 II Optimized**: Target levels specifically tuned for this device (-18 LUFS)
- **Batch Processing**: Handle entire music libraries at once
- **Recursive Support**: Process nested folder structures
- **Quality Preservation**: Maintains original FLAC quality while normalizing levels
- **Progress Tracking**: Visual feedback during processing

## Prerequisites

Before using this script, you need to install the following dependencies:

### 1. FFmpeg
Download and install FFmpeg from [https://ffmpeg.org/download.html](https://ffmpeg.org/download.html)

**Windows:**
- Download the latest release
- Extract to a folder (e.g., `C:\ffmpeg`)
- Add the `bin` folder to your system PATH

### 2. ffmpeg-normalize
Install using pip (Python package manager):

```bash
pip install ffmpeg-normalize
```

If you don't have Python/pip installed, download Python from [python.org](https://python.org) first.

## How to Use

### Basic Usage

1. **Open PowerShell** as Administrator (recommended)
2. **Navigate** to the script directory
3. **Run** the script with your input and output paths:

```powershell
.\Normalize-FLAC.ps1 -InputPath "C:\Music\FLAC" -OutputPath "C:\Music\Normalized"
```

### Advanced Usage

```powershell
# Process with custom target level and recursive search
.\Normalize-FLAC.ps1 -InputPath "C:\Music" -OutputPath "C:\Music\Normalized" -TargetLUFS -16 -Recursive

# Process only current directory with default settings
.\Normalize-FLAC.ps1 -InputPath ".\MyMusic" -OutputPath ".\Normalized"
```

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `InputPath` | Yes | - | Source directory containing FLAC files |
| `OutputPath` | Yes | - | Destination directory for normalized files |
| `TargetLUFS` | No | -18 | Target loudness level (recommended: -18 for Hiby R3 II) |
| `Recursive` | No | false | Process subdirectories recursively |

## Example Workflow

1. **Prepare your music**: Organize your FLAC files in a source folder
2. **Run the script**:
   ```powershell
   .\Normalize-FLAC.ps1 -InputPath "D:\Music\FLAC" -OutputPath "D:\Music\HibyReady" -Recursive
   ```
3. **Wait for processing**: The script will show progress for each file
4. **Transfer to device**: Copy normalized files to your Hiby R3 II
5. **Enjoy**: Experience consistent audio levels across your entire library!

## Why Normalize for Hiby R3 II?

The Hiby R3 II is a high-quality digital audio player, but like all portable devices, it benefits from properly normalized audio:

- **Consistent Volume**: No more adjusting volume between tracks
- **Battery Efficiency**: Optimal levels reduce the need for high amplification
- **Dynamic Range**: Preserves musical dynamics while ensuring audibility
- **No Clipping**: Prevents digital distortion on loud passages

## Troubleshooting

### "ffmpeg not found"
- Ensure FFmpeg is installed and added to your system PATH
- Try running `ffmpeg -version` in Command Prompt to verify

### "ffmpeg-normalize not found"
- Install Python and pip first
- Run `pip install ffmpeg-normalize`
- Restart PowerShell after installation

### Script execution policy error
Run this command in PowerShell as Administrator:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Large music libraries
For very large collections (1000+ files), consider:
- Processing in smaller batches
- Using an SSD for faster I/O
- Running overnight for large collections

## Technical Details

- **Target Level**: -18 LUFS (optimal for Hiby R3 II)
- **True Peak Limit**: -1.0 dBFS (prevents clipping)
- **Loudness Range**: 7.0 LU (maintains dynamics)
- **Format**: Preserves original FLAC encoding parameters

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Contributing

Feel free to submit issues, feature requests, or improvements to make this tool even better for the Hiby R3 II community!

---

**Enjoy your perfectly normalized music on your Hiby R3 II! 🎵**
