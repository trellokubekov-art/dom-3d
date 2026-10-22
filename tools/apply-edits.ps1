# Переносит расстановку мебели из редактора (файл furniture-edits.js, кнопка «Сохранить в файл»)
# в output\dom-data.js: у каждого передвинутого предмета меняются x, y и поворот rot (в градусах).
# По умолчанию берёт самый свежий furniture-edits*.js из папки «Загрузки».
param([string]$EditsFile)
$data = 'C:\projects\dom-3d\output\dom-data.js'
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
[IO.File]::WriteAllText($data, $t, (New-Object Text.UTF8Encoding $false))
"Перенесено предметов: $done из $(@($edits.PSObject.Properties).Count) (файл: $EditsFile)"
if ($skip) { "Пропущено: " + ($skip -join '; ') }
