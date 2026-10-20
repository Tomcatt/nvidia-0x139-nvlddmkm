# Phase 2 (runs once at logon after DDU): silent clean install of 617.14.
$b = $PSScriptRoot
Start-Transcript -Path "$b\phase2.log" -Force | Out-Null
"Waiting 30 s for the desktop to settle..."
Start-Sleep 30

"=== installing 617.14 (screen may flicker)"
$p = Start-Process "$b\installers\617.14\setup.exe" -ArgumentList '-s', '-clean', '-noreboot' -Wait -PassThru
"setup exit code: $($p.ExitCode)"

"=== result"
& nvidia-smi --query-gpu=driver_version,name --format=csv,noheader
Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, Status | Format-Table -AutoSize

Unregister-ScheduledTask -TaskName 'NvRollback-617.14' -Confirm:$false
"DONE"
Stop-Transcript | Out-Null
Read-Host "`nNVIDIA 617.14 install finished. Reboot once more. Press Enter to close"
