# Startet das Debug-Fenster des Spiels neu, ohne den Spielstand zu verlieren.
#
# Das laufende Fenster wird normal geschlossen (nicht abgeschossen). Dadurch
# speichert das Spiel noch, bevor es endet. Der Editor bleibt offen.

$title = 'Space Clicker (DEBUG)'
$project = Split-Path -Parent $PSScriptRoot

$running = Get-Process | Where-Object { $_.ProcessName -like 'Godot*' -and $_.MainWindowTitle -eq $title }
foreach ($process in $running) {
	[void]$process.CloseMainWindow()
	if (-not $process.WaitForExit(5000)) {
		Write-Warning "Fenster reagiert nicht, Spielstand evtl. bis zu 10 Sekunden alt."
		$process.Kill()
	}
}

Start-Process godot -ArgumentList '--path', $project
"Spiel neu gestartet ($($running.Count) altes Fenster geschlossen)"
