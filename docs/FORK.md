# Fork-Übersicht: Stand, Abweichungen zum Original, Vorgehen

Lebendes Dokument. Wird bei jedem Upstream-Merge, jeder Fork-Auslieferung und
jeder Upstream-PR aktualisiert (Abschnitt „Pflege" unten). Das Sitzungsprotokoll
`docs/SESSION_LOG.md` bleibt die chronologische Übergabe; dieses Dokument ist die
Landkarte darüber.

## Stand

| | |
|---|---|
| Stand vom | 2026-09-20 |
| Original (Upstream) | `silver2127/tpf2-multiplayer`, `main` 5783d4d = Release 0.6.1.9 |
| Fork | `tearded/tpf2-multiplayer`, Arbeitsbranch `codex/vehicle-name-sync` |
| Letzter Upstream-Merge | 325b879 (Upstream 0.6.1.9, 2026-09-20), davor 0.6.1.1 |
| Letzte Fork-Auslieferung | 0.6.2.10 aus b184c35 (Merge-Stand, reversed-Flag, Geschwindigkeit „letzter Klick"), Kanal **Mein Fork** im Launcher, 2026-09-20 |
| Nächste Auslieferung | offen; erst gemeinsamer Spieltest von 0.6.2.10 |
| Umfang der Abweichung | 77 Dateien, rund 4500 Fork-Zeilen: 15 Lua-Dateien der Mod, 3 native Dateien, CI/Release-Werkzeuge, 20 Fork-Releasehinweise |

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
| 6 | Spielstandauswahl im Host-Lobbyfenster | drin |
| 7 | Resync | vollständig Upstream (PR #4), kein Fork-Rest mehr |
| 8 | Bestätigungstöne | drin, weil mit 12 in einem PR-#6-Commit verwachsen; bei Bedarf trennbar |
| 9–14 | Fences, Depotkauf, Straßeneigentum, Linienhalt-Wahl, Parameter-Zeilenumbrüche, recycelte IDs | drin, PR #6 offen |
| 15 | Fahrzeugname reist mit (VNAME) | drin |
| 16 | Fahrzeug-Stopp repliziert (VSTOP) | drin |
| 17 | Stationsstraßen-Anschluss nativ | drin |
| 18 | Linienklick-Basis (`lineBaseFor`) | **raus**, Revert 6dd70a6; Upstream 0.6.1.9 löst die Ursache. Zurückholen nur, wenn im Spiel weiter Halte doppelt erscheinen |
| 19 | AutoSig2-Kompatibilität | drin |
| 20 | luacheck überspringt Langstrings | drin, sonst fällt die CI über Upstreams Workshop-Datei |
| 21 | Natives Vorschau-Rendering | entfällt, Upstream baut die Vorschau selbst; kein Fork-Code mehr |
| 22 | Umgedrehte Fahrzeugteile (reversed-Flag) reisen mit dem Kauf (VBUY/VREPL) | drin, Kandidat für Upstream (dort derselbe Platzhalter) |
| 23 | Spielgeschwindigkeit: letzter Klick eines beliebigen Spielers gewinnt, nur 1x/2x/4x (`K.SPEED_MODE = "last"`); Upstreams Vote-Mittel bleibt als `"vote"` im Code | drin, fork-eigen (bewusste Abweichung, Benutzerwunsch 2026-09-20) |

## Was der Fork gegenüber dem Original enthält

Status-Spalte: **fork** = bleibt Fork-eigen, **PR offen** = liegt Upstream zur
Prüfung vor, **PR gemergt** = Upstream hat es übernommen (im Fork bleibt ggf. ein
Rest), **Kandidat** = sollte als PR nach Upstream, sobald spielgetestet.

### Spielmechanik (Lua-Mod `mod/mp_lockstep_1`)

| Bereich | Dateien | Test | Status |
|---|---|---|---|
| Fahrzeugname reist mit dem Kauf (`VNAME`), gegen Zugnamen-Desync bei verschiedenen Spielsprachen | `vehicles.lua`, `inject.lua` | `vehicle_name_sync_test` | Kandidat |
| Fahrzeug-Stopp-Schalter repliziert (`VSTOP`, nativer Factory-Eintrag id 18) | `vehicles.lua`, `inject.lua`, `lockstep.lua`, `slice_hook.cpp` | `foreign_edit_guard_test`, `vehicle_line_choice_test` | Kandidat |
| Umgedrehte Fahrzeugteile: reversed-Flag (VehiclePart+0x04) im VBUY/VREPL-Wire, fünftes Feld der Teilespezifikation | `slice_hook.cpp`, `inject.lua`, `vehicles.lua` | `vehicle_reversed_test` | Kandidat |
| Automatische Linienhalt-Wahl beim Kauf (`-1` probiert Halte der Reihe nach) | `vehicles.lua` | `vehicle_line_choice_test` | PR offen (#6) |
| Depotkauf bei versetzter Mod-Geometrie (UEP-Terminal) | `vehicles.lua` | `depot_buy_test` | PR offen (#6) |
| Konstruktionsparameter mit Zeilenumbrüchen | `cons.lua`, `net.lua` | `params_line_test` | PR offen (#6) |
| Recycelte Entity-IDs: Bauwerk gilt nur mit passender CONSTRUCTION-Komponente als vorhanden | `cons.lua` | `con_recycled_id_test` | PR offen (#6) |
| Straßeneigentum über logische Firmennummern (`ROADP own`) | `roads.lua`, `geom.lua`, `stops.lua` | `edge_owner_decode_test`, `crossing_replay_test` | PR offen (#6) |
| Snowball Fences / Hecken als `FENCE`-Befehl, ganze Zäune, Abriss | `fences_compat.lua`, `mod.lua`, `previews.lua` | `fences_compat_test` | PR offen (#6) |
| Bestätigungstöne für abgefangene Fahrzeugaktionen | `action_sounds.lua`, `lockstep.lua` | `action_sounds_test` | PR offen (#6) |
| AutoSig2 automatische Signale als strict Follow-up | `autosig_compat.lua`, `mod.lua` | `autosig_compat_test` | fork (Mod-Kompatibilität, Upstream-Interesse unklar) |
| Spielgeschwindigkeit „letzter Klick gewinnt", Stufen 1/2/4 statt Vote-Mittel mit Bruchwerten | `pacing.lua`, `lockstep.lua` (Schalter `K.SPEED_MODE`, Geschwindigkeitszeile) | `speed_vote_test` | fork |
| Kartennavigation: Ping Ctrl+Shift+P, „Gehe zu", Fenster Ctrl+Shift+D | `navigation.lua`, `menu_hook.cpp` | `navigation_test` | fork |
| Host-geführter Resync mit Bereitschaftsprüfung | `resync.lua`, `menu_hook.cpp` | `resync_test`, Recovery-Matrix | PR gemergt (#4), vollständig Upstream |
| Gemeinsame Bauvorschauen Straße/Schiene | `previews.lua`, `tpf2_previews.dll` | `preview_test`, `preview_perf_test` | PR gemergt (#3), vollständig Upstream; Fork ergänzt nur die Fences-Vorschau |
| Bahnübergänge, Abriss, Straßen unter Brücken | `roads.lua`, `cons.lua` | `crossing_replay_test`, `bridge_companion_test` | PR gemergt (#2) |

### Nativ (`native/src`)

| Bereich | Dateien | Status |
|---|---|---|
| Stationsstraßen-Anschluss: Vorlagensegmente über `segmentsBefore`, loses Vorlagenende auf den versandten Splitknoten, Frozen-Index umschreiben | `slice_hook.cpp` (MergeTemplateStreet), `station_weld.h` | Kandidat, Spieltest offen (0.6.2.8) |
| `VSTOP` Factory-Hook | `slice_hook.cpp` | Kandidat (siehe oben) |
| Spielstandauswahl im Host-Lobbyfenster (SELECT SAVE, NEXT/PREVIOUS, REFRESH) | `menu_hook.cpp`, `tools/lobby_save_picker_test.cpp` | fork |
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
| [#6](https://github.com/silver2127/tpf2-multiplayer/pull/6) | Parameter, Depotkauf, Straßeneigentum, Töne, Linienhalte, Fences, recycelte IDs (6 Commits auf Upstream 7c15ea8) | offen, Branch `codex/pr-replication-bugfixes` |

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
   Launcher- oder CI-Dateien. Reihenfolge nach Spieltest: VSTOP, VNAME,
   Stationsstraßen-Weld, luacheck.
4. **Fork-eigen bleibt:** Launcher-Kanal, CI/Release-Pipeline, Testgruppen,
   Navigation, Spielstandauswahl, Mod-Kompatibilität (AutoSig2, Fences bis
   Upstream sie nimmt). Neue Features nur mit Eintrag im beschlossenen
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
- PR #6 wartet auf den Maintainer.
- `docs/PERFORMANCE_REVIEW.md` liegt untracked im Arbeitsverzeichnis (fremd, nicht
  eingecheckt).

## Pflege

Bei jedem Upstream-Merge: Tabelle „Stand", Konfliktstellen, Status-Spalten
(gemergte PRs aus der Kandidatenliste nehmen). Bei jeder Auslieferung: „Letzte
Fork-Auslieferung" und „Offen". Bei jeder PR: Tabelle „Upstream-PRs". Zeilen
für erledigte offene Punkte löschen, nicht durchstreichen.
