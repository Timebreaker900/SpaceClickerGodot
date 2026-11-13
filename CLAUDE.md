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
- Vorhandene Icons aus dem Unity-Projekt wiederverwenden (`SpaceClicker/Assets/Sprites`). Neue Icons im selben flachen Vektorstil.
- Antworten auf Deutsch.
