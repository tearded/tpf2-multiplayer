# Fork-Übersicht: Stand, Abweichungen zum Original, Vorgehen

Lebendes Dokument. Wird bei jedem Upstream-Merge, jeder Fork-Auslieferung und
jeder Upstream-PR aktualisiert (Abschnitt „Pflege" unten). Das Sitzungsprotokoll
`docs/SESSION_LOG.md` bleibt die chronologische Übergabe; dieses Dokument ist die
Landkarte darüber.

## Stand

| | |
|---|---|
| Stand vom | 2026-09-22 |
| Original (Upstream) | `silver2127/tpf2-multiplayer`, `main` 9cf0219 (vollstaendig in den Fork gemergt; nur Quellcode, kein Release) |
| Fork | `tearded/tpf2-multiplayer`, Arbeitsbranch `codex/vehicle-name-sync` |
| Letzter Upstream-Merge | Upstream main 9cf0219, 2026-09-22 (vorher 325b879 / 0.6.1.9) |
| Letzte Fork-Auslieferung | 0.6.2.10 aus b184c35 (Merge-Stand, reversed-Flag, Geschwindigkeit „letzter Klick"), Kanal **Mein Fork** im Launcher, 2026-09-20 |
| Nächste Auslieferung | nicht beauftragt; Quellupdate vom 2026-09-22 bleibt unveroeffentlicht als Spielpaket |
| Verbleibende Spiel-Extras | Navigation, Geschwindigkeitsmodus letzter Klick und Stationsstrassen-Anschlusskorrektur. Quellstand auf Upstream main 9cf0219; Launcherrelease weiterhin 0.6.2.10. |

## Versionierung und Kanäle

- Upstream nummeriert `0.6.1.x`. Der Fork nummeriert `0.6.2.x` und liegt damit
  immer oberhalb, damit der Launcher-Feed eindeutig bleibt. Beim nächsten
  Upstream-Sprung auf `0.6.2.x` oder höher muss der Fork auf `0.6.3.x` ausweichen.
- `installer/VERSION` und `LOBBY_VERSION` in `netpunch/lobby.py` müssen gleich
  sein, sonst bricht der Tag-Lauf vor allen Tests ab (passiert bei 0.6.2.6).
- Auslieferung nur über Tag `vX.Y.Z` auf dem Fork; Ablauf in `docs/FORK_BUILDS.md`.
  Der Launcher folgt dem Latest-Release des Forks, nicht dem neuesten Commit.
- Ein Release-Stand muss vollständig committet sein. Der Linienhalte-Fix lag
  vom 19.09. bis 20.09. uncommittet und war deshalb in 0.6.2.8 nicht enthalten.

## Beschlossener Funktionsumfang (2026-09-20)

Der Fork ist Upstream plus genau diese Liste. Alles andere wird nicht mitgeführt;
wer etwas Neues braucht, trägt es hier ein.

| Nr. | Feature | Entscheidung |
|---|---|---|
| A | Auslieferung: Workflow, Release-Skripte, Testgruppen, Fork-Versionierung | drin, Pflicht für den Launcher-Kanal |
| 5 | Kartennavigation (Ping, Gehe zu, Fenster-Hotkey) | drin |
| 6 | Spielstandauswahl im Host-Lobbyfenster | Upstream seit Merge von PR #9 (8f65d33, 2026-09-21) |
| 7 | Resync | vollständig Upstream (PR #4), kein Fork-Rest mehr |
| 8 | Bestätigungstöne | Upstream, Paket #6 ueber dev uebernommen |
| 9–14 | Fences, Depotkauf, Straßeneigentum, Linienhalt-Wahl, Parameter-Zeilenumbrüche, recycelte IDs | Upstream, Paket #6 ueber dev uebernommen |
| 15 | Fahrzeugname reist mit (VNAME) | Upstream, 68f6dc4 (2026-09-22) |
| 16 | Fahrzeug-Stopp repliziert (VSTOP) | Upstream, c0dde37 (2026-09-22) |
| 17 | Stationsstraßen-Anschluss nativ | drin |
| 18 | Linienklick-Basis (`lineBaseFor`) | **raus**, Revert 6dd70a6; Upstream 0.6.1.9 löst die Ursache. Zurückholen nur, wenn im Spiel weiter Halte doppelt erscheinen |
| 19 | AutoSig2-Kompatibilität | Upstream, f898165 + 9cf0219: Platzieren, Ersetzen/Entfernen vorwaerts/rueckwaerts. Fork-Quellstand jetzt komplett; ausgeliefertes 0.6.2.10 hat nur Platzieren. |
| 20 | luacheck überspringt Langstrings | drin, sonst fällt die CI über Upstreams Workshop-Datei |
| 21 | Natives Vorschau-Rendering | entfällt, Upstream baut die Vorschau selbst; kein Fork-Code mehr |
| 22 | Umgedrehte Fahrzeugteile (reversed-Flag) reisen mit dem Kauf (VBUY/VREPL) | drin, **Upstream hat es** (38941b4 = Port von a7047da, Release 0.6.1.12, 2026-09-20); im Quellstand jetzt unveraendert von Upstream |
| 23 | Spielgeschwindigkeit: letzter Klick eines beliebigen Spielers gewinnt, nur 1x/2x/4x (`K.SPEED_MODE = "last"`); Upstreams Vote-Mittel bleibt als `"vote"` im Code | drin, fork-eigen (bewusste Abweichung, Benutzerwunsch 2026-09-20) |

## Was der Fork gegenüber dem Original enthält

Status-Spalte: **fork** = bleibt Fork-eigen, **PR offen** = liegt Upstream zur
Prüfung vor, **PR gemergt** = Upstream hat es übernommen (im Fork bleibt ggf. ein
Rest), **Kandidat** = sollte als PR nach Upstream, sobald spielgetestet.

### Spielmechanik (Lua-Mod `mod/mp_lockstep_1`)

| Bereich | Dateien | Test | Status |
|---|---|---|---|
| Fahrzeugname reist mit dem Kauf (`VNAME`), gegen Zugnamen-Desync bei verschiedenen Spielsprachen | `vehicles.lua`, `inject.lua` | `vehicle_name_sync_test` | Upstream (68f6dc4) |
| Fahrzeug-Stopp-Schalter repliziert (`VSTOP`, nativer Factory-Eintrag id 18) | `vehicles.lua`, `inject.lua`, `lockstep.lua`, `slice_hook.cpp` | `foreign_edit_guard_test`, `vehicle_line_choice_test` | Upstream (c0dde37) |
| Umgedrehte Fahrzeugteile: reversed-Flag (VehiclePart+0x04) im VBUY/VREPL-Wire, fünftes Feld der Teilespezifikation | `slice/vehicles.inl`, `inject.lua`, `vehicles.lua` | `vehicle_reversed_test` | Upstream (38941b4, 0.6.1.12; dort in `native/src/slice/vehicles.inl`) |
| Automatische Linienhalt-Wahl beim Kauf (`-1` probiert Halte der Reihe nach) | `vehicles.lua` | `vehicle_line_choice_test` | Upstream (Paket #6 ueber dev) |
| Depotkauf bei versetzter Mod-Geometrie (UEP-Terminal) | `vehicles.lua` | `depot_buy_test` | Upstream (Paket #6 ueber dev) |
| Konstruktionsparameter mit Zeilenumbrüchen | `cons.lua`, `net.lua` | `params_line_test` | Upstream (Paket #6 ueber dev) |
| Recycelte Entity-IDs: Bauwerk gilt nur mit passender CONSTRUCTION-Komponente als vorhanden | `cons.lua` | `con_recycled_id_test` | Upstream (Paket #6 ueber dev) |
| Straßeneigentum über logische Firmennummern (`ROADP own`) | `roads.lua`, `geom.lua`, `stops.lua` | `edge_owner_decode_test`, `crossing_replay_test` | Upstream (Paket #6 ueber dev) |
| Snowball Fences / Hecken als `FENCE`-Befehl, ganze Zäune, Abriss | `fences_compat.lua`, `mod.lua`, `previews.lua` | `fences_compat_test` | Upstream (Paket #6 ueber dev) |
| Bestätigungstöne für abgefangene Fahrzeugaktionen | `action_sounds.lua`, `lockstep.lua` | `action_sounds_test` | Upstream (Paket #6 ueber dev) |
| AutoSig2 Platzieren und nun auch Ersetzen/Entfernen in beiden Richtungen | `autosig_compat.lua`, `mod.lua`, `stops.lua` | `autosig_compat_test`, `autosig_modes_test`, eigener Zweiinstanz-Test | Upstream (f898165, 9cf0219); neue Modi im Fork-Quellstand, noch nicht ausgeliefert |
| Spielgeschwindigkeit „letzter Klick gewinnt", Stufen 1/2/4 statt Vote-Mittel mit Bruchwerten | `pacing.lua`, `lockstep.lua` (Schalter `K.SPEED_MODE`, Geschwindigkeitszeile) | `speed_vote_test` | fork |
| Kartennavigation: Ping Ctrl+Shift+P, „Gehe zu", Fenster Ctrl+Shift+D | `navigation.lua`, `menu_hook.cpp` | `navigation_test` | fork |
| Host-geführter Resync mit Bereitschaftsprüfung | `resync.lua`, `menu_hook.cpp` | `resync_test`, Recovery-Matrix | PR gemergt (#4), vollständig Upstream |
| Gemeinsame Bauvorschauen Straße/Schiene | `previews.lua`, `tpf2_previews.dll` | `preview_test`, `preview_perf_test` | PR gemergt (#3), vollstaendig Upstream, inklusive Fences-Vorschau aus Paket #6 |
| Bahnübergänge, Abriss, Straßen unter Brücken | `roads.lua`, `cons.lua` | `crossing_replay_test`, `bridge_companion_test` | PR gemergt (#2) |

### Nativ (`native/src`)

| Bereich | Dateien | Status |
|---|---|---|
| Stationsstraßen-Anschluss: Vorlagensegmente über `segmentsBefore`, loses Vorlagenende auf den versandten Splitknoten, Frozen-Index umschreiben | `slice/station_weld.inl` (MergeTemplateStreet), `station_weld.h` | Kandidat, Spieltest offen (0.6.2.8) |
| `VSTOP` Factory-Hook | `slice_hook.cpp`, `slice/capture.inl`, `slice/add_hook.inl` | Upstream (c0dde37) |
| Spielstandauswahl im Host-Lobbyfenster (SELECT SAVE, NEXT/PREVIOUS, REFRESH) | `menu_hook.cpp`, `tools/lobby_save_picker_test.cpp` | Upstream (PR #9 gemergt, 8f65d33) |
| Navigation im Multiplayer-Fenster (Ping-Liste, Gehe-zu-Knöpfe) | `menu_hook.cpp` | fork |

### Build, Test und Auslieferung (bleibt Fork-eigen)

| Bereich | Dateien |
|---|---|
| GitHub-Actions-Workflow: MSI je Push, Release nur per Tag, Draft-Prüfung, Hash-Prüfung | `.github/workflows/windows-build.yml`, `docs/FORK_BUILDS.md` |
| Release-Skripte | `tools/build_release.ps1`, `tools/publish_fork_release.ps1`, `tools/validate_release_package.ps1`, `installer/build_msi.ps1` |
| Parallele Testgruppen (native, lobby, logic, recovery) | `tools/run_release_tests.py`, `tools/run_recovery_matrix.py`, `tools/release_runner_test.py` |
| Lua-Prüfer überspringt Langstrings | `tools/luacheck.py` (winziger PR-Kandidat) |
| Releasehinweise je Fork-Version | `docs/releases/*.md` |

### Dokumentation

`docs/REPLICATION.md` (Fork-Zeilen für ROADP own, AutoSig2, FENCE, DEMOLISH,
VSTOP, VNAME, Töne, Depotkauf, Linienhalt-Wahl), `docs/PLAYING.md` (Navigation,
Spielstandauswahl), `docs/DEVELOPMENT.md` (Testgruppen), `docs/re/` (Indexregel
für Vorlagensegmente).

## Upstream-PRs

| PR | Inhalt | Stand |
|---|---|---|
| [#2](https://github.com/silver2127/tpf2-multiplayer/pull/2) | Bahnübergänge, Abriss, Straßen unter Brücken | gemergt |
| [#3](https://github.com/silver2127/tpf2-multiplayer/pull/3) | Gemeinsame Bauvorschauen | gemergt |
| [#4](https://github.com/silver2127/tpf2-multiplayer/pull/4) | Host-geführter Resync mit Bereitschaftsprüfung | gemergt |
| [#6](https://github.com/silver2127/tpf2-multiplayer/pull/6) | Parameter, Depotkauf, Straßeneigentum, Töne, Linienhalte, Fences, recycelte IDs (6 Commits auf Upstream 7c15ea8) | geschlossen; ueber dev in main enthalten (a06775f), API merged=false ist hier kein Inhaltsnachweis |

Save-Picker: [#9](https://github.com/silver2127/tpf2-multiplayer/pull/9), am 2026-09-21 um 20:45 UTC gemergt (8f65d33); Branch `codex/pr-lobby-save-picker`, Commit `309eb57` auf Upstream `664110f`. Drei Dateien (Menue, Integrationstest, Spielanleitung), nativer Menuebuild und Offline-Integrationstest bestanden; kein neuer gemeinsamer Spieltest. Worktree `.local-test/pr-packages/save-picker`. Spielstandauswahl ist damit zur Upstream-Uebernahme eingereicht und nicht mehr bewusst fork-exklusiv.

PR-Branches liegen als Worktrees unter `.local-test/pr-packages/` und basieren
direkt auf Upstream-`main`, nicht auf dem Fork-Branch. Fork-Release, Version,
Launcher und CI gehören nie in eine Upstream-PR.

## Vorgehen ab jetzt

1. **Upstream regelmäßig einziehen, vor jeder Auslieferung.** Merge mit `--no-ff`
   in den Arbeitsbranch, Konflikte lösen, dann Build `native\build.bat all` mit
   `TPF2_BUILD_NO_DEPLOY=1`, Logikgruppe und luacheck, Whitespace-Prüfung mit
   `-c core.whitespace=cr-at-eol`. Ergebnis in `docs/SESSION_LOG.md` und hier.
2. **Bekannte Konfliktstellen** beim Merge: `installer/VERSION` und `LOBBY_VERSION`
   (immer Fork-Version behalten), `lockstep.lua` (`K.STRICT_OPS` als Vereinigung,
   `guiUpdate` mit Fork-Ticks für Töne und Navigation), `slice_hook.cpp`
   (Factory-Tabelle, `DeferHandler`), `inject.lua` (Befehlsparser), `vehicles.lua`,
   `REPLICATION.md` (Tabelle). `netpunch/lobby.py` ist bei Upstream CRLF; der Fork
   ändert nur die Versionszeile und muss den Blob mit CRLF behalten (Commit 960bf65),
   sonst konfliktiert die ganze Datei.
3. **Fixes klein und einzeln nach Upstream.** Jeder Fork-Fix, der das Spiel betrifft,
   ist ein PR-Kandidat, sobald er im gemeinsamen Spiel bestätigt ist. PR-Branch
   auf Upstream-`main` aufsetzen, nur die Sachänderung plus Test, keine Versions-,
   Launcher- oder CI-Dateien. Verbleibende Kandidaten nach Spieltest:
   Stationsstraßen-Weld, luacheck.
4. **Fork-eigen bleibt:** Launcher-Kanal, CI/Release-Pipeline, Testgruppen,
   Navigation und der Geschwindigkeitsmodus letzter Klick. AutoSig2 und Fences sind
   bereits Upstream. Neue Features nur mit Eintrag im beschlossenen
   Funktionsumfang; Upstream-Verhalten hat im Zweifel Vorrang vor einer
   Fork-Variante desselben Fixes.
5. **Jede Fork-Änderung hat einen Offline-Test** in `tools/` und steht in der
   Logikgruppe von `tools/run_release_tests.py`. Upstream-Tests werden beim Merge
   dort ebenfalls eingetragen.
6. **Ein Release pro geprüftem Stand.** Version, `LOBBY_VERSION`, Releasehinweise
   mit bekannten Fehlern, Tag, Feed-Prüfung mit dem echten Launcher. Spieltests
   der Mitspieler getrennt von automatischen Tests festhalten.
7. **Branch-Hygiene.** Der Arbeitsbranch ist die Wahrheit; `main` des Forks wird nach
   bestätigten Releases per Merge nachgezogen. Alte `codex/backup-*`- und
   Release-Branches können nach Sicherung des Tags gelöscht werden.

## Offen (Stand 2026-09-20)

- Gemeinsamer Spieltest für 0.6.2.8-Inhalte: Busendstation/Tramschleife an Straße,
  Depot an Spielerstraße, großer Bahnhof mit Straßenanschluss (`tpf2_slice.log`:
  „[merge] done" / „[merge-weld] done"), Zug stoppen (`VSTOP`), Zäune ziehen.
- Linienbearbeitung: im ausgelieferten 0.6.2.8 ist kein Linien-Fix enthalten.
  Der Branch trägt jetzt Upstreams Lösung unverändert (Halt = Stationsgruppe,
  Klicks auf Linien ohne Fahrzeuge sofort lokal, vorab erzeugte Ersatzlinie für
  „Neue Linie"). Im Spiel prüfen: Halte schnell hinzufügen, Bahnsteig umsetzen,
  „Neue Linie" öffnet sofort.
- Gleisbau-Fehlschläge von Mitspieler b (`critical=true` ohne Meldung, Tunnelhälften
  und Bahnübergang mit zwei Splits) ohne b-stdout nicht belegt.
- Peer-Drop während laufender Wiederherstellungsrunde und Hold-Abbruch bei
  gedrückter Taste (`native_io.cpp`), siehe SESSION_LOG 2026-09-19.
- Upstreams Dedicated-Server-Modus ist im Fork ungetestet; der Fork-Launcher
  kennt ihn nicht.
- Quellupdate vom 2026-09-22 vor einer spaeteren Auslieferung gemeinsam im Spiel testen. Es gibt daraus noch kein neues Launcherpaket.
- `docs/PERFORMANCE_REVIEW.md` liegt untracked im Arbeitsverzeichnis (fremd, nicht
  eingecheckt).

## Pflege

Bei jedem Upstream-Merge: Tabelle „Stand", Konfliktstellen, Status-Spalten
(gemergte PRs aus der Kandidatenliste nehmen). Bei jeder Auslieferung: „Letzte
Fork-Auslieferung" und „Offen". Bei jeder PR: Tabelle „Upstream-PRs". Zeilen
für erledigte offene Punkte löschen, nicht durchstreichen.

## Separater Launcher-Release (2026-09-21)

Launcher1.0.2 in tearded/tpf2-launcher veroeffentlicht (Commit10c5ed8,
Tagworkflow35616602040 erfolgreich). Unterstuetzt die Netpunch-Runtime des
Originalpakets0.6.1.12 inklusive Sicherung und Rueckwechsel. Download/Hash und
Signatur selbst verifiziert; GitHub-Latest1.0.2 bestaetigt. Direkter Updatefeed-
Abruf aus Agentumgebung derzeit504; UI-Update noch nicht bestaetigt.
Multiplayer-Forkrelease0.6.2.10 unveraendert.

## Direkte Upstream-Uebernahme (2026-09-22)

Auf ausdruecklichen Benutzerauftrag mit bestaetigten GitHub-Schreibrechten vier
Commits auf offiziellem main: f898165 (AutoSig-Platzieren), 68f6dc4 (Kaufnamen),
c0dde37 (Stopp/Weiterfahrt), 9cf0219 (AutoSig-Ersetzen/Entfernen in beiden Richtungen).
19 Dateien, ohne Fork-Versionierung, Release-Pipeline oder private Testdateien.
Native All-Build und gezielte Regressionen bestanden. Eigener lokaler Zweiinstanz-
Engine-Test in separater kleiner Welt: sechs AutoSig-Faelle, identische Signal-
Snapshots, 49 angewendete Befehle pro Instanz, SYNC/desyncs=0, leere Queues.
Seed-Einstellungen per privatem Skript ausgefuehrt; keine Workshop-GUI-Validierung
und kein neuer benutzerbestaetigter gemeinsamer Spieltest fuer VNAME/VSTOP.
Spiele regulaer beendet, vorherige Installation 0.6.1.18 und beide Profile samt
Sandbox-Overlays hashgeprueft wiederhergestellt. Kein Tag/Release/Launcherupdate.
CI: https://github.com/silver2127/tpf2-multiplayer/actions/runs/35755400616 (erfolgreich: MSI, ZIP, Checksums, Artefakte; Release-Schritt wie erwartet uebersprungen).

## Upstream-Abgleich des Quellcodes (2026-09-22)

Upstream main 9cf0219 per Merge uebernommen. Navigation, letzter
Geschwindigkeitsklick und Stationsstrassen-Korrektur bleiben erhalten; letztere
liegt nach Upstreams Dateiaufteilung in native/src/slice/station_weld.inl.
Doppelten Bestaetigungston-GUI-Tick aus dem automatischen Merge entfernt.
Versionsnummer bleibt 0.6.2.10, kein Tag und keine neue Auslieferung beauftragt.

Fork-Buildpfad auf die gebuendelte Netpunch-Runtime angepasst. Entfernte
Upstream-Telemetrie-/Updater-Tests entfallen; neue portable Upstream-Regressionen
sind in der Logikgruppe. Upstreams eigener MSI-Workflow laeuft nur im
Originalrepository, damit Fork-Tags weiter ausschliesslich die gepruefte
Draft-Release-Pipeline verwenden. AutoSig-Tests gegen installierte Workshop-Dateien
werden separat lokal ausgefuehrt; diese Dateien sind auf CI nicht vorhanden.

Validierung: nativer All-Build ohne Deployment, alle 58 Testprogramme der vier
Regressionsgruppen (inklusive Luacheck und Recovery fuer 2/3/5/8 Spieler)
sowie beide AutoSig-Workshop-Testreihen bestanden. Kein neuer Spieltest.
