extends Node

const MAX_SHADER_LIGHTS = 8

var light_positions_arr = []
var light_colors_arr = []
var light_intensities_arr = []
var light_ranges_arr = []
var light_types_arr = []
var light_directions_arr = []
var light_spot_cos_cutoffs_arr = []

var lit_materials: Array[ShaderMaterial] = []

func _ready():
	for i in range(MAX_SHADER_LIGHTS):
		light_positions_arr.append(Vector3.ZERO)
		light_colors_arr.append(Vector3.ZERO)
		light_intensities_arr.append(0.0)
		light_ranges_arr.append(0.0)
		light_types_arr.append(0)
		light_directions_arr.append(Vector3.FORWARD)
		light_spot_cos_cutoffs_arr.append(Vector2(-1.0, -1.0))

func register_lit_material(material: ShaderMaterial):
	if not material in lit_materials:
		lit_materials.append(material)

func unregister_lit_material(material: ShaderMaterial):
	if material in lit_materials:
		lit_materials.erase(material)

func _process(_delta):
	var active_scene_lights = get_tree().get_nodes_in_group("custom_lights")
	var current_light_count_for_shader = 0

	for i in range(MAX_SHADER_LIGHTS):
		light_types_arr[i] = -1
		light_colors_arr[i] = Vector3.ZERO
		light_intensities_arr[i] = 0.0
		light_positions_arr[i] = Vector3.ZERO
		light_directions_arr[i] = Vector3.FORWARD
		light_ranges_arr[i] = 0.0
		light_spot_cos_cutoffs_arr[i] = Vector2(-1.0, -1.0)

		if i < active_scene_lights.size():
			var light_node = active_scene_lights[i] as CustomLight
			if not is_instance_valid(light_node):
				continue

			light_types_arr[i] = int(light_node.light_type)
			light_colors_arr[i] = Vector3(light_node.light_color.r, light_node.light_color.g, light_node.light_color.b)
			light_intensities_arr[i] = light_node.light_intensity

			match light_node.light_type:
				CustomLight.LightType.POINT:
					light_positions_arr[i] = light_node.global_position
					light_ranges_arr[i] = light_node.light_range
				CustomLight.LightType.DIRECTIONAL:
					light_directions_arr[i] = -light_node.global_transform.basis.z.normalized()
				CustomLight.LightType.SPOT:
					light_positions_arr[i] = light_node.global_position
					light_directions_arr[i] = -light_node.global_transform.basis.z.normalized()
					light_ranges_arr[i] = light_node.light_range
					
					var sa_rad = deg_to_rad(light_node.spot_angle / 2.0)
					var inner_angle_rad = deg_to_rad(light_node.spot_angle / 2.0)
					var outer_angle_rad = inner_angle_rad + deg_to_rad(light_node.spot_penumbra_angle / 2.0)
					
					light_spot_cos_cutoffs_arr[i] = Vector2(cos(inner_angle_rad), cos(outer_angle_rad))

			current_light_count_for_shader += 1

	for mat in lit_materials:
		if is_instance_valid(mat):
			mat.set_shader_parameter("active_light_count", current_light_count_for_shader)
			mat.set_shader_parameter("light_positions", PackedVector3Array(light_positions_arr))
			mat.set_shader_parameter("light_colors", PackedVector3Array(light_colors_arr))
			mat.set_shader_parameter("light_intensities", PackedFloat32Array(light_intensities_arr))
			mat.set_shader_parameter("light_ranges", PackedFloat32Array(light_ranges_arr))
			mat.set_shader_parameter("light_types", PackedInt32Array(light_types_arr))
			mat.set_shader_parameter("light_directions", PackedVector3Array(light_directions_arr))
			mat.set_shader_parameter("light_spot_cos_cutoffs", PackedVector2Array(light_spot_cos_cutoffs_arr))
