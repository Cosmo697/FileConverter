#Requires -Version 5.1
<#
.SYNOPSIS
  Install File Converter (copy-based) with Explorer shell extension.

.DESCRIPTION
  The Explorer right-click menu is the product. This script copies the Release
  build, writes HKCU\Software\FileConverter\Path, initializes presets, registers
  the SharpShell context menu, and restarts Explorer.

  Use this instead of the WiX MSI (MSI hangs on the same shell registration).

.PARAMETER SkipShell
  Copy + presets only; do not register the context menu (not recommended).

.PARAMETER NoExplorerRestart
  Do not restart Explorer after registration.
#>
[CmdletBinding()]
param(
    [string]$TargetDir = (Join-Path $env:LOCALAPPDATA 'Programs\File Converter'),
    [string]$SourceDir = 'D:\coding\projects\FileConverter\Application\FileConverter\bin\x64\Release',
    [switch]$SkipShell,
    [switch]$NoExplorerRestart,
    # Kept for callers that still pass -RegisterShell (now the default).
    [switch]$RegisterShell
)

$ErrorActionPreference = 'Stop'
$wantShell = -not $SkipShell

function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'FileConverter.exe'))) {
    throw "Missing FileConverter.exe in $SourceDir — build Release x64 first."
}

if ($wantShell -and -not (Test-IsAdmin)) {
    Write-Host 'Shell extension needs elevation. Relaunching elevated...'
    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-TargetDir', $TargetDir,
        '-SourceDir', $SourceDir
    )
    if ($NoExplorerRestart) { $argList += '-NoExplorerRestart' }
    $p = Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList -Wait -PassThru
    exit $p.ExitCode
}

Write-Host "Source: $SourceDir"
Write-Host "Target: $TargetDir"

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
robocopy $SourceDir $TargetDir /E /XD obj /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit $LASTEXITCODE" }

$exe = Join-Path $TargetDir 'FileConverter.exe'
$ext = Join-Path $TargetDir 'FileConverterExtension.dll'
if (-not (Test-Path -LiteralPath $exe)) { throw "Copy failed: $exe missing" }
if (-not (Test-Path -LiteralPath $ext)) { throw "Copy failed: $ext missing" }

# Extension + presets both resolve FileConverter.exe from this key (same as the MSI).
Write-Host "Writing HKCU\\Software\\FileConverter Path = $exe"
New-Item -Path 'HKCU:\Software\FileConverter' -Force | Out-Null
Set-ItemProperty -LiteralPath 'HKCU:\Software\FileConverter' -Name 'Path' -Value $exe -Type String

Write-Host 'Initializing presets (--post-install-init)...'
# Quote paths with spaces ("File Converter") as one argv token.
$p = Start-Process -FilePath $exe -ArgumentList '--post-install-init' -WorkingDirectory $TargetDir -Wait -PassThru
if ($p.ExitCode -ne 0) {
    Write-Warning "post-install-init exit $($p.ExitCode) (often OK if settings already exist)"
}

$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\File Converter'
New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
$ws = New-Object -ComObject WScript.Shell
foreach ($pair in @(
        @{ Name = 'File Converter.lnk'; Args = $null },
        @{ Name = 'File Converter Settings.lnk'; Args = '--settings' }
    )) {
    $lnk = $ws.CreateShortcut((Join-Path $startMenu $pair.Name))
    $lnk.TargetPath = $exe
    $lnk.WorkingDirectory = $TargetDir
    if ($pair.Args) { $lnk.Arguments = $pair.Args }
    $lnk.Save()
}

if ($wantShell) {
    Write-Host "Registering shell extension: $ext"
    $r = Start-Process -FilePath $exe `
        -ArgumentList "--register-shell-extension `"$ext`"" `
        -WorkingDirectory $TargetDir -Wait -PassThru
    if ($null -eq $r.ExitCode -or $r.ExitCode -ne 0) {
        throw "Shell registration failed (exit $($r.ExitCode))"
    }
    Write-Host 'Shell extension registered (HKLM Classes + ContextMenuHandlers).'

    if (-not $NoExplorerRestart) {
        Write-Host 'Restarting Explorer so the context menu loads...'
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
            Start-Process explorer
        }
    }
} else {
    Write-Warning 'SkipShell set — Explorer right-click menu was NOT registered.'
}

Write-Host ''
Write-Host "Installed: $exe"
Write-Host 'Right-click a video/image in Explorer → File Converter → pick a preset.'
Write-Host '(Win11: if you only see a short menu, use Show more options, or keep the classic-menu registry tweak.)'
