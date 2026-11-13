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
- GDScript, kein C#.
- Ein System pro Schritt, ein Commit pro System, dazu eine kurze Erklärung, was gebaut wurde und warum – der Nutzer will mitlernen.
- Nach jeder Änderung am Spiel das Debug-Fenster neu starten: `pwsh tools/restart_game.ps1`. Das Skript schließt das Fenster normal, damit der Spielstand gespeichert wird – der Nutzer spielt nebenbei. Nie den Prozess abschießen und nie `user://save.json` anfassen; Tests laufen mit eigener Speicherdatei.
- Aussehen der Oberfläche steht in `tools/build_theme.gd`, das `ui/theme.tres` erzeugt. Nicht `theme.tres` von Hand ändern.
- Vor dem Commit: `godot_console --headless --path . res://tests/smoke.tscn` muss „ALLE TESTS OK“ melden.
- Vorhandene Icons aus dem Unity-Projekt wiederverwenden (`SpaceClicker/Assets/Sprites`). Neue Icons im selben flachen Vektorstil.
- Antworten auf Deutsch.
