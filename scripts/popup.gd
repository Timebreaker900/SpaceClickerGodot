extends Control
## Ein allgemeines Fenster über dem Spiel: abgedunkelter Hintergrund, Titel,
## Inhalt und ein Knopf zum Schließen. Der Inhalt wird von außen eingefüllt.
## Ein Tipp neben das Fenster schließt es ebenfalls.

@onready var title_label: Label = %Title
@onready var scroll: ScrollContainer = %Scroll
@onready var content: VBoxContainer = %Content
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	close_button.pressed.connect(func() -> void:
		Sfx.play("tap")
		hide())
	Ui.close_on_outside_tap(self, $Center, $Center/Panel)


## Leert den Inhalt, setzt den Titel und zeigt das Fenster. Danach füllt der
## Aufrufer "content".
func open(title: String, height: int = 700) -> void:
	title_label.text = title
	scroll.custom_minimum_size.y = height
	close_button.text = "Fertig"
	for child: Node in content.get_children():
		child.queue_free()
	show()
