@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_autoload_singleton("Asobi", "res://addons/asobi/asobi_client.gd")

func _exit_tree() -> void:
	remove_autoload_singleton("Asobi")
