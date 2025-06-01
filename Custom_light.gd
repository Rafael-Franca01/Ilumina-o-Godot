@tool
class_name CustomLight
extends Node3D

enum LightType { DIRECTIONAL, POINT, SPOT }

@export_group("Common Light Properties")
@export var light_type : LightType = LightType.POINT
@export var light_color : Color = Color(1.0, 1.0, 1.0)
@export var light_intensity : float = 10.0

@export_group("Point & Spot Light Properties")
@export var light_range : float = 10.0

@export_group("Spot Light Properties")
@export var spot_angle: float = 45.0
@export var spot_penumbra_angle: float = 5.0 # Usado para calcular cutoffs no LightManager
@export var cookie_texture: Texture2D = null
@export var cookie_projector_size: float = 5.0

@export_group("Shadow Properties (Spot Light Only for now)")
@export var cast_shadows : bool = false:
	set(value):
		_cast_shadows_internal = value
		if Engine.is_editor_hint():
			if is_inside_tree(): call_deferred("update_shadow_casting_nodes_visibility")
		else:
			if is_inside_tree(): update_shadow_casting_nodes_visibility()
	get:
		return _cast_shadows_internal

@export_range(0.001, 0.1, 0.001) 
var shadow_bias : float = 0.005

@export var shadow_map_size : int = 1024:
	set(value):
		var new_size = clamp(value, 256, 4096) # Garante que o tamanho seja razoável
		if _shadow_map_size_internal == new_size:
			return
		_shadow_map_size_internal = new_size
		if Engine.is_editor_hint():
			if is_inside_tree(): call_deferred("update_shadow_casting_nodes_visibility")
		else:
			if is_inside_tree(): update_shadow_casting_nodes_visibility()
	get:
		return _shadow_map_size_internal

# Variáveis internas para as propriedades com setters
var _cast_shadows_internal : bool = false
var _shadow_map_size_internal : int = 1024

# Referências aos nós para sombras (DEVEM corresponder à hierarquia em CustomLight.tscn)
@onready var shadow_camera_node: Camera3D = $ShadowMapViewport/ShadowCamera
@onready var shadow_map_viewport_node: SubViewport = $ShadowMapViewport

func _ready():
	add_to_group("custom_lights")

	# Validação inicial dos nós de sombra
	if not is_instance_valid(shadow_map_viewport_node):
		printerr("CustomLight '%s': ERRO AO ENCONTRAR ShadowMapViewport! Caminho esperado: $ShadowMapViewport. Verifique nome e hierarquia em CustomLight.tscn." % name)
	if not is_instance_valid(shadow_camera_node):
		printerr("CustomLight '%s': ERRO AO ENCONTRAR ShadowCamera! Caminho esperado: $ShadowMapViewport/ShadowCamera. Verifique nome e hierarquia em CustomLight.tscn." % name)
	
	# Garante o estado inicial correto para os nós de sombra.
	update_shadow_casting_nodes_visibility()


func _enter_tree():
	# Atualiza a visibilidade/configuração dos nós de sombra ao entrar na árvore (especialmente no editor).
	if Engine.is_editor_hint():
		call_deferred("update_shadow_casting_nodes_visibility")


func update_shadow_casting_nodes_visibility():
	# Tenta obter os nós novamente se as referências @onready estiverem nulas ou se chamado antes de _ready.
	if not is_instance_valid(shadow_map_viewport_node):
		shadow_map_viewport_node = get_node_or_null("ShadowMapViewport") as SubViewport
	if not is_instance_valid(shadow_camera_node):
		if is_instance_valid(shadow_map_viewport_node):
			shadow_camera_node = shadow_map_viewport_node.get_node_or_null("ShadowCamera") as Camera3D

	if not is_instance_valid(shadow_map_viewport_node) or not is_instance_valid(shadow_camera_node):
		# Se ainda não encontrou, não pode prosseguir.
		# Isso pode acontecer se a função for chamada via call_deferred antes dos nós estarem prontos.
		# Os prints de erro no _ready() são mais críticos para a configuração inicial.
		# print_debug("CustomLight '%s': Nós de sombra não disponíveis em update_shadow_casting_nodes_visibility." % name)
		return

	var current_light_is_spot = (get("light_type") == LightType.SPOT) # Usa getter para light_type
	var should_shadows_be_active = get("cast_shadows") and current_light_is_spot # Usa getter para cast_shadows

	if should_shadows_be_active:
		# Configurar a câmera de sombra
		shadow_camera_node.fov = get("spot_angle") # Usa getter
		shadow_camera_node.far = get("light_range")  # Usa getter
		shadow_camera_node.near = 0.05 # Valor padrão, considere exportar se necessário
		
		# Garante que a câmera de sombra seja a 'current' para seu viewport
		if not shadow_camera_node.is_current():
			shadow_camera_node.make_current()
		
		# Configurar o tamanho do viewport de sombra
		var current_shadow_map_size = get("shadow_map_size") # Usa getter
		if shadow_map_viewport_node.size != Vector2i(current_shadow_map_size, current_shadow_map_size):
			shadow_map_viewport_node.size = Vector2i(current_shadow_map_size, current_shadow_map_size)
		
		# Garante que o viewport atualize
		if shadow_map_viewport_node.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			shadow_map_viewport_node.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		# Se não projeta sombras, desabilita a atualização do viewport
		if shadow_map_viewport_node.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			shadow_map_viewport_node.render_target_update_mode = SubViewport.UPDATE_DISABLED
		
		# Limpa 'current' da câmera de sombra se ela estava ativa
		if shadow_camera_node.is_current():
			shadow_camera_node.clear_current()


func _process(_delta):
	if not Engine.is_editor_hint(): # Apenas no jogo
		var current_light_is_spot = (get("light_type") == LightType.SPOT)
		var current_cast_shadows = get("cast_shadows")

		if current_cast_shadows and current_light_is_spot:
			if is_instance_valid(shadow_camera_node):
				# Força a ShadowCamera a seguir a transformação global do CustomLight
				shadow_camera_node.global_transform = self.global_transform
				# Descomente para depurar posições:
				print("LuzPai Pos: ", global_position, " | ShadowCam Pos FORÇADA: ", shadow_camera_node.global_position)
			# else:
				# printerr("CustomLight '%s': shadow_camera_node é INVÁLIDA no _process ao forçar transform." % name)
