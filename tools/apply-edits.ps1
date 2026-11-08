# Переносит расстановку мебели из редактора (файл furniture-edits.js, кнопка «Сохранить в файл»)
# в output\dom-data.js: у каждого передвинутого предмета меняются x, y и поворот rot (в градусах).
# По умолчанию берёт самый свежий furniture-edits*.js из папки «Загрузки».
param([string]$EditsFile)
$data = Join-Path $PSScriptRoot '..\output\dom-data.js'
if (-not $EditsFile) {
  $EditsFile = Get-ChildItem "$env:USERPROFILE\Downloads\furniture-edits*.js" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $EditsFile -or -not (Test-Path $EditsFile)) { "Файл furniture-edits.js не найден"; exit 1 }
$raw = [IO.File]::ReadAllText($EditsFile)
$json = [regex]::Match($raw, 'window\.FURN_EDITS\s*=\s*(\{[\s\S]*\})\s*;').Groups[1].Value
$edits = $json | ConvertFrom-Json
$t = [IO.File]::ReadAllText($data)
$inv = [Globalization.CultureInfo]::InvariantCulture
$done = 0; $skip = @()
foreach ($p in $edits.PSObject.Properties) {
  $id = $p.Name; $e = $p.Value
  $m = [regex]::Match($t, "\{ id: '$([regex]::Escape($id))',[^\r\n]*?\}")
  if (-not $m.Success) { $skip += "$id (нет в dom-data.js)"; continue }
  $item = $m.Value
  $bx = [regex]::Match($item, "x: (-?[\d.]+)").Groups[1].Value; $by = [regex]::Match($item, "y: (-?[\d.]+)").Groups[1].Value
  if ([double]::Parse($bx, $inv) -ne [double]$e.bx -or [double]::Parse($by, $inv) -ne [double]$e.by) { $skip += "$id (в dom-data.js уже изменён)"; continue }
  $new = [regex]::Replace($item, "x: -?[\d.]+", "x: " + ([double]$e.x).ToString($inv), 1)
  $new = [regex]::Replace($new, "y: -?[\d.]+", "y: " + ([double]$e.y).ToString($inv), 1)
  $new = [regex]::Replace($new, ", f: '[+-][xy]'", "")
  $new = [regex]::Replace($new, ", rot: -?\d+", "")
  $new = $new -replace "(y: -?[\d.]+)", ('$1, rot: ' + [int]$e.deg)
  $t = $t.Substring(0, $m.Index) + $new + $t.Substring($m.Index + $m.Length)
  $done++
}
# положение зданий (window.BLD_EDITS: { garage: { x, y, rot, bx, by, brot } }) — строка «garage: { name: '…', x: …, y: …, rot: …,» в dom-data.js
$bm = [regex]::Match($raw, 'window\.BLD_EDITS\s*=\s*(\{[^\r\n]*\})\s*;')
if ($bm.Success) {
  $blds = $bm.Groups[1].Value | ConvertFrom-Json
  foreach ($p in $blds.PSObject.Properties) {
    $key = $p.Name; $b = $p.Value
    $rx = "($([regex]::Escape($key)): \{ name: '[^']*', x: )(-?[\d.]+)(, y: )(-?[\d.]+)(, rot: )(-?\d+)"
    $m = [regex]::Match($t, $rx)
    if (-not $m.Success) { "Здание $key — не нашёл строку положения в dom-data.js"; continue }
    if ([double]::Parse($m.Groups[2].Value, $inv) -ne [double]$b.bx -or [double]::Parse($m.Groups[4].Value, $inv) -ne [double]$b.by) { "Здание $key — в dom-data.js уже сдвинуто, пропускаю"; continue }
    $new = $m.Groups[1].Value + ([double]$b.x).ToString($inv) + $m.Groups[3].Value + ([double]$b.y).ToString($inv) + $m.Groups[5].Value + [int]$b.rot
    $t = $t.Substring(0, $m.Index) + $new + $t.Substring($m.Index + $m.Length)
    "Здание $key перенесено: x $($b.x), y $($b.y), поворот $($b.rot)"
  }
}
# граница участка (если в файле есть window.SITE_EDITS) — строка site: { poly: [...] } в dom-data.js
$sm = [regex]::Match($raw, 'window\.SITE_EDITS\s*=\s*(\{[^\r\n]*\})\s*;')
if ($sm.Success) {
  $site = $sm.Groups[1].Value | ConvertFrom-Json
  $pts = ($site.poly | ForEach-Object { '[' + ([double]$_[0]).ToString($inv) + ', ' + ([double]$_[1]).ToString($inv) + ']' }) -join ', '
  $t = [regex]::Replace($t, "site: \{ poly: \[[^\r\n]*\] \},", "site: { poly: [$pts] },", 1)
  "Граница участка перенесена: $(@($site.poly).Count) углов"
}
[IO.File]::WriteAllText($data, $t, (New-Object Text.UTF8Encoding $false))
"Перенесено предметов: $done из $(@($edits.PSObject.Properties).Count) (файл: $EditsFile)"
if ($skip) { "Пропущено: " + ($skip -join '; ') }
