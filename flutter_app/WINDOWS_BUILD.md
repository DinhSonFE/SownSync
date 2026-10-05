# SOWN Sync Windows build

V0.4.1 integrates the Flutter desktop UI with the native C++20 core through `sown_core_api.dll`.

## One-command debug build

From the repository root:

```powershell
.\scripts\build_windows.ps1
```

or double-click/run:

```text
scripts\build_windows_debug.bat
```

The script configures and builds the native core, builds Flutter for Windows, and copies `sown_core_api.dll` next to `sown_sync.exe`.

Output:

```text
flutter_app\build\windows\x64\runner\Debug\
  sown_sync.exe
  sown_core_api.dll
```

For release:

```powershell
.\scripts\build_windows.ps1 -Config Release
```

Keep the REAPER SOWN bridge installed as before. The Flutter app owns the native core lifecycle: it calls `sown_init()` when the UI starts and `sown_shutdown()` when the UI closes.
