param([int]$MaxSeconds = 45, [int]$IntervalMs = 200)
## Continuous on-device screenshot capture for live-behavior analysis.
## Runs detached on the PC, screencapping straight to /sdcard/lunar_seq on the
## phone so nothing is pulled until the user says "done".
$ErrorActionPreference = 'Stop'
$adb = 'tools\android\sdk\platform-tools\adb.exe'
$dir = '/sdcard/lunar_seq'

& $adb shell "mkdir -p $dir; rm -f $dir/*.png" | Out-Null
& $adb logcat -c | Out-Null

$count = 0
$max = [int]($MaxSeconds * 1000.0 / $IntervalMs)
$start = Get-Date
while ($count -lt $max) {
  $name = '{0:d3}' -f $count
  & $adb shell "screencap -p $dir/f$name.png" | Out-Null
  $count++
  Start-Sleep -Milliseconds $IntervalMs
}
$elapsed = (Get-Date) - $start
Write-Output ("capture_seq done frames={0} elapsed={1}s" -f $count, [int]$elapsed.TotalSeconds)