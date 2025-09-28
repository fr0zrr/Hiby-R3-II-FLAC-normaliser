<#
.SYNOPSIS
  HiBy-safe FLAC normalizer: audit, optionally strip ID3v2, sanitize tags, normalize artwork, and force canonical re-encode.

.DESCRIPTION
  Targets real-world issues that make DAPs (HiBy R3 II, etc.) skip files despite passing flac -t:
    - Non-canonical container / extra junk before fLaC magic
    - ID3v2-in-FLAC / APE tags
    - Wild/huge artwork (progressive JPEGs, >2MB, >2000px)
    - Bizarre tag sets and encodings

  Modes:
    * Audit (default, read-only)
    * StripId3 (in-place removal of ID3v2 in FLAC)
    * Recover (decode-through-errors + re-encode FAILED files only)
    * ForceReencode (re-encode ALL files, even OK, into canonical form; writes to OutRoot)
    * SanitizeTags (whitelist Vorbis comments, drop unknowns; optional map)
    * NormalizeArt (cap pixel size and kb; convert to baseline JPEG; preserves first picture)

  Writes a robust CSV log and prints per-file status lines when -VerboseLog.

.REQUIREMENTS
  - flac.exe, metaflac.exe in PATH (reference tools)
  - ffmpeg.exe in PATH (for artwork re-encode; optional but recommended)

.EXAMPLES
  # Conservative: audit only
  .\Fix-Flac-v2.ps1 -Root "F:\Music"

  # Common HiBy fix: strip ID3v2 in-place, then force canonical copies to Recovered\
  .\Fix-Flac-v2.ps1 -Root "F:\Music" -StripId3 -ForceReencode -NormalizeArt -SanitizeTags

  # Heavy repair: also try to salvage broken files
  .\Fix-Flac-v2.ps1 -Root "F:\Music" -StripId3 -Recover -ForceReencode -NormalizeArt -SanitizeTags
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateScript({Test-Path $_ -PathType Container})]
  [string]$Root,

  [string]$OutRoot = $(Join-Path $Root 'Recovered'),

  [switch]$Recover,
  [switch]$StripId3,
  [switch]$ForceReencode,
  [switch]$SanitizeTags,
  [switch]$NormalizeArt,
  [switch]$VerboseLog,

  # Tag whitelist (Vorbis comments). If empty, use sensible defaults.
  [string[]]$TagWhitelist = @('TITLE','ARTIST','ALBUM','ALBUMARTIST','TRACKNUMBER','TOTALTRACKS','DISCNUMBER','TOTALDISCS','DATE','YEAR','GENRE','COMMENT')
)

# region: Utilities

function Get-Tool([string]$name) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) { return $null }
  return $cmd.Source
}

function Exec-Cmd([string]$exe, [string[]]$args) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $psi.Arguments = ($args -join ' ')
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ ExitCode = $p.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

function Get-RelPath([string]$base, [string]$path) {
  $uriBase = (Resolve-Path -LiteralPath $base).ProviderPath
  $uriPath = (Resolve-Path -LiteralPath $path).ProviderPath
  $uriBaseObj = New-Object System.Uri($uriBase + '\')
  $uriPathObj = New-Object System.Uri($uriPath)
  return $uriBaseObj.MakeRelativeUri($uriPathObj).ToString().Replace('/','\')
}

function Test-FlacHeader([string]$file) {
  try {
    $fs = [System.IO.File]::Open($file, 'Open', 'Read', 'Read')
    $bytes = New-Object byte[] 4
    $null = $fs.Read($bytes, 0, 4)
    $fs.Close()
    return ($bytes[0] -eq 0x66 -and $bytes[1] -eq 0x4C -and $bytes[2] -eq 0x61 -and $bytes[3] -eq 0x43) # 'fLaC'
  } catch { return $false }
}

function Parse-StreamInfo([string]$metaOut) {
  $info = @{
    SampleRate = ''
    Channels = ''
    BitsPerSample = ''
    TotalSamples = ''
    MD5 = ''
  }
  foreach ($line in $metaOut -split "`r?`n") {
    if ($line -match 'sample_rate:\s*(\d+)')      { $info.SampleRate   = $matches[1] }
    elseif ($line -match 'channels:\s*(\d+)')     { $info.Channels     = $matches[1] }
    elseif ($line -match 'bits-per-sample:\s*(\d+)') { $info.BitsPerSample = $matches[1] }
    elseif ($line -match 'total samples:\s*(\d+)')   { $info.TotalSamples  = $matches[1] }
    elseif ($line -match 'MD5 signature:\s*([0-9a-fA-F]{32})') { $info.MD5 = $matches[1] }
  }
  return $info
}

function Has-Id3v2([string]$metaflac, [string]$file) {
  $r = Exec-Cmd $metaflac @('--list','--block-type=ID3v2','--no-filename',"`"$file`"")
  return ($r.StdOut -match 'ID3v2' -or $r.StdErr -match 'ID3v2')
}

function Get-TagDict([string]$metaflac, [string]$file) {
  $tmp = [System.IO.Path]::GetTempFileName()
  $exp = Exec-Cmd $metaflac @('--export-tags-to',"`"$tmp`"","`"$file`"")
  $tags = @{}
  if ($exp.ExitCode -eq 0 -and (Test-Path $tmp)) {
    $lines = Get-Content -LiteralPath $tmp -Encoding UTF8
    foreach ($l in $lines) {
      if ($l -match '^\s*$') { continue }
      $kv = $l.Split('=',2)
      if ($kv.Count -eq 2) {
        $tags[$kv[0]] = $kv[1]
      }
    }
  }
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue | Out-Null
  return $tags
}

function Get-PictureFiles([string]$metaflac, [string]$file, [string]$tmpDir) {
  $pics = @()
  # Export first picture only (HiBy gets grumpy with many)
  $r = Exec-Cmd $metaflac @('--list',"`"$file`"")
  $num = $null
  $cur = $null
  foreach ($line in $r.StdOut -split "`r?`n") {
    if ($line -match 'METADATA block #(\d+)') { $cur = [int]$matches[1] }
    elseif ($line -match 'type:\s*6\s*\(PICTURE\)') {
      if ($null -eq $num) { $num = $cur }
    }
  }
  if ($null -ne $num) {
    $pf = Join-Path $tmpDir ('pic_' + $num + '.bin')
    $e = Exec-Cmd $metaflac @('--export-picture-to',"`"$pf`"",'--block-number',"$num","`"$file`"")
    if ($e.ExitCode -eq 0 -and (Test-Path $pf)) { $pics += $pf }
  }
  return $pics
}

function Write-LogLine([string]$path,[string]$rel,[string]$status,[string]$reason,[bool]$hasId3,[bool]$hasPic,[string]$channels,[string]$sr,[string]$bps,[string]$samples,[string]$md5,[string]$action,[string]$newpath,[string]$csv) {
  $reasonCsv = '"' + ($reason -replace '"','''') + '"'
  $actionCsv = '"' + ($action.Trim() -replace '"','''') + '"'
  $line = ($path + ',' + $rel + ',' + $status + ',' + $reasonCsv + ',' + $hasId3 + ',' + $hasPic + ',' +
           $channels + ',' + $sr + ',' + $bps + ',' + $samples + ',' +
           $md5 + ',' + $actionCsv + ',' + $newpath)
  $line | Out-File -FilePath $csv -Append -Encoding UTF8
}

# endregion

# region: Preflight

$flacExe = Get-Tool 'flac'
$metaExe = Get-Tool 'metaflac'
$ffmpeg  = Get-Tool 'ffmpeg'

if (-not $flacExe -or -not $metaExe) {
  Write-Error "Missing tools. Need 'flac' and 'metaflac' in PATH."
  exit 1
}

$null = New-Item -ItemType Directory -Path $OutRoot -Force | Out-Null
$logCsv = Join-Path $OutRoot 'flac_audit.csv'
if (-not (Test-Path $logCsv)) {
  "Path,RelPath,Status,Reason,HasID3v2,HasPicture,Channels,SampleRate,BitsPerSample,TotalSamples,MD5,ActionTaken,NewPath" | Out-File -FilePath $logCsv -Encoding UTF8
}

# endregion

$files = Get-ChildItem -LiteralPath $Root -Filter *.flac -Recurse -File
$idx = 0

foreach ($f in $files) {
  $idx++
  $rel = Get-RelPath $Root $f.FullName
  if ($VerboseLog) { Write-Host ("[{0}/{1}] {2}" -f $idx, $files.Count, $rel) }

  $headerOk = Test-FlacHeader $f.FullName

  $streamInfoOut = Exec-Cmd $metaExe @('--list','--block-type=STREAMINFO','--no-filename',"`"$($f.FullName)`"")
  $info = Parse-StreamInfo $streamInfoOut.StdOut

  $hasId3 = Has-Id3v2 $metaExe $f.FullName

  $test = Exec-Cmd $flacExe @('-t','-s',"`"$($f.FullName)`"")
  $ok = ($test.ExitCode -eq 0)

  $status = ''
  if ($ok) { $status = 'OK' } else { $status = 'FAIL' }

  $reason = ''
  if (-not $headerOk) { $reason += 'BadMagic; ' }
  if (-not $ok) { $reason += (($test.StdErr + $test.StdOut) -replace '[\r\n]+',' ') }

  $action = ''
  $newPath = ''

  # In-place strip ID3v2 if requested
  if ($StripId3 -and $hasId3) {
    $strip = Exec-Cmd $metaExe @('--remove','--block-type=ID3v2',"`"$($f.FullName)`"")
    if ($strip.ExitCode -eq 0) { $action += 'StrippedID3; ' ; $hasId3 = $false }
    else { $action += 'StripID3Failed; ' }
    # re-test
    $test = Exec-Cmd $flacExe @('-t','-s',"`"$($f.FullName)`"")
    $ok = ($test.ExitCode -eq 0)
    if ($ok) { $status = 'OK' } else { $status = 'FAIL' }
  }

  # Determine if we need to produce a normalized copy
  $needCopy = $ForceReencode -or ($Recover -and -not $ok)

  if ($needCopy) {
    $tmp = Join-Path $OutRoot ("_tmp_" + [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetRandomFileName()))
    $null = New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    # Export tags (dict), export first picture if present
    $tags = @{}
    if ($SanitizeTags) {
      $tags = Get-TagDict $metaExe $f.FullName
    }

    $picList = @()
    if ($NormalizeArt -or $SanitizeTags) {
      $picList = Get-PictureFiles $metaExe $f.FullName $tmp
    }

    # Decode (for Recover, allow -F). For ForceReencode of OK files, normal decode (-d) is enough.
    $wav = Join-Path $tmp 'audio.wav'
    $decArgs = @('-d','-f','-o',"`"$wav`"","`"$($f.FullName)`"")
    if (-not $ok) { $decArgs = @('-d','-f','-F','-o',"`"$wav`"","`"$($f.FullName)`"") }
    $dec = Exec-Cmd $flacExe $decArgs

    if ($dec.ExitCode -ne 0 -or -not (Test-Path $wav)) {
      if ($Recover -and (Get-Tool 'ffmpeg')) {
        $dec2 = Exec-Cmd $ffmpeg @('-v','warning','-hide_banner','-y','-err_detect','ignore_err','-i',"`"$($f.FullName)`"",
                                   '-map','0:a:0','-vn','-sn','-dn','-c:a','pcm_s16le',"`"$wav`"")
        if ($dec2.ExitCode -ne 0 -or -not (Test-Path $wav)) {
          $action += 'DecodeFailed; '
          Write-LogLine $f.FullName $rel 'RECOVERY_FAILED' $reason $hasId3 $false $info.Channels $info.SampleRate $info.BitsPerSample $info.TotalSamples $info.MD5 $action $newPath $logCsv
          Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
          continue
        } else {
          $action += 'DecodedWithFFmpeg; '
        }
      } else {
        $action += 'DecodeFailed; '
        Write-LogLine $f.FullName $rel $status $reason $hasId3 $false $info.Channels $info.SampleRate $info.BitsPerSample $info.TotalSamples $info.MD5 $action $newPath $logCsv
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        continue
      }
    } else {
      $action += 'DecodedWithFlac; '
    }

    # Re-encode canonical
    $dst = Join-Path $OutRoot $rel
    $null = New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
    $enc = Exec-Cmd $flacExe @('-f','-8','--verify','-o',"`"$dst`"","`"$wav`"")
    if ($enc.ExitCode -eq 0 -and (Test-Path $dst)) {
      $action += 'ReEncoded; '
      $newPath = $dst

      # Sanitize tags
      if ($SanitizeTags) {
        # Remove all tags then re-add only whitelisted (case-insensitive compare)
        [void](Exec-Cmd $metaExe @('--remove-all-tags',"`"$dst`""))
        foreach ($k in $tags.Keys) {
          $kk = $k.ToUpperInvariant()
          if ($TagWhitelist -contains $kk) {
            $v = $tags[$k]
            [void](Exec-Cmd $metaExe @('--set-tag',"`"$kk=$v`"","`"$dst`""))
          }
        }
      }

      # Normalize first artwork (optional)
      if ($NormalizeArt -and $picList.Count -gt 0 -and (Get-Tool 'ffmpeg')) {
        # Convert first exported picture to baseline jpeg <= 1200px on longest side, quality ~3 (~ good), target <= 500KB
        $srcPic = $picList[0]
        $jpg = Join-Path $tmp 'cover.jpg'
        $ff1 = Exec-Cmd $ffmpeg @('-v','warning','-hide_banner','-y','-i',"`"$srcPic`"",
                                  '-vf','scale=''min(1200,iw)'':-2','-q:v','3','-pix_fmt','yuvj420p',"`"$jpg`"")
        if ((Test-Path $jpg)) {
          # Drop existing pictures then import new
          [void](Exec-Cmd $metaExe @('--remove','--block-type=PICTURE',"`"$dst`""))
          $imp = Exec-Cmd $metaExe @('--import-picture-from',"`"$jpg`"","`"$dst`"")
          if ($imp.ExitCode -eq 0) { $action += 'ArtNormalized; ' } else { $action += 'ArtNormalizeFailed; ' }
        } else {
          $action += 'ArtNormalizeFailed; '
        }
      }

      # Final verify
      $vt = Exec-Cmd $flacExe @('-t','-s',"`"$dst`"")
      if ($vt.ExitCode -eq 0) {
        if (-not $ok) { $status = 'RECOVERED' } else { $status = 'NORMALIZED' }
      } else {
        $status = 'VERIFY_FAILED'
        $action += 'VerifyFailed; '
      }
    } else {
      $action += 'ReEncodeFailed; '
    }

    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
  }

  # Detect picture presence for logging
  $hasPic = $false
  $picProbe = Exec-Cmd $metaExe @('--list','--block-type=PICTURE','--no-filename',"`"$($newPath -ne '' ? $newPath : $f.FullName)`"")
  if ($picProbe.StdOut -match '\(PICTURE\)') { $hasPic = $true }

  Write-LogLine $f.FullName $rel $status $reason $hasId3 $hasPic $info.Channels $info.SampleRate $info.BitsPerSample $info.TotalSamples $info.MD5 $action $newPath $logCsv
}

Write-Host ""
Write-Host "Done. CSV report: $logCsv"
Write-Host "Statuses:"
Write-Host "  OK           = Passed integrity test"
Write-Host "  FAIL         = Failed integrity test"
Write-Host "  RECOVERED    = Salvaged broken original into canonical copy"
Write-Host "  NORMALIZED   = Canonical copy created from OK original"
Write-Host "  VERIFY_FAILED= New file failed post-encode verification"
Write-Host ""
Write-Host "Tip: For HiBy, try: -StripId3 -ForceReencode -NormalizeArt -SanitizeTags"
