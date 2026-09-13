# Guided recovery after a desync

This fork includes the archived project's **guided** resync, adapted to the
current Lua modules. Saving and restarting remain manual. The archived native
save/load automation is not part of this port.

After a desync, **Gefuehrter Resync** opens once per loaded world. Either player
can press **Resync vorbereiten** to request a shared pause. **Resync...** in the
Multiplayer window reopens the instructions. Log-upload preferences are separate;
choosing **Never** for logs does not disable recovery.

1. Stop building. Wait until **every player's** recovery window says
   `PEERS PAUSED`. Missing, stale or incompatible peers prevent this status.
2. The host saves under a **new, unique name**, preserving earlier saves.
3. Everyone exits the game normally, then restarts. Returning only to the title
   menu is insufficient: restarting clears the old bridge and command buffers.
4. Reconnect in a fresh player-hosted lobby. The host uses **SAVE...** to select
   exactly the new save, then **START GAME** to transfer it.
5. Wait for successful transfer, then everyone loads the freshly transferred
   **mp_shared** and waits for all players and a fresh **SYNC** before building.
   If transfer fails, retry it; do not load an older mp_shared.

The host's world is authoritative. Changes present only on a client are lost;
the worlds are not merged. Do not use the relay's previously stored world as
the recovery source or invite additional players during recovery.

Closing either window hides it; it does not release the hold. There is no
timeout that resumes a diverged world. If a peer cannot acknowledge, pause that
game manually and coordinate the host-save/restart procedure with all players.

## What the hold guarantees

The Lua update exits before capture, replay, deferred company repairs and pacing.
Local scheduling and inbound game commands are suppressed while recovery
heartbeats continue. Requests repeat and identify both loaded-world tokens;
old local request files, wrong targets and unknown or stale senders are ignored.
The lobby's required player count cannot shrink during recovery. A pause is
acknowledged only after the engine reports speed zero.

This is **not an atomic world lock**. Native build tools remain usable, and
commands already dispatched to the engine can finish. Do not keep building.
`PEERS PAUSED` proves recent reported pauses, not command drain or world equality.
Restarting all games and loading one fresh host save performs the actual resync.

The first request preserves at most 256 KiB from each of four local diagnostic
files: dashboard, capture, events and inject. Copies use `resync_<world>_<file>`
in the multiplayer data folder. `INCOMPLETE` means a source was missing or a
read/write failed; the pause remains active. Recovery does not upload these
copies or change the existing log-upload preference.

All players need the same fork source/package. Older peers can ignore the new
heartbeat fields and requests, but cannot complete the guided pause handshake.
The MSI already includes all files under the mod directory, including resync.lua.

## Validation

`python tools/resync_test.py` runs the production Lua 5.2 modules with real
temporary files and simulated engine, GUI and peers. It covers lost/repeated
requests, world tokens, roster changes, stale acknowledgements, asynchronous
pause, command suppression, bounded diagnostics, file errors and GUI callbacks.
Run `tools/luacheck.py` after Lua edits; preview and delay-hold regressions also
exercise the shared network module.

A live multiplayer save/restart/retransfer test of this port remains outstanding.
Use a disposable test save, trigger recovery from host and client in separate
runs, and compare both worlds and the new SYNC after reloading. These source
changes alone do not install or publish a launcher update.
