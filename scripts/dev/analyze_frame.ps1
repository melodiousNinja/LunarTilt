param([string]$Path = "artifacts\\frame_capture.png")
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Path))
$w = $bmp.Width
$h = $bmp.Height
$bins = @{}
for ($x = 0; $x -lt $w; $x += 8) {
    for ($y = 0; $y -lt $h; $y += 8) {
        $c = $bmp.GetPixel($x, $y)
        $key = '{0},{1},{2}' -f ([int]($c.R / 32)), ([int]($c.G / 32)), ([int]($c.B / 32))
        if ($bins.ContainsKey($key)) { $bins[$key]++ } else { $bins[$key] = 1 }
    }
}
'--- frame analysis ---'
"size=${w}x${h}"
'--- top color families (r,g,b buckets) ---'
$bins.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 14 | ForEach-Object {
    $parts = $_.Key -split ','
    $r = [int]$parts[0] * 32
    $g = [int]$parts[1] * 32
    $b2 = [int]$parts[2] * 32
    '  rgb({0},{1},{2})  x{3}' -f $r, $g, $b2, $_.Value
}
$total = ($bins.Values | Measure-Object -Sum).Sum
$mid = 0
foreach ($kv in $bins.GetEnumerator()) {
    $p = $kv.Key -split ','
    $r = [int]$p[0] * 32
    $g = [int]$p[1] * 32
    $b2 = [int]$p[2] * 32
    if ([Math]::Abs($r - $g) -le 12 -and [Math]::Abs($g - $b2) -le 12) { $mid += $kv.Value }
}
'--- grey-ish fraction ---'
'{0:P1} of sampled pixels are near-grey' -f ($mid / $total)
$bmp.Dispose()
