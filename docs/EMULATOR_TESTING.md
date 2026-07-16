# Android Emulator testing (Cursor)

Use a local Android Emulator instead of a physical phone to run **Attandance_App** from Cursor.

The emulator opens as a **separate window**. Cursor connects to it via Flutter/adb; it is not embedded inside the editor.

## Prerequisites (already set up on this PC)

| Item | Value |
|------|--------|
| Flutter | `C:\flutter` |
| Android SDK | `%LOCALAPPDATA%\Android\sdk` |
| AVD name | `Pixel_6_API_35` (Pixel 6, API 35, Google Play) |
| Start script | `scripts/start-android-emulator.ps1` |

## From Cursor (recommended)

1. **Start the emulator**  
   Command Palette (`Ctrl+Shift+P`) → **Tasks: Run Task** → **Start Android Emulator**  
   Wait until the terminal prints `Emulator emulator-5554 is ready.` (first boot can take a few minutes).

2. **Run the app**  
   Open **Run and Debug** → choose **Attandance_App (emulator)** → Start (`F5`).  
   Or in a terminal:

   ```powershell
   cd Attandance_App
   C:\flutter\bin\flutter.bat run -d emulator-5554
   ```

3. Hot reload with `r` in the Flutter terminal (or the Flutter toolbar if the Dart extension is active).

## From PowerShell

```powershell
cd Attandance_App
powershell -ExecutionPolicy Bypass -File .\scripts\start-android-emulator.ps1
C:\flutter\bin\flutter.bat devices
C:\flutter\bin\flutter.bat run -d emulator-5554
```

## Networking notes

- **Production / cloud backends** (default debug/release builds): no special URLs — the emulator uses the same `https://hrm.peoplesitsolution.com` / ZKTeco cloud hosts as a phone.
- **Local Docker backends** from the emulator: use the special host `10.0.2.2` (maps to the host PC’s `127.0.0.1`), e.g. `http://10.0.2.2:8000` / `:8095` / `:8020`. See also `SERVER_COMMANDS.md`.
- The start script always launches with `-dns-server 8.8.8.8,1.1.1.1` and turns **Private DNS off** on the AVD (Private DNS to `one.one.one.one` was breaking login timeouts).
- If Google Fonts fail to download after a cold start, wait a few seconds and retry; with working internet they load normally.

## Login timeout / no internet on emulator

**Symptom:** Sign In fails with `Request timed out` to `https://hrm.peoplesitsolution.com/.../login`, while the **same build works on a real phone**.

**Cause:** Emulator network/DNS (not app auth). Common on fresh AVDs when Private DNS or a bad snapshot leaves Wi‑Fi “connected” but with no real egress.

**Fix:**

```powershell
cd Attandance_App
powershell -ExecutionPolicy Bypass -File .\scripts\start-android-emulator.ps1 -ColdBoot
```

Then verify:

```powershell
adb shell ping -c 2 hrm.peoplesitsolution.com
adb shell ping -c 2 8.8.8.8
```

If those succeed, Sign In again (production URL — no tunnel `dart-define` needed for this case).

`--dart-define=USE_LOCAL_TUNNEL_BACKENDS=true` is only for local Cloudflare tunnel backends; it does not fix a broken emulator internet path to production.

## Face check-in on emulator

Face registration / check-in use the emulator camera (webcam or Android Emulator virtual scene). Behavior can differ from a real phone; prefer a physical device for final face-flow QA.

## Useful commands

```powershell
# List AVDs
%LOCALAPPDATA%\Android\sdk\emulator\emulator.exe -list-avds

# adb
%LOCALAPPDATA%\Android\sdk\platform-tools\adb.exe devices

# Cold boot with DNS fix (use if login times out / no internet)
powershell -ExecutionPolicy Bypass -File .\scripts\start-android-emulator.ps1 -ColdBoot
```
