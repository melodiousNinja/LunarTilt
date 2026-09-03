param([string]$SeqPath = "artifacts\\seq\\lunar_seq")
## Analyze a sequence of on-device screenshots: for each consecutive pair,
## report the fraction of pixels that changed and where (left/right/top/bottom),
## so a blind observer can reconstruct live on-screen motion (ball launches,
## captures, rollbacks, UI changes). Outputs a CSV on stdout.
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SeqPath)) { $SeqPath = "artifacts\\seq" }
$files = Get-ChildItem -Path $SeqPath -Filter '*.png' | Sort-Object Name
if ($files.Count -lt 2) { Write-Output 'NO_FRAMES'; exit }

"idx,changePct,regions"
$prev = $null
$prevBmp = $null
$i = 0
foreach ($f in $files) {
  $bmp = [System.Drawing.Bitmap]::FromFile($f.FullName)
  $w = $bmp.Width; $h = $bmp.Height
  if ($i -gt 0) {
    $changed = 0
    $regions = @{'L'=0;'R'=0;'T'=0;'B'=0}
    $step = 4
    for ($x = 0; $x -lt $w; $x += $step) {
      for ($y = 0; $y -lt $h; $y += $step) {
        $c1 = $prevBmp.GetPixel($x, $y); $c2 = $bmp.GetPixel($x, $y)
        $dr = [Math]::Abs($c1.R - $c2.R); $dg = [Math]::Abs($c1.G - $c2.G); $db = [Math]::Abs($c1.B - $c2.B)
        if (($dr + $dg + $db) -gt 40) {
          $changed++
          if ($x -lt $w / 2) { $regions['L']++ } else { $regions['R']++ }
          if ($y -lt $h / 4) { $regions['T']++ }
          elseif ($y -gt $h * 3 / 4) { $regions['B']++ }
        }
      }
    }
    $totalPix = [Math]::Max(1, ($w / $step) * ($h / $step))
    $pct = $changed / $totalPix * 100.0
    $reg = "{0}:{1}:{2}:{3}" -f $regions['L'], $regions['R'], $regions['T'], $regions['B']
    '{0},{1:N2},{2}' -f ($i - 1), $pct, $reg
  }
  if ($prevBmp) { $prevBmp.Dispose() }
  $prevBmp = $bmp
  $i++
}
$prevBmp.Dispose()