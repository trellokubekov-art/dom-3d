# Переносит правки редактора (файл furniture-edits.js, кнопка «Сохранить в файл») в output\dom-data.js:
#  - положение зданий (window.BLD_EDITS) — строка «garage: { name: '…', x: …, y: …, rot: …»;
#  - мебель (window.FURN_EDITS) — x, y и поворот rot у каждого передвинутого предмета;
#  - граница участка (window.SITE_EDITS) — строка site: { poly: [...] }.
# Редактор пишет координаты УЧАСТКА, а мебель дома и пристроек хранится в местных координатах своего здания,
# поэтому для неё координаты пересчитываются через положение здания (уже новое, если здание тоже двигали).
# По умолчанию берёт самый свежий furniture-edits*.js из папки «Загрузки».
param([string]$EditsFile)
$data = Join-Path $PSScriptRoot '..\output\dom-data.js'
if (-not $EditsFile) {
  $EditsFile = Get-ChildItem "$env:USERPROFILE\Downloads\furniture-edits*.js" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $EditsFile -or -not (Test-Path $EditsFile)) { "Файл furniture-edits.js не найден"; exit 1 }
$raw = [IO.File]::ReadAllText($EditsFile)
$t = [IO.File]::ReadAllText($data)
$inv = [Globalization.CultureInfo]::InvariantCulture
$num = { param($v) ([double]$v).ToString($inv) }

# ---------- 1. здания ----------
$bm = [regex]::Match($raw, 'window\.BLD_EDITS\s*=\s*(\{[^\r\n]*\})\s*;')
if ($bm.Success) {
  $blds = $bm.Groups[1].Value | ConvertFrom-Json
  foreach ($p in $blds.PSObject.Properties) {
    $key = $p.Name; $b = $p.Value
    $rx = "($([regex]::Escape($key)): \{ name: '[^']*', x: )(-?[\d.]+)(, y: )(-?[\d.]+)(, rot: )(-?\d+)"
    $m = [regex]::Match($t, $rx)
    if (-not $m.Success) { "Здание $key — не нашёл строку положения в dom-data.js"; continue }
    if ([double]::Parse($m.Groups[2].Value, $inv) -ne [double]$b.bx -or [double]::Parse($m.Groups[4].Value, $inv) -ne [double]$b.by) { "Здание $key — в dom-data.js уже сдвинуто, пропускаю"; continue }
    $new = $m.Groups[1].Value + (& $num $b.x) + $m.Groups[3].Value + (& $num $b.y) + $m.Groups[5].Value + [int]$b.rot
    $t = $t.Substring(0, $m.Index) + $new + $t.Substring($m.Index + $m.Length)
    "Здание $key перенесено: x $($b.x), y $($b.y), поворот $($b.rot)"
  }
}
# положения зданий (уже новые) и где в файле начинается раздел buildings
$hdrs = @(); foreach ($m in [regex]::Matches($t, "(\w+): \{ name: '[^']*', x: (-?[\d.]+), y: (-?[\d.]+), rot: (-?\d+)")) {
  $hdrs += [pscustomobject]@{ key = $m.Groups[1].Value; idx = $m.Index; x = [double]::Parse($m.Groups[2].Value, $inv); y = [double]::Parse($m.Groups[3].Value, $inv); rot = [int]$m.Groups[4].Value }
}
$bStart = $t.IndexOf('buildings: {'); if ($bStart -lt 0) { $bStart = $t.Length }
$house = $hdrs | Where-Object key -eq 'house' | Select-Object -First 1
function BuildingAt([int]$idx) {   # к какому зданию относится текст на позиции idx
  if ($idx -lt $bStart) { return $house }
  $h = $hdrs | Where-Object { $_.idx -lt $idx -and $_.key -ne 'house' } | Sort-Object idx | Select-Object -Last 1
  if ($h) { return $h } else { return $house }
}
function ToLocal($B, [double]$wx, [double]$wy, [int]$deg) {   # координаты участка → местные координаты здания (rot 0/90/180/270)
  if (-not $B) { return @($wx, $wy, $deg) }
  $r = $B.rot * [Math]::PI / 180; $c = [Math]::Round([Math]::Cos($r)); $sn = [Math]::Round([Math]::Sin($r))
  $dx = $wx - $B.x; $dy = $wy - $B.y
  # каждое значение — в свою переменную: в PowerShell запятая сильнее арифметики, иначе % применится ко всему массиву
  $lx = [Math]::Round($dx * $c - $dy * $sn, 3); $ly = [Math]::Round($dx * $sn + $dy * $c, 3); $ld = (((($deg - $B.rot) % 360) + 360) % 360)
  return @($lx, $ly, $ld)
}

# ---------- 2. мебель ----------
$json = [regex]::Match($raw, 'window\.FURN_EDITS\s*=\s*(\{[\s\S]*\})\s*;').Groups[1].Value
$edits = $json | ConvertFrom-Json
$done = 0; $skip = @()
foreach ($p in $edits.PSObject.Properties) {
  $id = $p.Name; $e = $p.Value
  $m = [regex]::Match($t, "\{ id: '$([regex]::Escape($id))',[^\r\n]*?\}")
  if (-not $m.Success) { $skip += "$id (нет в dom-data.js)"; continue }
  $item = $m.Value
  $B = if ($item -match "bld: 'site'") { $null } else { BuildingAt $m.Index }
  $base = ToLocal $B ([double]$e.bx) ([double]$e.by) ([int]$e.bdeg)
  $new = ToLocal $B ([double]$e.x) ([double]$e.y) ([int]$e.deg)
  if (-not $new -or $new.Count -ne 3 -or -not $base -or $base.Count -ne 3) { $skip += "$id (не удалось пересчитать координаты)"; continue }
  $bx = [regex]::Match($item, "x: (-?[\d.]+)").Groups[1].Value; $by = [regex]::Match($item, "y: (-?[\d.]+)").Groups[1].Value
  if ([Math]::Abs([double]::Parse($bx, $inv) - $base[0]) -gt 0.011 -or [Math]::Abs([double]::Parse($by, $inv) - $base[1]) -gt 0.011) { $skip += "$id (в dom-data.js уже изменён: там $bx; $by, в правке было $($base[0]); $($base[1]))"; continue }
  $s = [regex]::Replace($item, "x: -?[\d.]+", "x: " + (& $num $new[0]), 1)
  $s = [regex]::Replace($s, "y: -?[\d.]+", "y: " + (& $num $new[1]), 1)
  $s = [regex]::Replace($s, ", f: '[+-][xy]'", "")
  $s = [regex]::Replace($s, ", rot: -?\d+", "")
  $s = $s -replace "(y: -?[\d.]+)", ('$1, rot: ' + [int]$new[2])
  $t = $t.Substring(0, $m.Index) + $s + $t.Substring($m.Index + $m.Length)
  $done++
}

# ---------- 3. граница участка ----------
$sm = [regex]::Match($raw, 'window\.SITE_EDITS\s*=\s*(\{[^\r\n]*\})\s*;')
if ($sm.Success) {
  $site = $sm.Groups[1].Value | ConvertFrom-Json
  $pts = ($site.poly | ForEach-Object { '[' + (& $num $_[0]) + ', ' + (& $num $_[1]) + ']' }) -join ', '
  $t = [regex]::Replace($t, "site: \{ poly: \[[^\r\n]*\] \},", "site: { poly: [$pts] },", 1)
  "Граница участка перенесена: $(@($site.poly).Count) углов"
}
[IO.File]::WriteAllText($data, $t, (New-Object Text.UTF8Encoding $false))
"Перенесено предметов: $done из $(@($edits.PSObject.Properties).Count) (файл: $EditsFile)"
if ($skip) { "Пропущено: " + ($skip -join '; ') }
