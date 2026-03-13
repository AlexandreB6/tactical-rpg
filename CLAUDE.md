# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Tactical RPG hexagonal en Godot 4.6.1 (GDScript uniquement, pas de C#), inspiré de Vandal Hearts et Battle Brothers.

- **Godot EXE** : `D:\Godot_v4.6.1*.exe` (à la racine de D:\)
- **Lancer le jeu** : ouvrir le projet dans Godot puis F5, ou via la CLI : `D:\Godot_v4.6.1.exe --path D:\Projet\tactical-rpg`
- **Scène principale** : `res://scenes/world/World.tscn`

## Architecture

### Flux de données

```
UnitData.tres (stats) → Unit.tscn (instance) → Units node (container)
                                                      ↓
World.gd (input) → GameManager.gd (tour/IA) → HexGrid.gd (grille)
                                ↓
                    UI : StatsPanel, CombatLog, EndScreen
```

### Système de tours (phases)

Un **round** = phase joueur (toutes les unités joueur agissent librement) puis phase ennemie (IA automatique).

- `GameManager.start_round()` : incrémente le compteur, lance `_start_player_phase()`
- `notify_unit_done(unit)` : marque l'unité comme ayant agi. Si toutes les unités joueur ont agi → `_start_enemy_phase()`
- `is_player_phase()` : utilisé dans `World.gd` pour filtrer les inputs.

### Grille hexagonale

Hexagones **flat-top**, coordonnées **odd-q offset**, taille `HEX_SIZE = 48`. Dimensions dynamiques (chargées depuis le niveau).

- `hex_grid.load_terrain(terrain_rows, width, height)` : charge le terrain depuis des données de niveau
- `hex_to_pixel(q, r)` → position pixel locale (à additionner avec `hex_grid.position`)
- `pixel_to_hex(pixel_pos)` → coordonnées hex (arrondi cubique, prend la position globale)
- `hex_distance(a, b)` → distance en cases (via coordonnées cubiques)

### Unités

Chaque unité est une instance de `Unit.tscn` initialisée via `unit.setup(data: UnitData, grid_pos, hex_grid)`.

Stats : `hp`, `attack`, `defense`, `move_range`, `initiative`, `team` (`"player"` ou `"enemy"`).

Highlights via `unit.set_highlight(state)` : `"active"` (anneau jaune), `"stats"` (anneau cyan), `""` (aucun).

### Système de niveaux

Les niveaux sont définis en JSON dans `res://data/levels/`. Chargement via `World._load_level(path)`.

Format JSON :
```json
{
  "name": "Nom du niveau",
  "grid_width": 10, "grid_height": 8,
  "terrain": ["PPFFPPPPPP", ...],
  "units": [{ "data": "warrior", "pos": [1, 2] }, ...]
}
```
- `terrain` : tableau de chaînes, une par ligne. Caractères : P=Plaine, F=Forêt, H=Colline, M=Montagne, W=Eau
- `units[].data` : nom du fichier `.tres` dans `res://data/units/` (sans extension)
- `units[].pos` : `[q, r]` coordonnées hex

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

1. Créer `res://data/units/nom.tres` (type `UnitData`) via l'éditeur Godot
2. Remplir les champs dans l'Inspector (team = `"player"` ou `"enemy"`)
3. Pour une unité magique : `class_type = MAGIC`, ajouter des sorts dans `spells[]`, fournir `sprite_cast_texture`
4. Ajouter l'unité dans le JSON du niveau : `{ "data": "nom", "pos": [q, r] }`

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
- **Bug** : `pixel_to_hex()` ne compense pas l'élévation visuelle → clics décalés sur terrains élevés (collines, etc.)
- Générer des sprites pour les autres personnages
- Textures hexagones (remplacer les couleurs plates)
- Améliorer l'IA ennemie (actuellement : se rapproche de la cible la plus proche + attaque)
- Vue isométrique + rotation de la map (à reprendre — première tentative annulée)
