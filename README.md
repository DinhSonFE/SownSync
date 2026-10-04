# Sown Sync Core v0.2 — REAPER Adapter

V0.2 adds a real REAPER bridge. REAPER remains the timeline source; Sown Core receives transport, position, project name and project markers over localhost UDP.

## Architecture
REAPER -> `reaper_sown_bridge.dll` -> UDP 127.0.0.1:19101 -> `ReaperSyncSource` -> `SyncEngine` -> `CueEngine`.

The bridge uses REAPER's extension API. The Core does not link to REAPER and can later swap in CuePoints/LTC/MTC adapters through `ISyncSource`.

## Build on Windows x64
Open the folder in Visual Studio (CMake) or Developer PowerShell:

    cmake -S . -B build -A x64
    cmake --build build --config Release
    ctest --test-dir build -C Release --output-on-failure

Outputs:

    build/Release/SownCoreConsole.exe
    build/Release/reaper_sown_bridge.dll

## Install REAPER bridge
1. In REAPER choose `Options > Show REAPER resource path in explorer/finder`.
2. Open `UserPlugins`.
3. Copy `reaper_sown_bridge.dll` into `UserPlugins`.
4. Restart REAPER.
5. Run `SownCoreConsole.exe`.

The console should change from `WAITING FOR BRIDGE` to `LOCKED`.

## Marker convention
REAPER marker names are parsed as:

    LIGHT|Beam Fan
    STAGE|Singer Ready
    VIDEO|VT GO
    ALL|Blackout

Text before `|` becomes Department; text after it becomes cue name. A marker without `|` uses Department `ALL`. Regions are transported by the bridge but ignored as reminder cues in v0.2.

## V0.2 test checklist
- REAPER Play -> Sown `PLAYING`
- REAPER Pause -> Sown `PAUSED`
- REAPER Stop -> Sown `STOPPED`
- Seek forward/back -> Sown snaps to the new position
- Add/move/rename/delete marker -> marker list refreshes
- TimeCore chases REAPER -> Sown follows REAPER's reported play position
- Close REAPER -> Sown becomes `WAITING FOR BRIDGE` after ~750 ms
- Reopen REAPER -> reconnects automatically

## Important
The bridge sends only to localhost in v0.2. This is intentional: REAPER integration is isolated from LAN distribution. Multi-device LAN sync will be a later Core module.

## v0.2.1 Precision Sync
Protocol upgraded to v3. Replace BOTH SownCoreConsole.exe and reaper_sown_bridge.dll.
Adds same-machine QPC one-way bridge latency, rolling avg/min/max/P95, inter-arrival jitter, sequence-gap detection, seek/discontinuity detection, and sync-quality classification. Position remains interpolated from the latest REAPER anchor using steady_clock; true seeks hard-snap on the next state packet.


## v0.2.2 Clock Discipline + Sync Health Watchdog

Adds a predictive local clock disciplined by REAPER packets instead of simply replacing the position on every packet.

- Predicts timeline position between bridge packets using steady_clock.
- Estimates source/local drift in ppm and applies a bounded rate correction (±2000 ppm).
- Small errors are corrected smoothly; real seeks/discontinuities (>150 ms) hard-snap immediately.
- Watchdog states: LOCKED (<100 ms), HOLDOVER (<350 ms), DEGRADED (<750 ms), LOST (>=750 ms).
- HOLDOVER keeps prediction running through short packet stalls; LOST stops claiming lock.
- Console exposes packet rate/age, prediction error, drift, hard snaps and soft corrections.

### v0.2.2 live test
Run REAPER normally, then test Play/Pause/Stop and several large seeks. For watchdog testing, close REAPER while Sown is running and observe LOCKED -> HOLDOVER -> DEGRADED -> LOST. Restart REAPER and confirm automatic recovery to LOCKED.
