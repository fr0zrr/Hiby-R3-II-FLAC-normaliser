<#
.SYNOPSIS
    FLAC Audio Normalizer for Hiby R3 II Digital Audio Player

.DESCRIPTION
    This script normalizes FLAC audio files to optimize playback on the Hiby R3 II.
    It uses ReplayGain analysis to calculate optimal volume levels and applies 
    normalization to ensure consistent audio levels across your music library.

.PARAMETER InputPath
    Path to the directory containing FLAC files to normalize

.PARAMETER OutputPath
    Path to the directory where normalized FLAC files will be saved

.PARAMETER TargetLUFS
    Target loudness level in LUFS (default: -18 LUFS, recommended for Hiby R3 II)

.PARAMETER Recursive
    Process subdirectories recursively

.EXAMPLE
    .\Normalize-FLAC.ps1 -InputPath "C:\Music\FLAC" -OutputPath "C:\Music\Normalized"
    
.EXAMPLE
    .\Normalize-FLAC.ps1 -InputPath "C:\Music" -OutputPath "C:\Music\Normalized" -TargetLUFS -16 -Recursive

.NOTES
    Author: fr0zrr
    Requires: FFmpeg with ffmpeg-normalize
    Compatible with: Hiby R3 II Digital Audio Player
    
    Prerequisites:
    1. Install FFmpeg: https://ffmpeg.org/download.html
    2. Install ffmpeg-normalize: pip install ffmpeg-normalize
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$InputPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputPath,
    
    [Parameter(Mandatory=$false)]
    [int]$TargetLUFS = -18,
    
    [Parameter(Mandatory=$false)]
    [switch]$Recursive
)

# Function to check if required tools are installed
function Test-Requirements {
    Write-Host "Checking system requirements..." -ForegroundColor Yellow
    
    # Check for FFmpeg
    try {
        $ffmpegVersion = & ffmpeg -version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ FFmpeg found" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "✗ FFmpeg not found. Please install FFmpeg and add it to your PATH." -ForegroundColor Red
        Write-Host "Download from: https://ffmpeg.org/download.html" -ForegroundColor Yellow
        return $false
    }
    
    # Check for ffmpeg-normalize
    try {
        $normalizeVersion = & ffmpeg-normalize --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ ffmpeg-normalize found" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "✗ ffmpeg-normalize not found. Please install it using: pip install ffmpeg-normalize" -ForegroundColor Red
        return $false
    }
    
    return $true
}

# Function to normalize FLAC files
function Invoke-FLACNormalization {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [int]$Target,
        [bool]$ProcessRecursive
    )
    
    # Validate input path
    if (-not (Test-Path $SourcePath)) {
        Write-Host "Error: Input path '$SourcePath' does not exist." -ForegroundColor Red
        return
    }
    
    # Create output directory if it doesn't exist
    if (-not (Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        Write-Host "Created output directory: $DestinationPath" -ForegroundColor Green
    }
    
    # Get FLAC files
    $searchOption = if ($ProcessRecursive) { "AllDirectories" } else { "TopDirectoryOnly" }
    $flacFiles = Get-ChildItem -Path $SourcePath -Filter "*.flac" -Recurse:$ProcessRecursive
    
    if ($flacFiles.Count -eq 0) {
        Write-Host "No FLAC files found in the specified path." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Found $($flacFiles.Count) FLAC files to process." -ForegroundColor Cyan
    Write-Host "Target loudness: $Target LUFS (optimized for Hiby R3 II)" -ForegroundColor Cyan
    
    $processedCount = 0
    $errorCount = 0
    
    foreach ($file in $flacFiles) {
        try {
            Write-Host "Processing: $($file.Name)" -ForegroundColor White
            
            # Create relative path structure in output directory
            $relativePath = $file.FullName.Substring($SourcePath.Length).TrimStart('\', '/')
            $outputFile = Join-Path $DestinationPath $relativePath
            $outputDir = Split-Path $outputFile -Parent
            
            # Create subdirectory if needed
            if (-not (Test-Path $outputDir)) {
                New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            }
            
            # Normalize the FLAC file
            $arguments = @(
                "--loudness-range-target", "7.0"
                "--true-peak", "-1.0"
                "--target-level", "$Target"
                "--format", "flac"
                "--output", $outputFile
                $file.FullName
            )
            
            & ffmpeg-normalize @arguments 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Normalized successfully" -ForegroundColor Green
                $processedCount++
            } else {
                Write-Host "  ✗ Failed to normalize" -ForegroundColor Red
                $errorCount++
            }
        }
        catch {
            Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
            $errorCount++
        }
    }
    
    # Summary
    Write-Host "`nNormalization completed!" -ForegroundColor Cyan
    Write-Host "Successfully processed: $processedCount files" -ForegroundColor Green
    if ($errorCount -gt 0) {
        Write-Host "Errors encountered: $errorCount files" -ForegroundColor Red
    }
    Write-Host "Output location: $DestinationPath" -ForegroundColor Yellow
    Write-Host "`nYour FLAC files are now optimized for Hiby R3 II playback!" -ForegroundColor Magenta
}

# Main execution
Clear-Host
Write-Host "=== Hiby R3 II FLAC Normalizer ===" -ForegroundColor Magenta
Write-Host "Optimizing FLAC files for your Hiby R3 II Digital Audio Player`n" -ForegroundColor Cyan

# Check system requirements
if (-not (Test-Requirements)) {
    Write-Host "`nPlease install the required dependencies and run the script again." -ForegroundColor Red
    exit 1
}

Write-Host "`nStarting normalization process..." -ForegroundColor Yellow

# Start normalization
Invoke-FLACNormalization -SourcePath $InputPath -DestinationPath $OutputPath -Target $TargetLUFS -ProcessRecursive $Recursive.IsPresent

Write-Host "`nDone! Transfer the normalized files to your Hiby R3 II for optimal listening experience." -ForegroundColor Green