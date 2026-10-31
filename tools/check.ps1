# Самопроверка модели: двери не перекрыты мебелью, до каждой комнаты можно дойти.
# Печатает отчёт страницы (?check=1), открытой в Edge без окна.
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$prof = Join-Path $env:TEMP "dom3d-edge-profile"
$dom = & $edge --headless=new --user-data-dir="$prof" --use-angle=swiftshader --enable-unsafe-swiftshader --ignore-gpu-blocklist `
  --allow-file-access-from-files --virtual-time-budget=60000 --dump-dom ("file:///" + ((Get-ChildItem "$PSScriptRoot\..\output\*.html" | Select-Object -First 1).FullName -replace '\\', '/') + "?check=1&ui=0") 2>$null
$m = [regex]::Match(($dom -join "`n"), 'CHECK\n([\s\S]*?)\nEND')
if ($m.Success) { $m.Groups[1].Value } else { "Отчёт не найден (страница не успела загрузиться?)" }
