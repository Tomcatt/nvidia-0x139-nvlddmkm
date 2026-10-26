# NVIDIA nvlddmkm 0x139 (CORRUPT_LIST_ENTRY) BSODs on RTX 5090: 617.42 → 617.14 rollback

Field notes from one machine. Across three NVIDIA driver branches, it hit the same `0x139` bugcheck in `nvlddmkm`. Two driver versions in between ran clean. This repo has the evidence, the rollback that fixed it (DDU plus a silent clean install), and a script that turns off the telemetry and auto-update parts that the full driver package installs again.

> One system, not a lab study. Some of the early crashes happened while I was still tuning RAM (see caveats). The 617.42 crashes did not.

## System

| | |
|---|---|
| GPU | RTX 5090 |
| CPU | Ryzen 9 9950X3D |
| Board | MSI MEG X870E GODLIKE |
| RAM | 96 GB DDR5-6400 CL28 (stable since 2026-09-08) |
| OS | Windows 11 Pro for Workstations, build 26200 |
| Workload | Elite Dangerous, flat and in VR (Valve Index / SteamVR) |

## The crash

Every NVIDIA-attributed dump has the same signature:

```
BUGCHECK_CODE:  139
Arg1: 0000000000000003, A LIST_ENTRY has been corrupted (i.e. double remove).
PROCESS_NAME:  System
FAILURE_BUCKET_ID:  0x139_3_CORRUPT_LIST_ENTRY_nvlddmkm!unknown_function

STACK_TEXT:
nt!KeBugCheckEx
nt!KiBugCheckDispatch+0x69
nt!KiFastFailDispatch+0xb2
nt!KiRaiseSecurityCheckFailure+0x368
nt!ExInterlockedRemoveHeadList+0x9e
nvlddmkm+0xd33a57          <- 617.42   (616.64: nvlddmkm+0xd31a57)
```

The caller in `nvlddmkm` sits at the same place in each version. It moves by exactly `0x2000` between 616.64 and 617.42, so this looks like the same function and a long-lived bug, not a one-off regression. The driver removes an entry from an interlocked list that has already been unlinked (a double remove), and the kernel's list-integrity check fast-fails.

## Timeline by driver version

Source: System log event 1001 (BugCheck). Windows keeps these records even after the minidump is gone. Install dates come from `setupapi.dev.log`.

| Driver | Installed | 0x139 crashes | Notes |
|---|---|---|---|
| 610.88 | 2026-07-29 | 08-13, 08-17, 08-19 | During DDR5 tuning, so RAM is a possible confounder |
| 616.56 | — | none (one `0x133` on 08-31, see below) | |
| 616.64 | 2026-09-04 | 09-07 | One day before RAM was declared stable |
| **616.92** | 2026-09-18 | **none** (09-18 → 09-27) | RAM stable |
| **617.14** | 2026-09-27 | **none** (09-27 → 10-07) | RAM stable |
| 617.42 | 2026-10-07 (auto-installed by the NVIDIA App) | **10-12 18:37, 10-12 19:44** | Both in Elite Dangerous, the second in VR. RAM stable |

617.42 was still the newest driver on 2026-10-20, so updating forward wasn't an option. **I rolled back to 617.14**, the longest clean run on a stable system.

### Not this bug

- **`0x133` DPC_WATCHDOG_VIOLATION, 08-31 (616.56).** The stuck DPC was `nt!ExpGetPoolTagInfoTarget`, i.e. something querying kernel pool tags (typical of hardware/system monitoring tools). This is probably not NVIDIA, but I haven't proven it.
- **Kernel-Power 41 with BugcheckCode 0.** These were hard resets (RAM testing, a USB watchdog card), not driver crashes.
- **`0x3B` in `vjoy.sys` (vJoy 2.1.9).** A separate NULL-pointer bug, fixed by upgrading vJoy. See [vjoy-2.2-upgrade](https://github.com/Tomcatt/vjoy-2.2-upgrade).

## How to check your own machine

```powershell
# Every bugcheck Windows recorded, even when the dump is gone
Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001} |
  ? { $_.ProviderName -eq 'Microsoft-Windows-WER-SystemErrorReporting' } |
  select TimeCreated, Message | fl

# Analyse a minidump (WinDbg: winget install Microsoft.WinDbg); needs an elevated shell
cdb -z C:\Windows\Minidump\<file>.dmp -c "!analyze -v; q"
```

Look for `0x139`, `Arg1 = 3`, and `nt!ExInterlockedRemoveHeadList` called from `nvlddmkm+0xd3xxxx`.

## The rollback (what I ran)

Scripts are in [`rollback/`](rollback). Put them in a folder with `DDU\` (Display Driver Uninstaller 18.1.5.3) and `installers\617.14\` (the official 617.14 package, already extracted). Verify both downloads before you run anything.

1. **`phase1.ps1`** (elevated) does the following:
   - creates a restore point;
   - backs up `ProgramData\NVIDIA Corporation\Drs` (driver profiles) and the NVIDIA registry keys;
   - sets `DriverSearching\SearchOrderConfig = 0` so Windows Update can't push a GPU driver over yours;
   - registers a one-shot logon task;
   - runs DDU with `-Silent -CleanNvidia -PreventWinUpdate -NoSafeModeMsg -Restart`.
2. **`phase2.ps1`** (runs from that task at the next logon) runs `setup.exe -s -clean -noreboot`, logs the result, and deletes the task.
3. Reboot once more.

Result: `nvidia-smi` reports 617.14 (32.0.16.1714), and setup exited with 0.

**After a DDU wipe, re-apply your per-game profile settings by hand** (I use NVIDIA Profile Inspector). Don't restore a `Drs` database saved under a newer driver into an older one.

## Telemetry and auto-update after a clean install

A full package install brings back the NVIDIA App's daily driver-update check. That check is what silently installed 617.42 in the first place. [`telemetry-off.ps1`](telemetry-off.ps1) (elevated, every step reversible) does this:

- disables the `NvDriverUpdateCheckDaily_*` and `NVIDIA App SelfUpdate_*` scheduled tasks;
- sets `FvSvc` (FrameView SDK) to Disabled;
- sets the telemetry opt-out values `NvControlPanel2\Client\OptInOrOutPreference = 0` and `Global\FTS\EnableRID44231/64640/66610 = 0`;
- restores any `NvTelemetry*.dll.disabled` files left by the first version of this script (see the warning below).

It deliberately leaves alone:
- `NvContainerLocalSystem`, which hosts the NVIDIA App backend (and the App's local MCP server);
- `NVDisplay.ContainerLocalSystem`, which the Control Panel needs;
- the per-user `NVIDIA Shader Compiler` task.

The NVIDIA App 11.0.9 telemetry plugin reports to `prod.otel.kaizen.nvidia.com` and `events.telemetry.data.nvidia.com`. On my network both were already blocked at DNS (AdGuard Home), and each logged over 2,000 refused attempts. Block those two hostnames at DNS; that's the part that actually stops the reports.

> **Don't rename the NvTelemetry DLLs.** The first version of this script renamed them to `*.disabled`, and that breaks the NVIDIA App. `NvContainerLocalSystem` loads a mandatory plugin, `NvLocalizedConfig`, which loads `NvTelemetryAPI64.dll` → `NvTelemetryBridge64.dll` → the `NvTelemetry64.dll` container plugin at runtime. If any of them is missing, the service crash-loops (System log 7031/7023, exit code 14109; `CxNative_LocalSystem.log` shows error 126 / `0x8007007E`) and the App hangs on its loading screen. If you ran the old version, run the current one again: it renames the files back. Then start `NvContainerLocalSystem` (or reboot).

## Caveats

- This is one machine and a small number of crashes. "No crashes on 616.92/617.14" covers about 19 days of the same use.
- The 610.88 crashes overlap with RAM overclock tuning. The 617.42 crashes do not: the RAM had passed long stress tests a month earlier and was unchanged.
- If you see this signature, update this README via an issue with your driver version and nvlddmkm offset; more data points help pin it down.

## License

MIT
