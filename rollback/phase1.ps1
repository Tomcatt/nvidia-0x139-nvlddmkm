# Phase 1 (elevated): backups, Windows Update driver block, logon task, then DDU + reboot.
$b = $PSScriptRoot
Start-Transcript -Path "$b\phase1.log" -Force | Out-Null

"=== current driver"
& nvidia-smi --query-gpu=driver_version,name --format=csv,noheader

"=== restore point (allow a second one today)"
$sr = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
Set-ItemProperty $sr SystemRestorePointCreationFrequency 0 -Type DWord
Checkpoint-Computer -Description 'Before NVIDIA rollback 617.42 to 617.14' -RestorePointType MODIFY_SETTINGS
Remove-ItemProperty $sr SystemRestorePointCreationFrequency
Get-ComputerRestorePoint | Select-Object -Last 2 | Format-Table -AutoSize

"=== backups"
robocopy 'C:\ProgramData\NVIDIA Corporation\Drs' "$b\Drs" /E /R:0 /W:0 /NP /NJH
reg export 'HKLM\SOFTWARE\NVIDIA Corporation' "$b\hklm-nvidia.reg" /y
reg export 'HKCU\Software\NVIDIA Corporation' "$b\hkcu-nvidia.reg" /y
$ds = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'
"SearchOrderConfig before: $((Get-ItemProperty $ds).SearchOrderConfig)" | Tee-Object "$b\searchorder-before.txt"

"=== block Windows Update driver installs"
Set-ItemProperty $ds SearchOrderConfig 0 -Type DWord

"=== logon task for phase 2"
$pwsh = (Get-Command pwsh).Source
$act  = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$b\phase2.ps1`""
$trg  = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$prn  = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'NvRollback-617.14' -Action $act -Trigger $trg -Principal $prn -Force | Select-Object TaskName, State

Read-Host "`nBackups done. Press Enter to run DDU - the PC will REBOOT"
"=== DDU"
Stop-Transcript | Out-Null
& "$b\DDU\Display Driver Uninstaller.exe" -Silent -CleanNvidia -PreventWinUpdate -NoSafeModeMsg -Restart

