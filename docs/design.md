# Spielentwurf

Der gültige Stand. Gebaut wird nur, was hier steht. Neue Ideen kommen über `ideen.md` herein.

Stand: Ausgangslage aus dem Unity-Projekt von 2021 übernommen. Abschnitte mit „(alt)“ sind noch nicht für die Godot-Version bestätigt.

## Leitidee

- Ein Incremental-Spiel, in dem man auf der Erde eine Bevölkerung aufbaut.
- Von dort arbeitet man sich auf weitere Planeten vor, bis ein ultimatives Ziel erreicht ist. Das Ziel ist noch offen.
- Anders als bei üblichen Clickern wächst nicht nur eine Währung, sondern mehrere nebeneinander (Coins, Holz, Nahrung, Stein, …).
- Die Anmutung soll etwas futuristisch sein.

## Bestätigt für die Erde

- Klicken gibt Coins oder Holz. Beide haben unterschiedliche Verwendungszwecke.
- Alle Gebäude aus dem alten Stand bleiben (Liste unter „Gebäude Erde“).
- Es gibt eine eigene Sicht, die alle Währungen auf einmal zeigt.

## Umgesetzt in Godot

- Klicken auf den Planeten (Coins oder Holz, umschaltbar)
- Ressourcenleiste mit Vorrat und Produktion pro Sekunde
- Gebäude: Farm, Bevölkerung, Holzfäller, Mine, Wassermühle, Bank – Werte in `data/buildings.json`
- Kaufmenge 1 / 10 / 100
- Speichern alle 10 Sekunden und beim Schließen

Abweichungen vom alten Stand:

- Kostenfaktor 1,15 pro Level für alle Gebäude. Das ist ein Vorschlag, der alte Wert ist unbekannt.
- Bevölkerung ist technisch ein Gebäude (kostet Nahrung, verbraucht 2 Nahrung/s, liefert 1 Bevölkerung).
- Die Erde ist eine sich drehende Kugel statt eines flachen Bildes.

Noch nicht portiert: Schmelze, Fabrik, Sandmine, Solarpanel, Erzabbau, Rezepte, Upgrades, Sicht mit allen Währungen, weitere Planeten.

## Rahmen

- Engine: Godot 4, GDScript
- Plattform: Handy im Hochformat (Android, iOS), später Steam als Kaufversion
- Genre: Incremental/Clicker

## Kernablauf (alt)

1. Planet antippen gibt Coins oder Holz (umschaltbar), anfangs 1 pro Klick.
2. Mit Coins und Holz Gebäude kaufen, die Ressourcen pro Sekunde liefern.
3. Nahrung in Bevölkerung umwandeln; Gebäude belegen Bevölkerung und Strom dauerhaft.
4. Erze abbauen, zu Barren schmelzen, zu Bauteilen verarbeiten.
5. Mit Bauteilen weitere Gebäude und (geplant) neue Planeten freischalten.

Kaufmenge umschaltbar: 1 / 10 / 100.

## Ressourcen (alt)

| Gruppe | Ressourcen |
|---|---|
| Basis | Coins, Holz, Nahrung, Stein, Sand |
| Laufend belegt | Bevölkerung, Strom |
| Erze | Kupfererz, Eisenerz, Golderz |
| Barren | Kupferbarren, Eisenbarren, Goldbarren |
| Bauteile | Kupferkabel, Eisenplatte, Glas, verstärktes Glas |

Bevölkerung: 1 Person kostet 250 Nahrung einmalig und 2 Nahrung/s dauerhaft.

## Gebäude Erde (alt)

Werte aus dem alten Code. Sie dienen als Ausgangspunkt und wandern beim Bauen nach `data/`; danach wird diese Tabelle auf Namen und Funktion gekürzt.

| Gebäude | Liefert | Kaufkosten (Start) | Belegt dauerhaft | Basis/s |
|---|---|---|---|---|
| Farm | Nahrung | 25 Coins, 25 Holz | – | 1 |
| Holzfäller | Holz | 50 Coins | 1 Bevölkerung | 1 |
| Mine | Stein | 75 Coins, 75 Holz | 2 Bevölkerung | 1 |
| Wassermühle | Strom | 100 Coins, 100 Holz | – | 1 |
| Bank | Coins | 125 Coins, 125 Stein | 2 Bevölkerung, 2 Strom | 2 |
| Schmelze | schaltet Schmelzen frei | 100 Coins, 150 Stein | 1 Bevölkerung, 1 Strom | – |
| Fabrik | schaltet Crafting frei | 150 Coins, 180 Holz, 225 Stein | 2 Bevölkerung, 3 Strom | – |
| Sandmine | Sand | Coins (Wert unbekannt) | Bevölkerung (Wert unbekannt) | unbekannt |
| Solarpanel | Strom | 4 Kupferkabel, 3 Eisenplatten, 3 verstärktes Glas | – | 2 |

Erzabbau (Kupfer, Eisen, Gold): je eine eigene Stufe, kostet Nahrung, Holz und Stein, wird ab einem bestimmten Minen-Level freigeschaltet. Im alten Code auskommentiert, Werte unbekannt.

„Unbekannt“ heißt: Der Wert war nur im Unity-Editor eingestellt und ist nicht aus dem Code ablesbar.

## Rezepte (alt)

Jedes Rezept hat eine Dauer und lässt sich auf automatisch stellen. Mengen und Zeiten waren im Unity-Editor eingestellt (unbekannt).

| Wo | Aus | Wird |
|---|---|---|
| Schmelze | Kupfererz | Kupferbarren |
| Schmelze | Eisenerz | Eisenbarren |
| Schmelze | Golderz | Goldbarren |
| Schmelze | Sand | Glas |
| Fabrik | Kupferbarren | Kupferkabel |
| Fabrik | Eisenbarren | Eisenplatte |

Verstärktes Glas wird vom Solarpanel verlangt, hat aber kein Rezept.

## Upgrades (alt)

- Je ein Upgrade für Farm, Holzfäller, Mine, Wassermühle, Bank, Sandmine. Freischaltung ab einem Gebäude-Level. Farm-Upgrade: +1 Basisproduktion; die anderen wurden nicht einzeln geprüft.
- Klick-Upgrades für Coins und Holz: +1 pro Klick, Freischaltung nach Anzahl Klicks.
- Auto-Schmelzen/-Craften als Upgrade-Icons vorhanden.

## Planeten (alt)

- Erde: spielbar.
- Mond: als gesperrter Planet mit Kaufknopf angelegt, ohne Inhalt.
- Mars: gesperrt, ohne Inhalt und ohne Freischaltung.

## Bekannte Schwächen des alten Stands

- Der Kostenfaktor wurde pro Kauf zweimal angewendet (Kosten × Faktor²).
- Kein Offline-Fortschritt gefunden.
- Kein Prestige, kein Endziel.
- Goldbarren und Glas haben keinen erkennbaren Verwendungszweck.

## Offene Fragen

- Was ist das ultimative Ziel? Gibt es Prestige?
- Was heißt „futuristisch“ konkret: nur das Aussehen der Oberfläche, oder auch Inhalte (spätere Gebäude, Technologien)? Die Erde beginnt mit Farm und Holzfäller.
- Wie viele Planeten, was bringt jeder, und wie schaltet man sie frei?
- Wie groß soll das Spiel werden (ein paar Stunden oder Wochen)?
- Worin unterscheiden sich die Verwendungszwecke von Coins und Holz über den Anfang hinaus? Derzeit kosten fast alle Gebäude Coins, Holz nur vier davon.
- Monetarisierung am Handy: welche Art? Was unterscheidet die Steam-Version?

## Später

Noch nichts.
