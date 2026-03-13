extends Resource
class_name SpellData

enum TargetType { ALLY, ENEMY }

@export var spell_name: String = ""
@export var description: String = ""
@export var power: int = 5
@export var spell_range: int = 3
@export var min_spell_range: int = 0
@export var target_type: TargetType = TargetType.ENEMY
@export var needs_los: bool = true
@export var icon_texture: Texture2D = null
@export var effect_texture: Texture2D = null
@export var effect_hframes: int = 1
