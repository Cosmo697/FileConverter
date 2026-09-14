#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$configPath = 'P:\PortableApps\app-launcher\config.json'
$bat = 'D:\coding\projects\droplets\Convert-Video-DXV3.bat'
$fc = 'D:\coding\projects\FileConverter\Application\FileConverter\bin\x64\Release\FileConverter.exe'
if (-not (Test-Path -LiteralPath $configPath)) { throw "Missing $configPath" }
if (-not (Test-Path -LiteralPath $bat)) { throw "Missing $bat" }

$backup = "$configPath.bak-fc-dxv-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -LiteralPath $configPath -Destination $backup -Force

$py = @'
import json
from pathlib import Path
cfg_path = Path(r"P:\PortableApps\app-launcher\config.json")
bat = Path(r"D:\coding\projects\droplets\Convert-Video-DXV3.bat")
fc = Path(r"D:\coding\projects\FileConverter\Application\FileConverter\bin\x64\Release\FileConverter.exe")
data = json.loads(cfg_path.read_text(encoding="utf-8"))
droplets = data.setdefault("droplets", [])

def upsert(entry_id, entry):
    global droplets
    droplets = [d for d in droplets if d.get("id") != entry_id]
    droplets.append(entry)

upsert("ddxv3convert", {
    "id": "ddxv3convert",
    "label": "Convert Video DXV3 (File Converter)",
    "path": str(bat).replace("\\", "/"),
    "type": "bat",
    "args": "",
    "working_dir": str(bat.parent),
    "run_as_admin": False,
    "tooltip": "DXV3 via ffmpeg-dxv3 (dxt1/dxt5); modes 3-6 File Converter",
    "accepts": "files",
    "extensions": [".mp4", ".mov", ".mkv", ".avi", ".webm", ".m4v", ".dxv3", ".wmv", ".mpg", ".mpeg"]
})

if fc.exists():
    upsert("dfileconverter", {
        "id": "dfileconverter",
        "label": "File Converter (Settings)",
        "path": str(fc).replace("\\", "/"),
        "type": "exe",
        "args": "--settings",
        "working_dir": str(fc.parent),
        "run_as_admin": False,
        "tooltip": "Open File Converter settings (all presets including Resolume/DXV3)",
        "accepts": "files",
        "extensions": []
    })

data["droplets"] = droplets
cfg_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("ok", [d["id"] for d in droplets if d["id"] in ("ddxv3convert", "dfileconverter")])
'@
$pyPath = Join-Path $env:TEMP 'register-fc-dxv.py'
Set-Content -LiteralPath $pyPath -Value $py -Encoding UTF8
python $pyPath
if ($LASTEXITCODE -ne 0) { throw 'register failed' }
Write-Host "Backup: $backup"
