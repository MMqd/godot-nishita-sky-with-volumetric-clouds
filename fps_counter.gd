extends Label


func _ready():
	$"/root/Main/Camera3D".position.y = (
		pow($"%HeightSlider".value, 4.0)
		- $"/root/Main/WorldEnvironment".environment.sky.sky_material.get_shader_parameter("Height")
		+ 1.0
	)


func _process(delta: float) -> void:
	set_text("FPS: " + str(Engine.get_frames_per_second()))
	get_node("/root/Main/Moon Holder/Moon").transform.rotated(Vector3.UP, delta)


func _on_height_slider_value_changed(value):
	$"/root/Main/Camera3D".position.y = (
		pow(value, 4.0)
		- $"/root/Main/WorldEnvironment".environment.sky.sky_material.get_shader_parameter("Height")
		+ 1.0
	)
