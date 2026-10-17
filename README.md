# Frame Dongle Fix

Makes the Wi-Fi dongle of the Steam Frame connect when it refuses to. One file: double-click it and the dongle links up with the Frame in about 15 seconds; or install the auto-fix from the same menu and let Windows do it for you.

Unofficial and not affiliated with Valve or Realtek. "Steam", "Steam Frame" and "Realtek" are trademarks of their owners.

## The problem

The Steam Frame talks to the PC through a small USB Wi-Fi dongle (on the author's PC: "Realtek 8832CU Wireless LAN WiFi 6 USB NIC For Valve", USB ID 28DE:2432). The Frame opens a hidden 6 GHz Wi-Fi network named `frame_XXXXXXXX`, and Steam makes the dongle join it.

Often, after the Frame is switched on (white blinking LED), the dongle just stays "Disconnected". The Windows event log (WLAN-AutoConfig, event 8002) then says *"The specific network is not available"* with `RSSI: 255`, which means the dongle does not even see the Frame's network, although the Frame is up and Steam keeps trying. The same happens right after unplugging and replugging the dongle while the Frame is already on.

What always fixes it: changing **any** value in Device Manager, Network adapters, the dongle, Advanced. The value does not matter: Windows restarts the adapter when you change one, and the restart is what helps. This tool does the same restart without touching any setting.

## Quick start

1. Download **`Frame-Dongle-Fix.cmd`**: open it here on GitHub and use the download button, or take it from the latest [Release](../../releases).
2. Double-click it and answer Yes at the administrator prompt. A menu opens:

   ```
   1  Fix now            restart the dongle adapter (when it will not connect)
   2  Install auto-fix   do it automatically from now on
   3  Uninstall auto-fix
   4  Quit
   ```

Windows may warn about a file from the internet. Either right-click the file, Properties, tick **Unblock** before the first run, or choose "More info" and "Run anyway".

It is a single plain-text file: open it in Notepad to read exactly what it does.

## Fix now

It finds the dongle, restarts its adapter and waits up to 45 seconds for the link to the Frame (an address `10.35.78.x`). If the dongle is already connected it does nothing. It tells you whether it worked and appends the details to `Frame-Dongle-Fix-report.txt` next to the file.

## Auto-fix

It copies the file to `C:\ProgramData\FrameDongleFix` and creates a scheduled task that starts with Windows, runs as System in the background and watches the dongle:

- If the dongle stays disconnected for 30 seconds while **Steam is running** (for at least 40 seconds), it restarts the adapter.
- If that does not help it tries again after 1, 2, 4, 8 minutes and so on, never waiting more than 10 minutes, and never more than 8 times per hour.
- After sleep or a long pause, and after the dongle is plugged in again, it starts counting from scratch.
- It does nothing when Steam is closed, when the dongle is connected, or when you disabled the adapter.
- Everything it does, including the values of the adapter's Advanced settings at every restart, is written to `C:\ProgramData\FrameDongleFix\log.txt`.

Menu entry 3 (or `Frame-Dongle-Fix.cmd uninstall`) removes the task and the copy; the log is left in place.

What it cannot do: it has no way to know the moment you switch the Frame on. While the Frame is off and Steam is open the dongle looks the same as a blind one, so it keeps trying with growing pauses; after you switch the Frame on it can take up to 10 minutes to try again. "Fix now" is immediate.

## Command line

`Frame-Dongle-Fix.cmd fix`, `install`, `uninstall` or `status` (from an administrator prompt). An optional second argument is the adapter pattern, see below.

## What it touches

- It restarts one network adapter (`Restart-NetAdapter`). It does not change any setting, driver or registry value, and it does not touch your normal Wi-Fi: only the adapter whose name matches `8832CU|Valve` is restarted.
- Auto-fix adds one scheduled task and one folder in `C:\ProgramData`, which only System and Administrators can change.
- The only thing it contacts is the Frame, with one ping after a successful fix. Nothing is sent anywhere.
- Because it starts PowerShell and can install a start-up task, security software may ask questions. The file is short and readable; please read it.

## Another dongle

The adapter is found by matching its description against a pattern, `8832CU|Valve` by default. To use another one, pass part of its name as the second argument: `Frame-Dongle-Fix.cmd fix "part of the adapter name"` or `Frame-Dongle-Fix.cmd install "part of the adapter name"`. The names are listed by `Get-NetAdapter | Format-List Name, InterfaceDescription`. The link check looks for the address range the Frame uses on the dongle link (`10.35.78.x`), so this only makes sense for an adapter that connects to the Frame.

## What is not known

- **Why** the dongle becomes blind. It stayed blind with different Advanced values and a plain restart fixed it, so the values are not the cause. Candidates (a USB hub, resume from sleep, Steam re-initialising the driver again and again, the 6 GHz handling of the driver) are not confirmed.
- Whether this helps on other PCs, other Windows versions or other dongles.

## Status

Experimental. Written after chasing the problem on one PC (Windows 11). On that PC a plain restart connected the dongle in about 15 seconds. The auto-fix is newer and has been tested with simulated adapters and simulated Windows commands (see Tests); real-world testing of it is thin, so please report what you see.

## Reporting

Open an issue and attach `C:\ProgramData\FrameDongleFix\log.txt` (adapter name and Advanced setting values, no personal data) and, if you ran Fix now, `Frame-Dongle-Fix-report.txt` (the hotspot name, the interface GUID and MAC addresses are replaced before anything is written). Useful details: Windows version, driver version (Device Manager, dongle, Driver tab), USB port or hub, how the Frame was switched on.

## How it works

The file starts with a few lines of batch that ask for administrator rights and then start PowerShell, which reads the rest of the same file (everything after the line `#PAYLOAD#`) and runs it. The auto-fix runs the installed copy in `watch` mode from a scheduled task (`Frame Dongle Fix`, at start-up, as System) and looks at the adapter every 4 seconds.

## Tests

`pwsh tests/run-tests.ps1` (also works with Windows PowerShell 5.1). The tests load the PowerShell part of the file, replace the Windows cmdlets with simulated ones and a simulated clock, and cover the watcher's decisions (waiting, growing pauses, hourly limit, sleep, Steam closed), the installer and uninstaller, the report masking, the menu and Fix now. They run on Linux and Windows in GitHub Actions, where the launcher itself is also started.

## License

[MIT](LICENSE)
