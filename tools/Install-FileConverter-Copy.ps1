#Requires -Version 5.1
<#
.SYNOPSIS
  Install File Converter without the WiX MSI (copy-based).

.DESCRIPTION
  Copies the Release build to a local Programs folder, initializes presets,
  creates a Start Menu shortcut, and optionally registers the Explorer
  shell extension (separate step — that is what hangs the MSI).

.PARAMETER TargetDir
  Install directory. Default: %LOCALAPPDATA%\Programs\File Converter

.PARAMETER RegisterShell
  Also register the Explorer context-menu extension (needs elevation).

.PARAMETER SourceDir
  Build output to copy. Default: repo Release x64 output.
#>
[CmdletBinding()]
param(
    [string]$TargetDir = (Join-Path $env:LOCALAPPDATA 'Programs\File Converter'),
    [string]$SourceDir = 'D:\coding\projects\FileConverter\Application\FileConverter\bin\x64\Release',
    [switch]$RegisterShell
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'FileConverter.exe'))) {
    throw "Missing FileConverter.exe in $SourceDir — build Release x64 first."
}

Write-Host "Source: $SourceDir"
Write-Host "Target: $TargetDir"

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

# Mirror build output (exe + ffmpeg + languages + extension dll).
robocopy $SourceDir $TargetDir /E /XD obj /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
$rc = $LASTEXITCODE
if ($rc -ge 8) { throw "robocopy failed with exit $rc" }

$exe = Join-Path $TargetDir 'FileConverter.exe'
$ext = Join-Path $TargetDir 'FileConverterExtension.dll'
if (-not (Test-Path -LiteralPath $exe)) { throw "Copy failed: $exe missing" }

Write-Host 'Initializing presets (--post-install-init)...'
$p = Start-Process -FilePath $exe -ArgumentList '--post-install-init' -WorkingDirectory $TargetDir -Wait -PassThru
if ($p.ExitCode -ne 0) {
    Write-Warning "post-install-init exit $($p.ExitCode) (often OK if settings already exist)"
}

$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\File Converter'
New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut((Join-Path $startMenu 'File Converter.lnk'))
$lnk.TargetPath = $exe
$lnk.WorkingDirectory = $TargetDir
$lnk.Description = 'File Converter'
$lnk.Save()
$lnk2 = $ws.CreateShortcut((Join-Path $startMenu 'File Converter Settings.lnk'))
$lnk2.TargetPath = $exe
$lnk2.Arguments = '--settings'
$lnk2.WorkingDirectory = $TargetDir
$lnk2.Description = 'File Converter Settings'
$lnk2.Save()

Write-Host "Installed. Launch: `"$exe`""
Write-Host "Settings: `"$exe`" --settings"

if ($RegisterShell) {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'RegisterShell requires an elevated PowerShell (Run as administrator).'
    }
    if (-not (Test-Path -LiteralPath $ext)) { throw "Missing extension DLL: $ext" }
    Write-Host "Registering shell extension: $ext"
    # Start-Process -ArgumentList array splits on spaces inside paths ("File Converter").
    # Pass one quoted argument string so the DLL path stays a single argv token.
    $r = Start-Process -FilePath $exe `
        -ArgumentList "--register-shell-extension `"$ext`"" `
        -WorkingDirectory $TargetDir -Wait -PassThru
    if ($null -eq $r.ExitCode -or $r.ExitCode -ne 0) {
        throw "Shell registration failed (exit $($r.ExitCode))"
    }
    Write-Host 'Shell extension registered. Restart Explorer or sign out/in if the context menu is missing.'
} else {
    Write-Host ''
    Write-Host 'Explorer right-click menu was NOT registered (avoids the MSI hang).'
    Write-Host 'Use Start Menu, App Launcher, or the droplet. To add the context menu later (elevated):'
    Write-Host "  pwsh -File `"$PSCommandPath`" -RegisterShell"
}
