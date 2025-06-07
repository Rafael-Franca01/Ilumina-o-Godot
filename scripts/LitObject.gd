extends MeshInstance3D

@export_group("Material Properties")
@export var material_albedo : Color = Color(0.8, 0.8, 0.8, 1.0)
@export var shader_ambient : Color = Color(0.05, 0.05, 0.1, 1.0)
@export var material_roughness : float = 0.5:
	set(value):
		_material_roughness_internal = clamp(value, 0.0, 1.0)
		if is_instance_valid(_cached_shader_material) and not Engine.is_editor_hint():
			_cached_shader_material.set_shader_parameter("material_roughness_uniform", _material_roughness_internal)
	get:
		return _material_roughness_internal
@export_range(0.0, 1.0, 0.001) var material_f0_reflectivity : float = 0.04
@export_range(0.0, 1.0) var material_metallic : float = 0.0
@export var material_emission_color : Color = Color(0.0, 0.0, 0.0, 1.0)

@export_group("Materials & Rendering")
@export var main_pbr_material: ShaderMaterial
@export_flags_3d_render var visual_layers_override : int = 1

@export var object_specific_depth_material: ShaderMaterial

var _material_roughness_internal : float = 0.5
var _cached_shader_material: ShaderMaterial

func _ready():
	_material_roughness_internal = material_roughness
	self.layers = visual_layers_override

	if not is_instance_valid(main_pbr_material):
		printerr("Objeto '%s': main_pbr_material não atribuído!" % name)
		return

	_cached_shader_material = main_pbr_material.duplicate() as ShaderMaterial
	self.material_override = _cached_shader_material

	if is_instance_valid(_cached_shader_material):
		_cached_shader_material.set_shader_parameter("albedo_color_uniform", material_albedo)
		_cached_shader_material.set_shader_parameter("ambient_shader_color_uniform", Vector3(shader_ambient.r, shader_ambient.g, shader_ambient.b))
		_cached_shader_material.set_shader_parameter("material_roughness_uniform", _material_roughness_internal)
		_cached_shader_material.set_shader_parameter("material_f0_scalar_uniform", material_f0_reflectivity)
		_cached_shader_material.set_shader_parameter("material_metallic_uniform", material_metallic)
		_cached_shader_material.set_shader_parameter("material_emission_color_uniform", Vector3(material_emission_color.r, material_emission_color.g, material_emission_color.b))

		if LightManager:
			LightManager.register_lit_material(_cached_shader_material)
		else:
			printerr("Objeto '%s': LightManager (Autoload) não encontrado!" % name)
	else:
		printerr("Objeto '%s': Falha ao duplicar main_pbr_material." % name)

func _exit_tree():
	if is_instance_valid(_cached_shader_material):
		if LightManager:
			LightManager.unregister_lit_material(_cached_shader_material)
	_cached_shader_material = null
