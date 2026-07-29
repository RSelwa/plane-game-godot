class_name Mission

extends RefCounted

var id: String
var modules: Array[String]
var time: int
var lives: int

func _init(p_id: String, p_modules: Array[String], p_time: int, p_lives: int) -> void:
	id = p_id
	modules = p_modules
	time = p_time
	lives = p_lives
