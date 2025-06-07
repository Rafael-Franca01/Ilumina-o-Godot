@tool
class_name CustomLight
extends Node3D

enum LightType { POINT, DIRECTIONAL, SPOT }

@export_group("Common Light Properties")
@export var light_type : LightType = LightType.POINT:
	set(value):
		_light_type_internal = value
	get: return _light_type_internal
@export var light_color : Color = Color(1.0, 1.0, 1.0, 1.0)
@export var light_intensity : float = 10.0

@export_group("Point & Spot Light Properties")
@export var light_range : float = 10.0:
	set(value):
		_light_range_internal = value
	get: return _light_range_internal

@export_group("Spot Light Properties")
@export var spot_angle: float = 45.0:
	set(value):
		_spot_angle_internal = value
	get: return _spot_angle_internal
@export var spot_penumbra_angle: float = 5.0

var _light_type_internal : LightType = LightType.POINT
var _light_range_internal : float = 10.0
var _spot_angle_internal : float = 45.0

func _enter_tree():
	_light_type_internal = light_type
	_light_range_internal = light_range
	_spot_angle_internal = spot_angle
	add_to_group("custom_lights")

func _ready():
	pass
