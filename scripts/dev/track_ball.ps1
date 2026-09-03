param([string]$SeqPath = "artifacts\\seq\\lunar_seq")
## Track the active red ball + power bar across a screenshot sequence.
## For each frame emits: redPix, redCx, redCy, powerPix, blackPix.
## Red ball = rgb where r >> g and r >> b (balls are vivid red 0.84,0.14,0.09;
## the black balls are near-black so they won't trip the red detector).
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $SeqPath)) { $SeqPath = "artifacts\\seq" }
$files = Get-ChildItem -Path $SeqPath -Filter '*.png' | Sort-Object Name
if ($files.Count -lt 2) { Write-Output 'NO_FRAMES'; exit }

"idx,redPix,cxC,cyC,powerPix,blackPix"
$i = 0
foreach ($f in $files) {
  $bmp = [System.Drawing.Bitmap]::FromFile($f.FullName)
  $w = $bmp.Width; $h = $bmp.Height
  $redPix = 0; $powPix = 0; $blkPix = 0
  $sx = 0.0; $sy = 0.0
  $step = 3
  for ($x = 0; $x -lt $w; $x += $step) {
    for ($y = 0; $y -lt $h; $y += $step) {
      $c = $bmp.GetPixel($x, $y)
      $r = $c.R; $g = $c.G; $b = $c.B
      # vivid red ball
      if ($r -gt 120 -and $g -lt 90 -and $b -lt 90) {
        $redPix++
        $sx += $x; $sy += $y
      }
      # black ball (very dark, but not the deep void background): r,g,b < 40
      # limited to top region (y in first 60%) to stay away from dark backdrop
      if ($y -lt $h * 0.62 -and $r -lt 45 -and $g -lt 45 -and $b -lt 45) {
        $blkPix++
      }
      # power bar fill (warm orange, bottom area): bottom-center column band
      if ($y -gt $h * 0.86 -and [Math]::Abs($x - $w / 2) -lt $w * 0.22 -and
          $r -gt 140 -and $g -gt 60 -and $g -lt 160 -and $b -lt 80) {
        $powPix++
      }
    }
  }
  $cx = if ($redPix -gt 0) { [int]($sx / $redPix) } else { -1 }
  $cy = if ($redPix -gt 0) { [int]($sy / $redPix) } else { -1 }
  '{0},{1},{2},{3},{4},{5}' -f $i, $redPix, $cx, $cy, $powPix, $blkPix
  $bmp.Dispose()
  $i++
}