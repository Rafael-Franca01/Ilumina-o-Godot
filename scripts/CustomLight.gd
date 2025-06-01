@tool
class_name CustomLight
extends Node3D

enum LightType { DIRECTIONAL, POINT, SPOT } # DIRECTIONAL=0, POINT=1, SPOT=2 (Cuidado com a ordem se mudar)

@export_group("Common Light Properties")
@export var light_type : LightType = LightType.POINT:
	set(value): 
		var old_value = _light_type_internal
		_light_type_internal = value
		if Engine.is_editor_hint() or (is_inside_tree() and old_value != value):
			call_deferred("update_shadow_and_gizmo_config")
	get: return _light_type_internal
@export var light_color : Color = Color(1.0, 1.0, 1.0, 1.0) # Adicionado Alpha para consistência com ColorPicker
@export var light_intensity : float = 10.0

@export_group("Point & Spot Light Properties")
@export var light_range : float = 10.0:
	set(value): 
		var old_value = _light_range_internal
		_light_range_internal = value
		if Engine.is_editor_hint() or (is_inside_tree() and old_value != value) : 
			call_deferred("update_shadow_and_gizmo_config")
	get: return _light_range_internal

@export_group("Spot Light Properties")
@export var spot_angle: float = 45.0: # Ângulo total do cone
	set(value): 
		var old_value = _spot_angle_internal
		_spot_angle_internal = value
		if Engine.is_editor_hint() or (is_inside_tree() and old_value != value) : 
			call_deferred("update_shadow_and_gizmo_config")
	get: return _spot_angle_internal
@export var spot_penumbra_angle: float = 5.0 # Ângulo adicional para suavizar a borda do spot

@export_group("Shadow Properties (Spot Light Only for now)")
@export var cast_shadows : bool = false:
	set(value): 
		var old_value = _cast_shadows_internal
		_cast_shadows_internal = value
		if is_inside_tree() and old_value != value: 
			call_deferred("update_shadow_and_gizmo_config")
	get: return _cast_shadows_internal

@export var depth_pass_material: ShaderMaterial # Arraste seu ShaderMaterial de profundidade aqui

@export_range(0.001, 0.1, 0.001) 
var shadow_bias : float = 0.005

@export_enum("256:256", "512:512", "1024:1024", "2048:2048", "4096:4096") 
var shadow_map_size : int = 1024: # Usado como int diretamente
	set(value): 
		var old_value = _shadow_map_size_internal
		_shadow_map_size_internal = value
		if is_inside_tree() and old_value != value: 
			call_deferred("update_shadow_and_gizmo_config")
	get: return _shadow_map_size_internal

# Variáveis internas para guardar o valor real e evitar chamadas desnecessárias de setter
var _light_type_internal : LightType = LightType.POINT
var _light_range_internal : float = 10.0
var _spot_angle_internal : float = 45.0
var _cast_shadows_internal : bool = false
var _shadow_map_size_internal : int = 1024

# Nós filhos esperados na cena CustomLight.tscn
@onready var shadow_camera_node: Camera3D = $ShadowMapViewport/ShadowCamera
@onready var shadow_map_viewport_node: SubViewport = $ShadowMapViewport
@onready var shadow_caster_root_node: Node3D = $ShadowMapViewport/ShadowCasterRoot # Nó para colocar os sombreadores

# Para debug da textura de COR (não profundidade)
@export var debug_texture_rect_path: NodePath 
var _debug_texture_rect_node: TextureRect = null

func _enter_tree():
	# Garante que os valores exportados sejam os valores internos ao entrar na árvore
	_light_type_internal = light_type 
	_light_range_internal = light_range
	_spot_angle_internal = spot_angle
	_cast_shadows_internal = cast_shadows
	_shadow_map_size_internal = shadow_map_size

	if not is_instance_valid(shadow_map_viewport_node): printerr("'%s': Nó Filho 'ShadowMapViewport' (SubViewport) NÃO ENCONTRADO!" % name)
	if is_instance_valid(shadow_map_viewport_node) and not is_instance_valid(shadow_camera_node): 
		printerr("'%s': Nó Filho 'ShadowMapViewport/ShadowCamera' (Camera3D) NÃO ENCONTRADO!" % name)
	if is_instance_valid(shadow_map_viewport_node) and not is_instance_valid(shadow_caster_root_node):
		printerr("'%s': Nó Filho 'ShadowMapViewport/ShadowCasterRoot' (Node3D) NÃO ENCONTRADO!" % name)
	
	if not debug_texture_rect_path.is_empty():
		var node = get_node_or_null(debug_texture_rect_path)
		if node is TextureRect:
			_debug_texture_rect_node = node
		elif is_instance_valid(node): # Node existe mas não é TextureRect
			printerr("'%s': Nó de debug em '%s' não é um TextureRect." % [name, debug_texture_rect_path])
		# Se node for null, não imprime nada, pois pode ser intencional não ter debug rect

	add_to_group("custom_lights")
	call_deferred("update_shadow_and_gizmo_config") # Deferred para garantir que tudo está pronto

func update_shadow_and_gizmo_config():
	if not is_inside_tree(): return
	if not is_instance_valid(shadow_map_viewport_node) or \
	   not is_instance_valid(shadow_camera_node) or \
	   not is_instance_valid(shadow_caster_root_node):
		# Tenta obter novamente se algo falhou no @onready (ex: mudança de nome de nó no editor)
		var smv_path = NodePath("ShadowMapViewport")
		if has_node(smv_path): shadow_map_viewport_node = get_node(smv_path)
		
		if is_instance_valid(shadow_map_viewport_node):
			var sc_path = NodePath("ShadowMapViewport/ShadowCamera")
			var scr_path = NodePath("ShadowMapViewport/ShadowCasterRoot")
			if has_node(sc_path): shadow_camera_node = get_node(sc_path)
			if has_node(scr_path): shadow_caster_root_node = get_node(scr_path)

		if not is_instance_valid(shadow_map_viewport_node) or \
		   not is_instance_valid(shadow_camera_node) or \
		   not is_instance_valid(shadow_caster_root_node):
			printerr("'%s': Falha ao encontrar nós essenciais para sombra em update_shadow_and_gizmo_config." % name)
			if is_instance_valid(shadow_map_viewport_node): # Se viewport existe mas o resto não, desabilita
				shadow_map_viewport_node.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return

	var current_light_is_spot = (_light_type_internal == LightType.SPOT)
	var should_shadows_be_active = _cast_shadows_internal and current_light_is_spot

	if should_shadows_be_active:
		# Configurações da câmera de sombra
		shadow_camera_node.set_perspective(_spot_angle_internal, 0.05, _light_range_internal + 0.1) # near, far
		# O FOV em set_perspective é vertical. spot_angle é geralmente o ângulo total do cone.
		# Se spot_angle for o FOV horizontal, precisaria de conversão ou usar set_fov() após set_perspective.
		# Para simplificar, assumimos que spot_angle pode ser usado diretamente como FOV vertical aqui.
		# Ou, se spot_angle é o ângulo total do cone, talvez fov = spot_angle.

		if shadow_map_viewport_node.size != Vector2i(_shadow_map_size_internal, _shadow_map_size_internal):
			shadow_map_viewport_node.size = Vector2i(_shadow_map_size_internal, _shadow_map_size_internal)
		
		if shadow_map_viewport_node.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			shadow_map_viewport_node.render_target_update_mode = SubViewport.UPDATE_ALWAYS

		# Aplicar o material override de profundidade
		if is_instance_valid(depth_pass_material):
			# Aplica aos filhos do ShadowCasterRoot
			for child_node in shadow_caster_root_node.get_children():
				if child_node is GeometryInstance3D:
					var geom_instance: GeometryInstance3D = child_node
					geom_instance.material_override = depth_pass_material
		else:
			printerr("'%s': Depth Pass Material NÃO ESTÁ DEFINIDO para sombras!" % name)
			# Desabilitar sombras se o material não estiver lá?
			shadow_map_viewport_node.render_target_update_mode = SubViewport.UPDATE_DISABLED
			# return # Ou simplesmente não aplicar o override

	else: 
		if shadow_map_viewport_node.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			shadow_map_viewport_node.render_target_update_mode = SubViewport.UPDATE_DISABLED
		
		# Remover o material override de profundidade
		if is_instance_valid(depth_pass_material): # Verifica se há um material para tentar remover
			for child_node in shadow_caster_root_node.get_children():
				if child_node is GeometryInstance3D:
					var geom_instance: GeometryInstance3D = child_node
					if geom_instance.material_override == depth_pass_material:
						geom_instance.material_override = null
	
	# Atualiza a visibilidade do gizmo (se você tiver um) com base no tipo de luz e range
	# Exemplo: queue_redraw() se estiver usando _draw() para gizmos.

func _process(_delta):
	# Sincronizar a transformação da câmera de sombra em _process
	# para que ela siga a luz se a luz se mover.
	if _cast_shadows_internal and _light_type_internal == LightType.SPOT and \
	   is_instance_valid(shadow_camera_node) and \
	   shadow_map_viewport_node.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		shadow_camera_node.global_transform = self.global_transform
	
	# Debug da textura de COR do viewport
	if is_instance_valid(_debug_texture_rect_node) and is_instance_valid(shadow_map_viewport_node):
		if _cast_shadows_internal and _light_type_internal == LightType.SPOT and \
		   shadow_map_viewport_node.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_debug_texture_rect_node.texture = shadow_map_viewport_node.get_texture()
		elif _debug_texture_rect_node.texture != null: # Limpa a textura se as sombras não estiverem ativas
			_debug_texture_rect_node.texture = null

# --- Funções para gerenciar os objetos no ShadowCasterRoot ---
# Você precisará chamar estas funções da sua cena principal para adicionar/remover
# objetos que devem projetar sombras para ESTA LUZ ESPECÍFICA.

func add_shadow_caster(node: Node3D, keep_transform: bool = true):
	if not is_instance_valid(shadow_caster_root_node):
		printerr("'%s': ShadowCasterRoot não é válido. Não é possível adicionar sombreador." % name)
		return
	
	var current_parent = node.get_parent()
	if is_instance_valid(current_parent):
		current_parent.remove_child(node)
		
	shadow_caster_root_node.add_child(node)
	if not keep_transform: # Reseta a transformação local se não for para manter a global
		node.transform = Transform3D.IDENTITY
	
	# Aplica o material de profundidade imediatamente se as sombras estiverem ativas
	if _cast_shadows_internal and _light_type_internal == LightType.SPOT and \
	   is_instance_valid(depth_pass_material) and node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = depth_pass_material

func remove_shadow_caster(node: Node3D, reparent_to: Node = null):
	if not is_instance_valid(shadow_caster_root_node) or not node.get_parent() == shadow_caster_root_node:
		#printerr("'%s': Nó não é filho do ShadowCasterRoot. Não é possível remover." % name)
		return

	shadow_caster_root_node.remove_child(node)
	if node is GeometryInstance3D: # Remove o override
		(node as GeometryInstance3D).material_override = null
		
	if is_instance_valid(reparent_to):
		reparent_to.add_child(node)
	# Se reparent_to for null, o nó é removido da árvore de cena (poderia ser queue_free'd depois)

func clear_all_shadow_casters():
	if not is_instance_valid(shadow_caster_root_node): return
	for child_node in shadow_caster_root_node.get_children():
		if child_node is GeometryInstance3D:
			(child_node as GeometryInstance3D).material_override = null
		shadow_caster_root_node.remove_child(child_node)
		# Considere se você quer que esses nós sejam re-adicionados à cena principal ou liberados
		# child_node.queue_free() # Se eles forem apenas para sombras e não existirem em outro lugar
