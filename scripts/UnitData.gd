extends Resource
class_name UnitData

@export var unit_name: String = ""
@export var hp: int = 10
@export var attack: int = 3
@export var defense: int = 1
@export var move_range: int = 3
@export var description: String = ""
@export var team: String = "player"
@export var color: Color = Color(0.2, 0.4, 0.9)
@export var initiative: int = 5
@export var attack_range: int = 1
@export var min_attack_range: int = 1
@export var sprite_texture: Texture2D = null
@export var sprite_hframes: int = 1
@export var sprite_run_texture: Texture2D = null
@export var sprite_run_hframes: int = 1
@export var sprite_attack_texture: Texture2D = null
@export var sprite_attack_hframes: int = 1
@export var sprite_guard_texture: Texture2D = null
@export var sprite_guard_hframes: int = 1
@export var sprite_scale_factor: float = 1.0
@export var projectile_texture: Texture2D = null
