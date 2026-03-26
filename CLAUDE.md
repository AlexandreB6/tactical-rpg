# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Tactical RPG hexagonal en Godot 4.6.1 (GDScript uniquement, pas de C#), inspiré de Vandal Hearts et Battle Brothers.

- **Godot EXE** : `D:\Projet\Godot_v4.6.1-stable_win64.exe`
- **Lancer le jeu** : ouvrir le projet dans Godot puis F5, ou via la CLI : `D:\Projet\Godot_v4.6.1-stable_win64.exe --path D:\Projet\tactical-rpg`
- **Scène principale 3D** : `res://scenes/world/World3D.tscn` (migration 3D en cours)
- **Ancienne scène 2D** : `res://scenes/world/World.tscn` (conservée pour référence)

## Architecture

### Flux de données (3D)

```
UnitData.tres (stats) → Unit3D.tscn (instance) → Units3D node (container)
                                                        ↓
World3D.gd (input) → GameManager3D.gd (tour/IA) → HexGrid3D.gd (grille)
                                  ↓
                      UI : StatsPanel, CombatLog, EndScreen (CanvasLayer, inchangés)
```

### Architecture 3D

```
World3D (Node3D)
├── CameraPivot (Node3D, rotation Q/E par 90°)
│   └── CameraArm (Node3D, rotation.x = -40°)
│       └── Camera3D (orthographic, size = 12)
├── HexGrid3D (Node3D)
│   ├── MeshInstance3D (hex prism) × N    ← terrain
│   ├── StaticBody3D + CollisionShape3D × N  ← picking
│   ├── Sprite3D (décorations) × M        ← arbres/rochers billboard
│   └── FloatingIsland (MeshInstance3D)    ← bloc sous la map
├── Units3D (Node3D)
│   └── Unit3D (Node3D) × K
│       ├── Sprite3D (body, billboard manuel)
│       ├── MeshInstance3D (highlight ring)
│       └── Label3D (nom)
├── DirectionalLight3D + WorldEnvironment
├── GameManager3D (Node)
├── EndScreen / StatsPanel / CombatLog / ActionBar (CanvasLayer)
```

### Système de tours (phases)

Un **round** = phase joueur (toutes les unités joueur agissent librement) puis phase ennemie (IA automatique).

- `GameManager.start_round()` : incrémente le compteur, lance `_start_player_phase()`
- `notify_unit_done(unit)` : marque l'unité comme ayant agi. Si toutes les unités joueur ont agi → `_start_enemy_phase()`
- `is_player_phase()` : utilisé dans `World.gd` pour filtrer les inputs.

### Grille hexagonale

Hexagones **flat-top**, coordonnées **odd-q offset**. Dimensions dynamiques (chargées depuis le niveau).

**3D (HexGrid3D)** : `HEX_SIZE = 1.0` (unités 3D), `ELEVATION_UNIT = 0.5`
- `hex_to_world_local(q, r)` → Vector3 locale (X = q * 1.5, Z = hex spacing, Y = hauteur)
- `get_cell_world_position(cell)` → Vector3 globale (avec offset grille)
- `world_to_hex(world_pos)` → Vector2i (par intersection plans Y)
- `hex_distance(a, b)` → distance en cases (via coordonnées cubiques)
- Picking : raycast Camera3D → intersection plan Y par hauteur de terrain

**2D (ancien, hex_grid.gd)** : `HEX_SIZE = 48` pixels, `ISO_Y_SCALE = 0.55`
- `hex_to_pixel(q, r)`, `pixel_to_hex(pixel_pos)`, `hex_distance(a, b)`

### Unités

Chaque unité est une instance de `Unit.tscn` initialisée via `unit.setup(data: UnitData, grid_pos, hex_grid, team, overrides)`.

Un seul `.tres` par classe (warrior, archer, monk, lancer). L'équipe et les overrides de stats sont déterminés au spawn depuis le JSON du niveau. Les sprites sont automatiquement remappés (`Blue Units` → `Black Units`) pour les ennemis.

Stats : `hp`, `attack`, `defense`, `move_range`, `initiative`, `team` (`"player"` ou `"enemy"`), `damage_type`, `armor_type`.

### Système de dégâts (types d'arme × types d'armure)

Chaque unité a un `damage_type` (SLASHING, PIERCING, BLUNT, MAGIC) et un `armor_type` (NONE, LIGHT, CHAIN, PLATE).
Les sorts ont aussi un `damage_type` (défaut MAGIC).

Table de multiplicateurs (armor × damage) :

|            | Tranchant | Perçant | Contondant | Magique |
|------------|-----------|---------|------------|---------|
| **Aucune** | x1.2      | x1.0    | x0.8       | x1.2    |
| **Légère** | x0.8      | x1.0    | x1.0       | x1.0    |
| **Mailles**| x0.6      | x1.2    | x1.0       | x1.0    |
| **Plate**  | x0.5      | x0.7    | x1.3       | x0.8    |

Formule : `dégâts = max(1, int((atk_power - def_power) * multiplicateur))`

Le multiplicateur est affiché dans le combat log quand ≠ 1.0 (`[efficace x1.3]` ou `[résisté x0.5]`).

Highlights via `unit.set_highlight(state)` : `"active"` (anneau jaune), `"stats"` (anneau cyan), `""` (aucun).

### Système de niveaux

Les niveaux sont définis en JSON dans `res://data/levels/`. Chargement via `World._load_level(path)`.

Format JSON :
```json
{
  "name": "Nom du niveau",
  "grid_width": 10, "grid_height": 8,
  "terrain": ["PPFFPPPPPP", ...],
  "units": [
    { "data": "warrior", "team": "player", "pos": [1, 2] },
    { "data": "warrior", "team": "enemy", "pos": [7, 3], "overrides": {"hp": 8, "attack": 2} }
  ]
}
```
- `terrain` : tableau de chaînes, une par ligne. Caractères : P=Plaine, F=Forêt, H=Colline, M=Montagne, W=Eau
- `units[].data` : nom de la classe (fichier `.tres` dans `res://data/units/` sans extension). Un seul `.tres` par classe, plus de doublons `enemy_*`.
- `units[].team` : `"player"` ou `"enemy"` (obligatoire). Rétrocompat : si absent, le préfixe `enemy_` dans `data` est détecté.
- `units[].pos` : `[q, r]` coordonnées hex
- `units[].overrides` : (optionnel) dictionnaire de stats à surcharger (hp, attack, defense, move_range, initiative, attack_range, min_attack_range, unit_name, spells, damage_type, armor_type)

`World.level_path` est `@export` → modifiable dans l'Inspector pour changer de niveau.

### Système de sorts

Les sorts sont définis comme `SpellData` resources dans `res://data/spells/`. Chaque sort a :
- `spell_name`, `description`, `power` (dégâts ou soin)
- `spell_range`, `min_spell_range` (0 = peut cibler soi-même)
- `target_type` : `ALLY` (même équipe) ou `ENEMY`
- `needs_los` : vérifie la ligne de vue
- `effect_texture` + `effect_hframes` : sprite sheet FX animé sur la cible

Les unités ont un `class_type` (`PHYSICAL` ou `MAGIC`) et un tableau `spells: Array[SpellData]`.
Lancer un sort consomme l'action (`has_acted = true`), comme une attaque physique.

L'IA ennemie utilise les sorts : soin si un allié < 70% HP, sort offensif si dégâts >= attaque physique.

### Ajouter une nouvelle unité

1. Créer `res://data/units/nom.tres` (type `UnitData`) via l'éditeur Godot avec les sprites **Blue Units**
2. Remplir les champs dans l'Inspector. Ajouter `enemy_avatar_texture` si l'avatar ennemi diffère.
3. Pour une unité magique : `class_type = MAGIC`, ajouter des sorts dans `spells[]`, fournir `sprite_cast_texture`
4. Ajouter l'unité dans le JSON du niveau : `{ "data": "nom", "team": "player", "pos": [q, r] }`
5. Pour un ennemi avec stats différentes : `{ "data": "nom", "team": "enemy", "pos": [q, r], "overrides": {"hp": 8} }`
6. Les sprites sont automatiquement remappés `Blue Units` → `Black Units` pour `team = "enemy"`

### UI

Toutes les UI sont des `CanvasLayer` enfants de `World` :
- **StatsPanel** : s'affiche au clic sur n'importe quelle unité. Émet `panel_closed` à la fermeture.
- **CombatLog** : haut gauche, minimisable. `add_entry(text)` pour ajouter une ligne.
- **EndScreen** : overlay victoire/défaite. `show_end_screen(message)` pour l'afficher.

## Conventions GDScript

- Toujours vérifier `unit.is_queued_for_deletion()` avant d'accéder à une unité (elle peut être morte mais encore dans `get_children()`)
- Les positions pixel des unités = `hex_grid.hex_to_pixel(q, r) + hex_grid.position`
- Indentation : **tabulations** (pas d'espaces). Si problème après copier-coller : Edit → Convert Indent to Tabs dans l'éditeur de script Godot.
- Les `await` dans une fonction la rendent asynchrone — les appelants doivent `await` si l'ordre d'exécution est important.

## État actuel et TODO

- ~~Les spawns sont hardcodés dans `World._ready()`~~ → **FAIT** : chargement depuis JSON (`data/levels/level_01.json`)
- ~~Refactoring `_handle_click`~~ → **FAIT** : machine d'état (IDLE, ACTION_BAR, SELECTING_MOVE, SELECTING_ATTACK, SELECTING_SPELL_TARGET)
- ~~Système de sorts~~ → **FAIT** : SpellData resource, Monk (joueur + ennemi), boutons sorts dynamiques, IA sorts
- ~~Système de murs par comparaison de voisins~~ → **FAIT** : hex blocks solides (5 polygones/hex, z_index = r*2 + q%2)
- ~~Ligne de vue~~ → **FAIT** : `has_line_of_sight()` via lerp cubique, Forêt/Montagne bloquent la LOS
- ~~**Bug** : `pixel_to_hex()` ne compense pas l'élévation visuelle~~ → **RÉSOLU** en 3D (raycast par plan Y)
- ~~Vue isométrique + rotation de la map~~ → **EN COURS** : migration 3D (Issue #8), World3D.tscn
- Générer des sprites pour les autres personnages
- Améliorer l'IA ennemie (actuellement : se rapproche de la cible la plus proche + attaque)
- Polish 3D : ajuster tailles sprites, éclairage, île flottante, décorations
