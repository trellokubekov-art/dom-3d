# Снимок 3D-сцены без открытия окна (Edge в «невидимом» режиме).
# Пример: .\snap.ps1 -Query "view=walk-gf&pos=22,3&yaw=180" -Out C:\temp\living.png
param(
  [string]$Query = "",
  [Parameter(Mandatory = $true)][string]$Out,
  [int]$W = 1400,
  [int]$H = 900,
  [int]$WaitMs = 30000
)
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$html = Get-ChildItem "$PSScriptRoot\..\output\*.html" | Select-Object -First 1   # страница проекта (dom-3d.html / dom-3d-2.html …)
$page = "file:///" + ($html.FullName -replace '\\', '/')
if ($Query) { $page += "?" + $Query }
$prof = Join-Path $env:TEMP "dom3d-edge-profile"
& $edge --headless=new --user-data-dir="$prof" --use-angle=swiftshader --enable-unsafe-swiftshader --ignore-gpu-blocklist `
  --allow-file-access-from-files --hide-scrollbars --window-size="$W,$H" --virtual-time-budget=$WaitMs --screenshot="$Out" "$page" 2>$null | Out-Null
if (Test-Path $Out) { "OK $Out" } else { "НЕ ПОЛУЧИЛОСЬ" }
