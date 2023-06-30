@tool
extends Node3D

var sun_color := Color.BLACK
@export var sun_enabled := true
@export var light_color := Color.WHITE
@export var sky_material: Material = null
@export var sun_object_path: NodePath
@export var moon_object_path: NodePath
@export var sun_ground_Height := 1000.0
@export var sun_saturation_scale := 100.0
@export var sun_saturation_mult := 0.3
@export_range(0.0000001, 1.0) var sun_desaturation_height := 0.25
@export var sun_gradient: GradientTexture1D = null
@export var sun_cloud_gradient: GradientTexture1D = null
@export var sun_cloud_ambient_gradient: GradientTexture1D = null
@export var sun_cloud_ground_gradient: GradientTexture1D = null
@export var compute_gradient_toggle := false:
	get:
		return compute_gradient_toggle
	set(value):
		if value:
			compute_gradient_toggle = false
			var cloud_height = (
				(
					(
						get_param("cloud_bottom")
						+ get_param("cloud_top")
					)
					* 0.5
				)
				+ get_param("Height")
			)
			var sun_min_angle_mult := 1.0
			var min_sun_y := (
				sun_min_angle_mult
				* sin( acos(
						 get_param("earthRadius") / (get_param("earthRadius") + sun_ground_Height)
					)
				)
			)
			var min_cloud_sun_y := (
				sun_min_angle_mult
				* sin( acos(
							get_param("earthRadius") / (get_param("earthRadius") + cloud_height)
					)
				)
			)

			sun_gradient = compute_sun_gradient(sun_ground_Height, min_sun_y)
			sun_cloud_gradient = compute_sun_gradient(min_cloud_sun_y, cloud_height)
			sun_cloud_ambient_gradient = compute_sun_gradient(
				min_cloud_sun_y, get_param("cloud_top"), true
			)
			sun_cloud_ground_gradient = compute_sun_gradient(
				min_cloud_sun_y, get_param("cloud_bottom")
			)

func set_param(param: String, value):
	sky_material.set_shader_parameter(param, value)

func get_param(param: String):
	return sky_material.get_shader_parameter(param)

func compute_sun_gradient(h: float, min_sun_y: float, ambient: bool = false):
	var gradient := GradientTexture1D.new()
	gradient.gradient = Gradient.new()
	var sample_count := 256
	var max_col := 0.0
	var cols: Array[Color] = []
	var poss: Array[float] = []

	var max_sky: Vector4
	if ambient:
		max_sky = sample_sky(
			Basis.from_euler(Vector3(PI * 0.5, PI * 0.5, 0.0)).z, Vector3.UP * h, Vector3.UP
		)
	else:
		max_sky = sample_sky(Vector3.UP, Vector3.UP * h, Vector3.UP)
	for i in range(sample_count):
		var new_i: float = i / (sample_count + 1.0)
		var dir: float = lerp(-0.5 * PI, 0.5 * PI, new_i)
		var b_sun: Basis

		var sun_rot := Vector3(dir, 0.0, 0.0)
		sun_rot.x = min(Vector3(dir, 0.0, 0.0).x, asin(min_sun_y))
		b_sun = Basis.from_euler(sun_rot)

		var b_sample: Basis = Basis.from_euler(Vector3(dir, 0.0, 0.0))
		if ambient:
			b_sample = Basis.from_euler(Vector3(PI * 0.5, PI * 0.5, 0.0))

		var sky: Vector4 = sample_sky(b_sample.z, Vector3.UP * h, b_sun.z)
		var col: Color = Color(sky.x, sky.y, sky.z).srgb_to_linear()
		if not ambient:
			col = saturate(
				col,
				clamp((sun_desaturation_height - b_sun.z.y) / sun_desaturation_height, 0.0, 1.0)
			)
		max_col = max(max_col, col.r, col.g, col.b)
		cols.append(col)
		poss.append(new_i)

	for i in range(sample_count):
		var new_i: float = i / (sample_count + 1.0)
		cols[i] /= max_col
		cols[i].r *= light_color.r
		cols[i].g *= light_color.g
		cols[i].b *= light_color.b
		cols[i].a = 1.0
		if i > 0 and cols[i] == cols[i - 1]:
			continue
		gradient.gradient.add_point(poss[i], cols[i])

	gradient.gradient.remove_point(len(gradient.gradient.offsets) - 1)
	gradient.gradient.remove_point(0)
	return gradient


#func rot_to_gradient(rot: float) -> float:
#	if rot > 0.5*PI:
#		return fmod(rot, 0.5*PI)/PI - 0.5
#	elif rot < -0.5*PI:
#		return 0.5-fmod(rot, 0.5*PI)/PI
#	return rot/PI


func rot_to_gradient(rot: float) -> float:
	return (1.0 - rot) * 0.5


func normalized_color(col: Vector4) -> Vector4:
	if max(col.x, col.y, col.z) == 0.0:
		col = Vector4.ZERO
	else:
		col = col / max(col.x, col.y, col.z)

	return col


func saturate(col: Color, saturation: float) -> Color:
	return Color.from_hsv(
		col.h,
		clamp(log(col.s * saturation * sun_saturation_scale + 1.0) * sun_saturation_mult, 0.0, 1.0),
		col.v
	)


func loop(val: float, val_range: float) -> float:
	if val > val_range:
		return fmod(val, val_range) - val_range
	if val < -val_range:
		return fmod(val, -val_range) + val_range
	return val


func _process(delta):
	var cloud_height = (
		(get_param("cloud_bottom") + get_param("cloud_top"))
		* 0.5 + get_param("Height")
	)
	var sun_dir: Vector3 = global_transform.basis.z
	var sun_min_angle_mult := 1.0
	var min_sun_y := (
		sun_min_angle_mult
		* sin( acos(
				get_param("earthRadius") / (get_param("earthRadius") + sun_ground_Height)
			)
		)
	)
	var min_cloud_sun_y := (
		sun_min_angle_mult
		* sin( acos(
				get_param("earthRadius") / (get_param("earthRadius") + cloud_height)
			)
		)
	)

	var sun_object = get_node(sun_object_path)

	rotation.x = loop(rotation.x, PI)
	rotation.y = loop(rotation.y, PI)
	rotation.z = loop(rotation.z, PI)

	var moon_object = get_node(moon_object_path)
	set_param("precomputed_moon_dir", moon_object.global_transform.basis)
	set_param(
		"precomputed_sun_size", deg_to_rad(sun_object.light_angular_distance)
	)


	var precomputed_sun_size : float = deg_to_rad(sun_object.light_angular_distance)
	var moonRadius : float = get_param("moonRadius")
	var moonDistance : float = get_param("moonDistance")
	var earthRadius : float = get_param("earthRadius")
	var moon_dir : Vector3 = moon_object.global_transform.basis.z

	var moon_size : float = (moonRadius /
		 ((moonDistance + earthRadius) * moon_dir -
				Vector3.UP * (get_viewport().get_camera_3d().global_position.y + earthRadius + get_param("Height"))).length() *
		 2.0) * get_param("moon_size_mult")


	var sun_passthrough := 1.0
	if (moon_size > 0.0):
		var sun_atten_range := sin(precomputed_sun_size)
		var moon_atten_range := sin(deg_to_rad(moon_size)) * 0.5
		sun_passthrough = pow(clamp(1.0 - clamp(min(
									moon_object.global_transform.basis.z.dot(sun_dir),
									  1.0) -
									  (1.0 - moon_atten_range),
								  0.0, 1.0) /
								moon_atten_range,
					  0.0, 1.0),
				2.0)

	sun_object.light_energy = sun_passthrough * lerp(1.0, 0.0, pow(clamp((get_param("cloud_coverage") - 0.25) / 0.75, 0.0, 1.0), 0.5));
	
	set_param(
		"precomputed_sun_energy",
		sun_object.light_intensity_lux / get_world_3d().get_environment().background_intensity
	)

	set_param("precomputed_background_intensity", get_world_3d().get_environment().background_intensity) 

	sun_object.rotation = rotation
	sun_object.rotation.x = (
		max(rotation.x, PI - asin(min_sun_y))
		if (rotation.x > PI * 0.5)
		else min(rotation.x, asin(min_sun_y))
	)

	if sun_enabled:
		sun_object.visible = (
			sun_dir.y > -sin(
				deg_to_rad(sun_object.light_angular_distance)
				+ acos(
						get_param("earthRadius")
						/ (
							get_param("earthRadius")
							+ (
								get_param("cloud_top")
								* float(get_param("clouds"))
							)
						)
				)
			)
		)
		set_param("precomputed_sun_visible", sun_object.visible)
		set_param("precomputed_sun_enabled", sun_enabled)
	else:
		sun_object.visible = false
		set_param("precomputed_sun_visible", false)
		set_param("precomputed_sun_enabled", false)

	var gradient_pos := rot_to_gradient(sun_dir.y)
	var sun_ratio := asin(deg_to_rad(sun_object.light_angular_distance)) / PI
	var sun_gradient_offset: float = -clamp(1.0 - sun_dir.y / sun_ratio, 0.0, 1.0) * sun_ratio
	sun_object.light_color = sun_gradient.gradient.sample(gradient_pos + sun_gradient_offset)
	set_param("precomputed_sun_dir", sun_dir)
	set_param("precomputed_sun_color", light_color)

	#Precomputed cloud lighting
	if get_param("clouds"):
		var cloud_sun_rot := rotation
		cloud_sun_rot.x = min(rotation.x, asin(min_cloud_sun_y))
		set_param(
			"precomputed_Atmosphere_sun",
			sun_cloud_gradient.gradient.sample(gradient_pos + sun_gradient_offset)
		)
		set_param(
			"precomputed_Atmosphere_ambient",
			sun_cloud_ambient_gradient.gradient.sample(gradient_pos)
		)
		set_param(
			"precomputed_Atmosphere_ground", sun_cloud_ground_gradient.gradient.sample(gradient_pos)
		)


var ground_color: Vector3 = Vector3(0.1, 0.07, 0.034)
var ground_brightness: float = 1.0


func solve_quadratic(origin: Vector3, dir: Vector3, Radius: float) -> Vector3:
	var b := 2.0 * dir.dot(origin)
	var c := origin.dot(origin) - Radius * Radius
	var d := b * b - 4.0 * c
	var det := sqrt(d)
	return Vector3((-b + det) * 0.5, (-b - det) * 0.5, d)


func atmosphere(
	Direction: Vector3, pos: Vector3, SunDirection: Vector3, intensity: float = 1.0
) -> Array[Vector3]:
	var shader_Height := 1.0
#	var intensity : float = get_param("intensity")
	var Re: float = get_param("earthRadius")
	var Ra: float = get_param("atmosphereRadius")
	var Hr: float = get_param("rayleighScaleHeight")
	var Hm: float = get_param("mieScaleHeight")
	var mie_eccentricity: float = get_param("mie_eccentricity")
	var turbidity: float = get_param("turbidity")

	var ground := 0.0

	var mu := Direction.dot(SunDirection)
	var phaseR := (3.0 / (16.0 * PI)) * (1.0 + mu * mu)
	var phaseM := (
		(3.0 / (8.0 * PI))
		* (
			(1.0 - mie_eccentricity * mie_eccentricity)
			* (1.0 + mu * mu)
			/ (
				(2.0 + mie_eccentricity * mie_eccentricity)
				* pow(1.0 + mie_eccentricity * mie_eccentricity - 2.0 * mie_eccentricity * mu, 1.5)
			)
		)
	)

	var SumR := Vector3.ZERO
	var SumM := Vector3.ZERO

	var begin := Vector3.ZERO
	var end := Vector3.ZERO

	var cameraPos := Vector3(0, Re + sun_ground_Height + max(0.0, pos.y), 0)
	begin = cameraPos

	var d1 := solve_quadratic(cameraPos, Direction, Ra)
	if d1.x > d1.y && d1.x > 0.0:
		end = cameraPos + Direction * d1.x

		if d1.y > 0.0:
			begin = cameraPos + Direction * d1.y
	else:
		return [Vector3.ZERO, Vector3.ONE, Vector3.ONE]

	var d2 = solve_quadratic(cameraPos, Direction, Re)
	if d2.x > 0.0 && d2.y > 0.0:
		end = begin + Direction * d2.y
		ground = 1.0

	var numSamples := 16 * 16
	var numSamplesL := 8 * 2

	var segmentLength := begin.distance_to(end) / float(numSamples)
	var opticalDepthR := 0.0
	var opticalDepthM := 0.0
	var atmosphere_atten := Vector3.ZERO

	var BetaR: Vector3 = (
		get_param("rayleigh_color")
		* 22.4e-6
		* get_param("rayleigh")
	)
	var BetaM: Vector3 = (
		get_param("mie_color")
		* 20e-6
		* get_param("mie")
	)

	for i in range(numSamples):
		var Px := begin + Direction * segmentLength * (float(i) + 0.5)
		var sampleHeight := Px.length() - Re

		var Hr_sample := exp(-sampleHeight / (Hr * turbidity)) * segmentLength
		var Hm_sample := exp(-sampleHeight / (Hm * turbidity)) * segmentLength

		opticalDepthR += Hr_sample
		opticalDepthM += Hm_sample

		var opticalDepthLR := 0.0
		var opticalDepthLM := 0.0

		var d3 = solve_quadratic(Px, SunDirection, Ra)
		var d4 = solve_quadratic(Px, SunDirection, Re)

		if d4.x > 0.0 and d4.y > 0.0:
			continue

		var j2 := 0

		var segmentLengthL: float = max(d3.x, d3.y) / float(numSamplesL)

		for j in range(numSamplesL):
			var Pl: Vector3 = Px + SunDirection * segmentLengthL * (j + 0.5)
			var sampleHeightL: float = Pl.length() - Re
			if sampleHeightL < 0.0:
				break
			opticalDepthLR += exp(-sampleHeightL / (Hr * turbidity))
			opticalDepthLM += exp(-sampleHeightL / (Hm * turbidity))
			j2 += 1

		if j2 == numSamplesL:
			opticalDepthLR *= segmentLengthL
			opticalDepthLM *= segmentLengthL
			var tau := (
				BetaR * (opticalDepthR + opticalDepthLR)
				+ BetaM * 1.1 * (opticalDepthM + opticalDepthLM)
			)
			var attenuation := v3exp(-tau)
			atmosphere_atten += tau

			SumR += Hr_sample * attenuation
			SumM += Hm_sample * attenuation

	var sky := SumR * phaseR * BetaR + SumM * phaseM * BetaM
	return [
		sky,
		atmosphere_atten * (1.0 - ground),
		v3exp(-(opticalDepthR * BetaR + opticalDepthM * BetaM))
	]


func v3exp(input: Vector3) -> Vector3:
	return Vector3(exp(input.x), exp(input.y), exp(input.z))


func sample_sky(
	dir: Vector3,
	pos: Vector3,
	sun_dir: Vector3,
	LIGHT0_ENERGY: Vector3 = Vector3.ONE,
	LIGHT0_COLOR: Vector3 = Vector3.ONE
) -> Vector4:
	var sun_object = get_node(sun_object_path)
	var sky: Array[Vector3] = atmosphere(dir, pos, sun_dir)
	var skyxyz: Vector3 = sky[0]
	var sun: Vector3 = Vector3.ZERO
	sun = (
		(Vector3.ONE - v3exp(-sky[1]))
		* (
			(
				Vector3.ONE
				* max(
					(
						max(dir.dot(sun_dir), 0.0)
						- (cos(deg_to_rad(sun_object.light_angular_distance)))
					),
					0.0
				)
				* get_param("sun_brightness")
			)
			+ (
				(Vector3.ONE - v3exp(-sky[2]))
				* ground_color
				* max(sun_dir.y, 0.0)
				* sky[2].x
				* ground_brightness
			)
		)
		* LIGHT0_ENERGY
	)

	var col := skyxyz + sun
	return Vector4(col.x, col.y, col.z, 1.0)


func mix(start: Vector3, end: Vector3, factor: float):
	return lerp(start, end, factor)
