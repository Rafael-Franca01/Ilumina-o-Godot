# TestLitObject.gd
extends MeshInstance3D

@export_group("Material Properties")
@export var material_albedo : Color = Color(0.8, 0.8, 0.8, 1.0)
@export var shader_ambient : Color = Color(0.05, 0.05, 0.1, 1.0) # Cor ambiente específica do shader para este material

@export var material_roughness : float = 0.5:
	set(value):
		_material_roughness_internal = clamp(value, 0.0, 1.0)
		# Para atualizar o shader em tempo real se o valor for mudado no Inspector DURANTE o jogo:
		if is_instance_valid(_cached_material_instance) and Engine.is_editor_hint() == false: # Apenas no jogo
			_cached_material_instance.set_shader_parameter("material_roughness_uniform", _material_roughness_internal)
	get:
		return _material_roughness_internal

@export_range(0.0, 1.0, 0.001) 
var material_f0_reflectivity : float = 0.04 # F0 para dielétricos (não-metais)

@export_range(0.0, 1.0) # Step padrão de 0.01 para float range
var material_metallic : float = 0.0 # 0.0 para dielétrico, 1.0 para metálico

@export var material_emission_color : Color = Color(0.0, 0.0, 0.0, 1.0) # Cor da emissão


var _material_roughness_internal : float = 0.5 # Valor inicial deve corresponder ao default do export
var _cached_material_instance: ShaderMaterial 

func _ready():
	# O setter de material_roughness já foi chamado por Godot ao inicializar o export,
	# então _material_roughness_internal já tem o valor correto (default ou do Inspector) e clampeado.
	# A linha '_material_roughness_internal = material_roughness' é redundante aqui.

	var mat = get_active_material(0)
	if mat is ShaderMaterial:
		_cached_material_instance = mat 
		
		mat.set_shader_parameter("albedo_color_uniform", material_albedo)
		mat.set_shader_parameter("ambient_shader_color_uniform", shader_ambient)
		mat.set_shader_parameter("material_roughness_uniform", _material_roughness_internal) # Usa a var interna
		mat.set_shader_parameter("material_f0_scalar_uniform", material_f0_reflectivity)
		mat.set_shader_parameter("material_metallic_uniform", material_metallic)
		mat.set_shader_parameter("material_emission_color_uniform", material_emission_color)
		
		if LightManager:
			LightManager.register_lit_material(mat)
			# print("Objeto '%s': Registrado no LightManager." % name) # Para depuração
		else:
			printerr("Objeto '%s': LightManager (Autoload) não encontrado!" % name)
	else:
		if mat == null:
			printerr("Objeto '%s': Sem material para configurar ou registrar!" % name)
		else:
			printerr("Objeto '%s': Material não é ShaderMaterial! Tipo: %s" % [name, mat.get_class()])

func _exit_tree():
	if is_instance_valid(_cached_material_instance):
		if LightManager: # Boa prática checar se LightManager ainda existe ao sair
			LightManager.unregister_lit_material(_cached_material_instance)
	_cached_material_instance = null
