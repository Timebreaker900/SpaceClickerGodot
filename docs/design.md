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
- Gebäude in dieser Reihenfolge (Werte in `data/buildings.json`):
  1. Farm – Nahrung
  2. Holzfäller – Holz
  3. Mine – Stein, darunter der Bergbau: Kohle ab Mine Lv 2, dann Kupfer, Eisen, Gold
  4. Markt – 1 Coin pro Sekunde, die erste Coin-Quelle ohne Klicken
  5. Sandmine – Sand
  6. Schmelze – schaltet Schmelz-Rezepte frei; braucht Kohle statt Strom
  7. Wassermühle – Strom, zuerst für die Fabrik
  8. Fabrik – schaltet Fabrik-Rezepte frei
  9. Solarpanel – Strom; kostet Coins, Kupferkabel und Eisenplatten
  10. Sägewerk – mehr Holz als der Holzfäller
  11. Bank – das letzte und teuerste Gebäude der Erde: 50 Coins pro Sekunde (Vorschlag); kostet Coins, Stein, Eisenplatten und Goldbarren (1 für die erste, je Level einer mehr), belegt Bevölkerung und Strom
- Verstärktes Glas entfällt: Das Solarpanel braucht es nicht mehr.
- Es gibt eine eigene Sicht, die alle Währungen auf einmal zeigt.

## Umgesetzt in Godot

- Klicken auf den Planeten (Coins oder Holz, umschaltbar)
- Ressourcenleiste mit Vorrat und Produktion pro Sekunde
- Gebäude: Farm, Bevölkerung, Holzfäller, Mine, Wassermühle, Bank – Werte in `data/buildings.json`
- Kaufmenge 1 / 10 / 100
- Speichern alle 10 Sekunden und beim Schließen
- Sandmine, Schmelze, Fabrik
- Erzabbau für Kupfer, Eisen und Gold, freigeschaltet über das Minen-Level
- Rezepte mit Laufzeit, Start-Knopf und Auto-Schalter – Werte in `data/recipes.json`
- Vier Reiter: Gebäude, Produktion, Upgrades, Ressourcen (die Sicht mit allen Währungen)
- Gebäude-Upgrades als Reihe: alle 5 Level eine Stufe. Frühe Gebäude (Farm, Holzfäller, Mine, Markt, Wassermühle, Sandmine) haben 5 Stufen, späte (Solarpanel, Sägewerk, Bank) 10. So hören die frühen ab Level 25 auf, stärker zu werden, und die späten lohnen sich dauerhaft. Stufe n bringt n × 0,5 der Grundproduktion dazu (bei Grundwert 1: +0,5, dann +1, dann +1,5 …). Die Regel steht in `data/upgrade_series.json`.
- Klick-Upgrades als Reihe für Coins und Holz: alle 250 Klicks eine Stufe (250, 500, 750 …), jede bringt +1 pro Klick. Die Regel steht in `data/upgrade_series.json`.
- Eigenes Design: dunkle Flächen mit türkisem Akzent, Schrift Exo 2
- Gezeichnete Erde aus dem alten Projekt als Planet
- Coins/Holz-Umschalter als Icon-Knöpfe; das geklickte Icon fliegt im Bogen weg
- Bevölkerung hat einen eigenen Kaufknopf beim Planeten statt einer Zeile in der Gebäudeliste
- Erzabbau ist ein aufklappbares Untermenü der Mine
- Kosten zeigen Icons; rot wird nur der Posten, der fehlt
- Alle Icons als SVG neu gezeichnet
- Überraschung wie bei Cookie Clicker: Von den Gebäuden sieht man nur die bekannten und das jeweils nächste als schwarzen Umriss mit „???“. Bekannt wird ein Gebäude, wenn sein Vorgänger gekauft ist. Dasselbe gilt für die Erze unter der Mine.
- Upgrades: sichtbar, sobald freigeschaltet; als Rätsel nur für Gebäude, die man besitzt. Rezepte und der Reiter „Produktion“ erscheinen erst mit Schmelze oder Fabrik.
- Ressourcen werden entdeckt: Leiste und Reiter „Ressourcen“ zeigen nur, was man schon einmal hatte.
- Leiste oben zeigt nur den Stand, ohne Rate. Vorräte (Coins, Holz, …) und Versorgung (Bevölkerung, Strom) stehen getrennt.
- Knopf „Leiste anpassen“: höchstens 8 Vorräte frei wählbar, Versorgung ist immer zu sehen.
- Knopf „Einstellungen“: Version und Spielstand zurücksetzen.
- Offline-Fortschritt, aufgebaut über Upgrades: Ohne Upgrade passiert bei Abwesenheit nichts. „Nachtschicht“ schaltet 1 Stunde zu 20 % frei, je drei weitere Upgrades erhöhen die Dauer (2, 4, 8 Stunden) und den Ertrag (40, 60, 80 %). Obergrenze: 8 Stunden zu 80 %. Jede Stufe erscheint erst, wenn die vorige gekauft ist. Ab 60 Sekunden Abwesenheit zeigt das Fenster „Willkommen zurück“ den Ertrag.
- Die späten Abwesenheits-Upgrades kosten Kupferkabel, Eisenplatten, Glas und Goldbarren. Damit haben Glas und Goldbarren einen ersten Verwendungszweck (Vorschlag).

Abweichungen vom alten Stand:

- Kostenfaktor 1,15 pro Level für alle Gebäude. Das ist ein Vorschlag, der alte Wert ist unbekannt.
- Bevölkerung ist technisch ein Gebäude (kostet Nahrung, verbraucht 2 Nahrung/s, liefert 1 Bevölkerung).
- Menge pro Durchgang: 1 beim Freischalten, +1 je weiterem Level von Schmelze bzw. Fabrik, +1 je Mengen-Upgrade des Rezepts. Größere Menge heißt mehr Zutaten und mehr Ergebnis bei gleicher Dauer.
- Das Level der Schmelze schaltet die Schmelz-Rezepte frei: ab Lv 1 Glas, ab Lv 5 Kupferbarren, ab Lv 10 Eisenbarren, ab Lv 15 Goldbarren. Glas steht in der Produktionsliste ganz oben.
- Kohle ist der Brennstoff der Schmelze: Jeder Schmelz-Durchgang verbraucht Kohle als zusätzliche Zutat (Glas und Kupferbarren 1, Eisen- und Goldbarren 2, mal Menge). Die Schmelze belegt dafür keinen Strom.
- Die Fabrik ist genauso gestaffelt: ab Lv 5 Kupferkabel, ab Lv 10 Eisenplatte.
- Höchstlevel von Schmelze und Fabrik: immer 5 Level über der letzten Freischaltung (Schmelze 20, Fabrik 15), damit auch das letzte Rezept noch größere Durchgänge bekommt.
- Die Fabrik kostet zusätzlich Glas: das erste Level 1, jedes weitere eines mehr (bis Lv 10 zusammen 55).

Vorschlagswerte, weil die alten nur im Unity-Editor standen: Kosten und Ertrag der Sandmine, Kosten und Freischalt-Level des Erzabbaus (Mine Lv 5 / 10 / 20), Mengen und Zeiten aller Rezepte. Die Erz-Raten 0,8 / 0,5 / 0,2 pro Sekunde stammen aus dem alten Code.

Vorschlagswerte bei den Upgrades: Eine Stufe der Gebäude-Reihe kostet das Fünffache dessen, was das Gebäude auf dem Freischalt-Level kostet; Strom-Upgrades werden auf ganze Einheiten aufgerundet. Eine Klick-Stufe kostet so viele der geklickten Ressource wie Klicks nötig sind und halb so viele der anderen (Stufe I: 250 und 125); es gibt 40 Stufen.

Noch nicht portiert: Solarpanel, weitere Planeten.

## Feinschliff Erde

Wird Punkt für Punkt abgearbeitet: Nach jedem Punkt testet der Nutzer und gibt den nächsten frei.

- [x] Rückmeldung beim Kauf (Zeile blitzt auf, Icon hüpft)
- [x] Effekt, wenn ein „???“ aufgedeckt wird oder eine Ressource dazukommt (Icon färbt sich ein, Einblendung „Neu: …“ bzw. „Entdeckt: …“)
- [x] Kaufmenge „Max“ (1 → 10 → 100 → Max; kauft so viele Level wie leistbar)
- [x] Ton (Klick, Kauf, Upgrade, Aufdecken, Entdecken, Tippen) – per Code erzeugt, Lautstärke in den Einstellungen
- [x] Planet bewegt sich leicht (schwebt auf und ab, wiegt sich)
- [x] Einstiegshinweis für neue Spieler (führt bis zum ersten Gebäude: tippen, umschalten, kaufen)
- [x] Zahlenformat als Einstellung (kurz: 12.345 / 1,23 Mio, oder wissenschaftlich: 1.23e6; kurz ist Standard)
- [x] Bevölkerungs-Knopf erklärt, wofür Bevölkerung gebraucht wird (Beschriftung, Hinweis beim ersten Gebäude mit Bedarf, „3 frei von 9“ im Reiter)
- [x] Handy-Ränder (Notch, runde Ecken) – eingebaut und mit simulierten Rändern geprüft; am echten Handy noch zu testen
- [x] Ruhigerer Hintergrund (untere Hälfte abgedunkelt, Flächen deckender; das Hintergrundbild selbst ist unverändert)
- [x] Solarpanel (kostet Coins, Kupferkabel, Eisenplatten; verstärktes Glas entfällt)
- [x] Auto bei Rezepten als Upgrade (100 vom eigenen Erzeugnis)
- [x] Erzabbau darf das Level der Mine nie übersteigen
- [x] Rezept-Upgrades, bezahlt mit dem eigenen Erzeugnis: „Schneller“ (je Stufe −1 s, mindestens 1 s) und „Mehr“ (je Stufe +1 Menge, also Zutaten und Ergebnis um den Grundwert); Preis 25, 50, 75 …
- [x] Produktion zeigt Icons statt Namen; oben ein Umschalter zwischen „Schmelzen“ und „Herstellen“
- [x] Leiste oben als festes Raster, damit nichts springt
- [x] Mehr Verwendung für Strom und Goldbarren (Schmelze und Fabrik brauchen viel Strom, die Bank kostet Goldbarren)

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
