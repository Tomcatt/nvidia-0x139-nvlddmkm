# Disable NVIDIA telemetry/auto-update bits reinstalled by the 617.14 package. Reversible; see telemetry-on notes in telemetry-off.log.
$kit = Split-Path -Parent $MyInvocation.MyCommand.Path
Start-Transcript -Path "$kit\telemetry-off.log" -Append

"=== scheduled tasks (auto driver check + app self-update)"
Get-ScheduledTask | ? { $_.TaskName -like 'NvDriverUpdateCheckDaily_*' -or $_.TaskName -like 'NVIDIA App SelfUpdate_*' } |
    % { Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath | ft TaskName,State -auto | Out-String }

"=== FrameView SDK service -> Disabled (was Manual)"
Set-Service FvSvc -StartupType Disabled
Get-Service FvSvc | ft Name,Status,StartType -auto | Out-String

"=== rename NvTelemetry DLLs to .disabled"
Get-ChildItem 'C:\Program Files\NVIDIA Corporation\NvTelemetry','C:\Program Files (x86)\NVIDIA Corporation\NvTelemetry' -Recurse -File -Filter *.dll |
    % { Rename-Item $_.FullName "$($_.Name).disabled" -PassThru | select -Expand FullName }

"=== registry opt-outs"
$cp = 'HKLM:\SOFTWARE\NVIDIA Corporation\NvControlPanel2\Client'
$fts = 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\FTS'
New-Item $cp -Force | Out-Null; New-Item $fts -Force | Out-Null
New-ItemProperty $cp -Name OptInOrOutPreference -PropertyType DWord -Value 0 -Force | Out-Null
foreach ($n in 'EnableRID44231','EnableRID64640','EnableRID66610') { New-ItemProperty $fts -Name $n -PropertyType DWord -Value 0 -Force | Out-Null }
Get-ItemProperty $cp | select OptInOrOutPreference | Out-String
Get-ItemProperty $fts | select EnableRID* | Out-String

"=== verify tasks"
Get-ScheduledTask | ? { $_.TaskName -match 'NvDriverUpdate|NVIDIA App SelfUpdate' } | ft TaskName,State -auto | Out-String
"DONE"
Stop-Transcript
