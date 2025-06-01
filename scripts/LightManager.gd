# LightManager.gd
extends Node

const MAX_SHADER_LIGHTS = 8 # Deve ser o mesmo valor do shader PBR

# Arrays para os dados das luzes
var light_positions_arr = []
var light_colors_arr = []
var light_intensities_arr = []
var light_ranges_arr = []
var light_types_arr = [] # int[]
var light_directions_arr = []
var light_spot_cos_cutoffs_arr = [] # vec2[]

var lit_materials: Array[ShaderMaterial] = []

# Variáveis para a sombra de uma única luz
var current_shadow_map_texture: Texture2D = null # Será uma DepthTexture
var current_shadow_light_VIEW_matrix: Transform3D = Transform3D()
var current_shadow_light_PROJ_matrix: Projection = Projection()
var use_shadows_this_frame: bool = false
var shadow_casting_light_shader_idx: int = -1
var current_shadow_bias: float = 0.005

func _ready():
	# Inicializa os arrays com valores padrão
	for i in range(MAX_SHADER_LIGHTS):
		light_positions_arr.append(Vector3.ZERO)
		light_colors_arr.append(Vector3.ZERO) # Cor preta como padrão
		light_intensities_arr.append(0.0)
		light_ranges_arr.append(0.0)
		light_types_arr.append(0) # Assume CustomLight.LightType.POINT como 0
		light_directions_arr.append(Vector3.FORWARD)
		light_spot_cos_cutoffs_arr.append(Vector2(-1.0, -1.0)) # Cutoffs que desabilitam o spot

func register_lit_material(material: ShaderMaterial):
	if not material in lit_materials:
		lit_materials.append(material)

func unregister_lit_material(material: ShaderMaterial):
	if material in lit_materials:
		lit_materials.erase(material)

func _process(_delta):
	var active_scene_lights = get_tree().get_nodes_in_group("custom_lights")
	var current_light_count_for_shader = 0

	# Reseta os parâmetros de sombra para este frame
	use_shadows_this_frame = false
	shadow_casting_light_shader_idx = -1
	current_shadow_map_texture = null # Importante resetar

	# Limpa e preenche os dados das luzes
	for i in range(MAX_SHADER_LIGHTS):
		# Reseta os valores para esta entrada de luz
		light_types_arr[i] = 0 # Default to POINT
		light_colors_arr[i] = Vector3.ZERO
		light_intensities_arr[i] = 0.0
		light_positions_arr[i] = Vector3.ZERO
		light_directions_arr[i] = Vector3.FORWARD
		light_ranges_arr[i] = 0.0
		light_spot_cos_cutoffs_arr[i] = Vector2(-1.0, -1.0)

		if i < active_scene_lights.size():
			var light_node = active_scene_lights[i] as CustomLight # Garante que é do tipo CustomLight
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
					# Direção da luz (para onde ela aponta). No shader, L = -light_direction
					light_directions_arr[i] = -light_node.global_transform.basis.z.normalized()
				CustomLight.LightType.SPOT:
					light_positions_arr[i] = light_node.global_position
					light_directions_arr[i] = -light_node.global_transform.basis.z.normalized()
					light_ranges_arr[i] = light_node.light_range
					
					var sa_rad = deg_to_rad(light_node.spot_angle / 2.0)
					var pa_rad = deg_to_rad(light_node.spot_penumbra_angle / 2.0) # Penumbra é o ângulo total da penumbra
					var inner_cos = cos(sa_rad) # Ângulo interno do cone
					var outer_cos = cos(sa_rad + pa_rad) # Ângulo externo do cone (com penumbra)
					# No shader, usamos smoothstep(outer_cos, inner_cos, dot_product)
					# Então, .x é inner_cos, .y é outer_cos
					light_spot_cos_cutoffs_arr[i] = Vector2(inner_cos, outer_cos)

					# Lógica de Sombras (apenas para a primeira SpotLight habilitada)
					if light_node.cast_shadows and not use_shadows_this_frame:
						var vp_node = light_node.shadow_map_viewport_node # Este é o seu SubViewport
						var cam_node = light_node.shadow_camera_node    # Esta é a Camera3D dentro do SubViewport
						
						if is_instance_valid(vp_node) and is_instance_valid(cam_node) and \
							vp_node.render_target_update_mode != SubViewport.UPDATE_DISABLED:

							var viewport_texture: ViewportTexture = vp_node.get_texture() # Obtém a ViewportTexture

							if is_instance_valid(viewport_texture):
								# CORREÇÃO APLICADA AQUI:
								# Usamos a viewport_texture diretamente. O hint no shader fará com que ela seja
								# amostrada como uma textura de profundidade.
								current_shadow_map_texture = viewport_texture 

								use_shadows_this_frame = true
								shadow_casting_light_shader_idx = i 
								current_shadow_bias = light_node.shadow_bias
								current_shadow_light_VIEW_matrix = cam_node.global_transform.affine_inverse()
								current_shadow_light_PROJ_matrix = cam_node.get_camera_projection()
							else:
								printerr("LM: Spot '%s' não conseguiu obter uma ViewportTexture válida do SubViewport." % light_node.name)
						elif light_node.cast_shadows: 
							printerr("LM: Spot '%s' configurado para sombras, mas seu SubViewport/Camera3D são inválidos ou o SubViewport está desabilitado." % light_node.name)
			
			current_light_count_for_shader += 1
		# else: # Se i >= active_scene_lights.size(), os valores já foram resetados
			# Não precisa fazer nada aqui

	# Atualiza todos os materiais registrados
	for mat in lit_materials:
		if is_instance_valid(mat): # Verifica se o material ainda é válido (ex: objeto foi removido)
			mat.set_shader_parameter("active_light_count", current_light_count_for_shader)
			mat.set_shader_parameter("light_positions", PackedVector3Array(light_positions_arr))
			mat.set_shader_parameter("light_colors", PackedVector3Array(light_colors_arr))
			mat.set_shader_parameter("light_intensities", PackedFloat32Array(light_intensities_arr))
			mat.set_shader_parameter("light_ranges", PackedFloat32Array(light_ranges_arr))
			mat.set_shader_parameter("light_types", PackedInt32Array(light_types_arr))
			mat.set_shader_parameter("light_directions", PackedVector3Array(light_directions_arr))
			mat.set_shader_parameter("light_spot_cos_cutoffs", PackedVector2Array(light_spot_cos_cutoffs_arr))
			
			mat.set_shader_parameter("use_shadow_map_global", use_shadows_this_frame)
			if use_shadows_this_frame and is_instance_valid(current_shadow_map_texture):
				mat.set_shader_parameter("shadow_map_sampler_global", current_shadow_map_texture)
				mat.set_shader_parameter("shadow_light_V_matrix_global", current_shadow_light_VIEW_matrix)
				mat.set_shader_parameter("shadow_light_P_matrix_global", current_shadow_light_PROJ_matrix)
				mat.set_shader_parameter("shadow_casting_light_idx_global", shadow_casting_light_shader_idx)
				mat.set_shader_parameter("shadow_bias_global", current_shadow_bias)
			# Se use_shadows_this_frame for falso, o shader PBR não deve tentar usar os outros uniforms de sombra.
