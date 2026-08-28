File Converter — Resolume DXV3 via Adobe Media Encoder
=======================================================

All existing File Converter presets (MP4, WebM, images, Office, etc.) are unchanged.
DXV3 encode uses Adobe Media Encoder watch folders + the Resolume DXV plugin.

One-time setup
--------------
1. Confirm Adobe Media Encoder is installed (this PC: D:\Adobe\Adobe Media Encoder 2026\).
2. Confirm DXV plugin exists:
   C:\Program Files\Adobe\Common\Plug-ins\7.0\MediaCore\Resolume DXV\DXV3MediaCoreExport.prm
3. Create these folders (File Converter also creates them on first DXV job):

   %LOCALAPPDATA%\FileConverter\ame-watch\dxv-normal-noalpha\input
   %LOCALAPPDATA%\FileConverter\ame-watch\dxv-normal-noalpha\output
   %LOCALAPPDATA%\FileConverter\ame-watch\dxv-normal-withalpha\input
   %LOCALAPPDATA%\FileConverter\ame-watch\dxv-normal-withalpha\output

4. In Adobe Media Encoder: File > Create Watch Folder for each INPUT path.
   - Set Output folder to the matching OUTPUT path.
   - Format = DXV3
   - Compression = Normal Quality, No Alpha   (first pair)
                 = Normal Quality, With Alpha (second pair)
5. Leave AME running when converting to DXV3.

Presets in File Converter (Explorer right-click / CLI)
-----------------------------------------------------
  Resolume/To DXV3 (Normal, No Alpha)
  Resolume/To DXV3 (Normal, With Alpha)
  Resolume/To ProRes 422 MOV
  Resolume/To ProRes 4444 MOV (alpha)

Existing To Mp4 / To Webm already accept .mov (including DXV-in-MOV sources).

CLI example
-----------
  FileConverter.exe --conversion-preset "Resolume/To DXV3 (Normal, No Alpha)" "D:\clip.mp4"
