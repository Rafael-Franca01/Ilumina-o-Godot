# LightManager.gd
extends Node

const MAX_SHADER_LIGHTS = 8

# Arrays de dados das luzes
var light_positions_arr = []
var light_colors_arr = []
var light_intensities_arr = []
var light_ranges_arr = []
var light_types_arr = [] # Enum LightType: 0:DIRECTIONAL, 1:POINT, 2:SPOT
var light_directions_arr = [] # Usado por DIRECTIONAL e SPOT
var light_spot_cos_cutoffs_arr = [] # vec2(cos_inner_angle, cos_outer_angle), Usado por SPOT

var lit_materials = []

# Variáveis para os dados da luz que projeta sombra (uma por vez)
var current_shadow_map_texture: ViewportTexture = null
var current_shadow_light_VIEW_matrix: Transform3D = Transform3D()
var current_shadow_light_PROJ_matrix: Projection = Projection()
var use_shadows_this_frame: bool = false
var shadow_casting_light_shader_idx: int = -1
var current_shadow_bias: float = 0.005


func _ready():
	# Inicializa os arrays com valores padrão
	for i in range(MAX_SHADER_LIGHTS):
		light_positions_arr.append(Vector3.ZERO)
		light_colors_arr.append(Vector3.ZERO) # Cor preta (luz desligada)
		light_intensities_arr.append(0.0)
		light_ranges_arr.append(0.0)
		light_types_arr.append(CustomLight.LightType.POINT) # Padrão para tipo PONTO
		light_directions_arr.append(Vector3.FORWARD) # Direção padrão
		light_spot_cos_cutoffs_arr.append(Vector2(-1.0, -1.0)) # Spot "desligado"

func register_lit_material(material : ShaderMaterial):
	if not material in lit_materials:
		lit_materials.append(material)

func unregister_lit_material(material : ShaderMaterial):
	if material in lit_materials:
		lit_materials.erase(material)


func _process(_delta): # Parâmetro _delta se não for usado
	var active_scene_lights = get_tree().get_nodes_in_group("custom_lights")
	var current_light_count_for_shader = 0

	# Reseta o estado global das sombras para este frame
	use_shadows_this_frame = false
	shadow_casting_light_shader_idx = -1
	current_shadow_map_texture = null # Limpa a referência da textura anterior

	for i in range(MAX_SHADER_LIGHTS):
		# Valores padrão para slots de luz não ativos ou inválidos (reset a cada frame por slot)
		light_types_arr[i] = CustomLight.LightType.POINT
		light_colors_arr[i] = Vector3.ZERO
		light_intensities_arr[i] = 0.0
		light_positions_arr[i] = Vector3.ZERO
		light_directions_arr[i] = Vector3.FORWARD
		light_ranges_arr[i] = 0.0
		light_spot_cos_cutoffs_arr[i] = Vector2(-1.0, -1.0)

		if i < active_scene_lights.size():
			var light_node = active_scene_lights[i] as CustomLight
			
			if not is_instance_valid(light_node):
				# print_debug("LightManager: Luz no índice %d é inválida." % i) # Para depuração
				continue

			# Coleta dados básicos da luz
			light_types_arr[i] = int(light_node.light_type)
			light_colors_arr[i] = Vector3(light_node.light_color.r, light_node.light_color.g, light_node.light_color.b)
			light_intensities_arr[i] = light_node.light_intensity

			# Coleta dados específicos do tipo
			match light_node.light_type:
				CustomLight.LightType.POINT:
					light_positions_arr[i] = light_node.global_position
					light_ranges_arr[i] = light_node.light_range
					light_directions_arr[i] = Vector3.FORWARD 
					light_spot_cos_cutoffs_arr[i] = Vector2(-1.0, -1.0)

				CustomLight.LightType.DIRECTIONAL:
					light_directions_arr[i] = -light_node.global_transform.basis.z.normalized()
					light_positions_arr[i] = Vector3.ZERO
					light_ranges_arr[i] = 0.0
					light_spot_cos_cutoffs_arr[i] = Vector2(-1.0, -1.0)

				CustomLight.LightType.SPOT:
					light_positions_arr[i] = light_node.global_position
					light_directions_arr[i] = -light_node.global_transform.basis.z.normalized()
					light_ranges_arr[i] = light_node.light_range
					
					var spot_angle_rad = deg_to_rad(light_node.spot_angle / 2.0)
					var penumbra_rad_reduction = deg_to_rad(light_node.spot_penumbra_angle / 2.0)
					var outer_cone_half_angle_rad = spot_angle_rad
					var inner_cone_half_angle_rad = max(0.0, outer_cone_half_angle_rad - penumbra_rad_reduction)
					light_spot_cos_cutoffs_arr[i] = Vector2(cos(inner_cone_half_angle_rad), cos(outer_cone_half_angle_rad))

					# Coleta de Dados de Sombra para esta Luz SPOT
					if light_node.cast_shadows and not use_shadows_this_frame: # Se projeta sombras e ainda não pegamos uma
						var shadow_vp_node = light_node.shadow_map_viewport_node
						var shadow_cam_node = light_node.shadow_camera_node

						if is_instance_valid(shadow_vp_node) and is_instance_valid(shadow_cam_node):
							use_shadows_this_frame = true
							shadow_casting_light_shader_idx = i
							current_shadow_map_texture = shadow_vp_node.get_texture()
							current_shadow_bias = light_node.shadow_bias
							
							var light_cam_global_transform: Transform3D = shadow_cam_node.global_transform
							current_shadow_light_VIEW_matrix = light_cam_global_transform.affine_inverse()
							current_shadow_light_PROJ_matrix = shadow_cam_node.get_camera_projection()
						else:
							printerr("LightManager: Luz Spot '%s' configurada para projetar sombras, mas seus nós de viewport/câmera de sombra são inválidos (CustomLight.gd)." % light_node.name)
			
			current_light_count_for_shader += 1
	
	# Atualiza os shaders de todos os materiais registrados
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

			# Define Uniforms Globais de Sombra
			mat.set_shader_parameter("use_shadow_map_global", use_shadows_this_frame)
			if use_shadows_this_frame: 
				# Envia os uniforms de sombra mesmo que a textura seja nula (o shader deve checar use_shadow_map_global)
				# mas uma checagem extra para a textura aqui não faz mal se o shader não for robusto.
				if is_instance_valid(current_shadow_map_texture): 
					mat.set_shader_parameter("shadow_map_sampler_global", current_shadow_map_texture)
				# else: O shader não deve tentar usar um sampler nulo.
				
				mat.set_shader_parameter("shadow_light_V_matrix_global", current_shadow_light_VIEW_matrix)
				mat.set_shader_parameter("shadow_light_P_matrix_global", current_shadow_light_PROJ_matrix)
				mat.set_shader_parameter("shadow_casting_light_idx_global", shadow_casting_light_shader_idx)
				mat.set_shader_parameter("shadow_bias_global", current_shadow_bias)
