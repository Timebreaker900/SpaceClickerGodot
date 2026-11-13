# Space Clicker Godot

Incremental-/Clicker-Spiel im Weltraum. Neuaufbau des alten Unity-Projekts (`D:\repos\SpaceClicker`, Stand 2021, nur noch Referenz) in Godot 4.

Ziel: Handy (Android, iOS) im Hochformat mit Monetarisierung, später Steam als Kaufversion.

## Wo was steht

- `docs/ideen.md` – Eingangskorb des Nutzers, unsortiert. Nur lesen, wenn der Nutzer es sagt („schau in die Ideen“).
- `docs/design.md` – der gültige Spielentwurf. Einzige Quelle für das, was gebaut wird.
- `docs/ideen-archiv.md` – verarbeitete Ideen. Nicht lesen, außer es wird danach gefragt.
- `docs/skizzen/` – Bilder zu Seiten und Layouts.
- `data/*.json` – alle Spielzahlen (Gebäude, Kosten, Upgrades, Rezepte). Das Spiel liest diese Dateien direkt. Zahlen stehen nie zusätzlich in `design.md` oder im Code.

## Ideen verarbeiten

1. Jeden Block aus `ideen.md` in `design.md` einsortieren.
2. Bei Widersprüchen zum bestehenden Entwurf oder Blöcken mit `?` nachfragen bzw. unter „Offene Fragen“ eintragen, nicht raten.
3. Verarbeitete Blöcke mit Datum nach `ideen-archiv.md` verschieben. Die Anleitung oben in `ideen.md` bleibt stehen.
4. Blöcke mit `später` unter „Später“ in `design.md` eintragen und nicht bauen.

## Arbeitsweise

- Gebaut wird nur, was in `design.md` steht.
- Datengetrieben: ein generisches Skript pro Art (Gebäude, Upgrade, Rezept), Inhalte kommen aus `data/`. Kein Skript pro Gebäude.
- Texte: Deutsch steht im Code (in `tr("…")`) und in `data/*.json`. Jeder neue sichtbare Text braucht einen Eintrag in `data/lang_en.json`, sonst bleibt er im Englischen deutsch. Der Test prüft das für alle Namen aus den Datendateien.
- GDScript, kein C#.
- Ein System pro Schritt, ein Commit pro System, dazu eine kurze Erklärung, was gebaut wurde und warum – der Nutzer will mitlernen.
- Nach jeder Änderung am Spiel das Debug-Fenster neu starten: `pwsh tools/restart_game.ps1`. Das Skript schließt das Fenster normal, damit der Spielstand gespeichert wird – der Nutzer spielt nebenbei. Nie den Prozess abschießen und nie `user://save.json` anfassen; Tests laufen mit eigener Speicherdatei.
- Aussehen der Oberfläche steht in `tools/build_theme.gd`, das `ui/theme.tres` erzeugt. Nicht `theme.tres` von Hand ändern.
- Vor dem Commit: `godot_console --headless --path . res://tests/smoke.tscn --quit-after 3000` muss „ALLE TESTS OK“ melden. Tests mit Fenster ebenfalls mit `--quit-after`, sonst bleibt bei einem Skriptfehler ein Fenster hängen.
- Nach Änderungen an Preisen, Erträgen oder Freischaltungen die Balancing-Simulation laufen lassen und Auffälligkeiten nennen: `godot_console --headless --path . res://tests/sim.tscn -- --minutes=180 --clicks=3` (aktiver Spieler) bzw. `--minutes=360 --clicks=0.5` (nebenbei). Sie braucht rund 20 Sekunden.
- Android-APK bauen: `godot_console --headless --path . --export-debug "Android" build/SpaceClicker.apk`. Die Einstellungen stehen in `export_presets.cfg`; `build/` wird nicht eingecheckt. Neue Datendateien außerhalb von Szenen und Ressourcen (z. B. weitere `*.json`) müssen dort unter `include_filter` stehen, sonst fehlen sie in der APK. Aufs angeschlossene Handy: `adb install -r build/SpaceClicker.apk` (adb liegt im Android-SDK unter `platform-tools`). Die APK ist eine Debug-Version mit Test-Schlüssel, nicht für den Play Store.
- Icons sind handgeschriebene SVGs in `assets/icons` (Ressourcen, 128 px) und `assets/buildings` (Gebäude, 256 px), alle mit viewBox 128. Stil: flach, zwei bis drei Tonwerte pro Fläche (helle und dunkle Seite), kein Hintergrundkasten, Gebäude mit Bodenschatten, Türkis `#3fd0ff` als Akzent. Neue Icons im selben Stil zeichnen und vor dem Einbau als Bild prüfen.
- Upgrades haben kein eigenes Icon: Sie zeigen das Icon des Gebäudes bzw. der Ressource, die Zeile legt das Abzeichen `upgrade_badge.svg` darüber.
- Antworten auf Deutsch.
