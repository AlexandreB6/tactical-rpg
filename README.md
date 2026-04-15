# Tactical RPG

[![Demo](https://img.youtube.com/vi/t5PiGAfweDw/maxresdefault.jpg)](https://youtu.be/t5PiGAfweDw)

Jeu de rôle tactique hexagonal développé en **Godot 4.6.1** (GDScript), inspiré de _Vandal Hearts_ et _Battle Brothers_. Combats au tour par tour sur une grille hex flat-top avec élévation, sorts, lignes de vue et IA ennemie. Projet personnel en cours de migration d'un rendu 2D isométrique vers un rendu **3D orthographique**.

## Features

- **Combat tactique** — phases joueur/ennemi, initiative, déplacement A* + flood-fill, attaques corps-à-corps et à distance
- **Grille hexagonale 3D** — hex flat-top avec élévation (plaine, colline, forêt, montagne, eau), ligne de vue bloquée par le relief
- **Système de dégâts typé** — 4 types d'armes (tranchant, perçant, contondant, magique) × 4 types d'armures avec multiplicateurs d'efficacité
- **Sorts & magie** — ressource `SpellData`, ciblage allié/ennemi, FX animés, IA qui priorise les soins sous 70% HP
- **Niveaux JSON** — format data-driven (`data/levels/*.json`) pour terrain, unités, overrides de stats
- **IA ennemie** — scoring multi-critères (focus fire, cibles blessées, hauteur, défense terrain), garde la distance pour les unités ranged
- **Caméra 3D orbitale** — rotation Q/E par 90°, zoom molette, pan, picking par raycast
- **UI in-game** — stats panel, combat log minimisable, action bar contextuelle, écran fin de partie
- **Éditeur de niveaux** — outil intégré pour créer/éditer les maps et exporter en JSON

## Stack technique

- **Godot 4.6.1** (GDScript uniquement, pas de C#)
- **Rendu 3D** — `Node3D`, `Camera3D` orthographique, `ArrayMesh` procédural pour les prismes hex, `Sprite3D` billboard pour les unités
- **Sprites** — Tiny Swords (unités, décorations, UI), sprite sheets d'animations (idle, run, attack, guard, cast)
- **Resources** — `UnitData.tres` (une par classe), `SpellData.tres` (sorts), remap automatique des sprites bleu→rouge pour les ennemis
- **Pathfinding** — A* + BFS flood-fill sur grille hex odd-q offset, coordonnées cubiques pour les distances

## Architecture

Chaque unité est une instance de `Unit3D.tscn` initialisée depuis une resource `UnitData` via `setup(data, grid_pos, hex_grid, team, overrides)`. Un seul `.tres` par classe — l'équipe et les surcharges de stats sont déterminées au spawn depuis le JSON du niveau.

Un **round** est découpé en deux phases : toutes les unités joueur agissent librement (déplacement + action chacune une fois), puis l'IA ennemie joue automatiquement. `GameManager3D` orchestre les transitions via `notify_unit_done()`.

Le flux d'input passe par une **machine d'état** dans `World3D.gd` (`IDLE`, `ACTION_BAR`, `SELECTING_MOVE`, `SELECTING_ATTACK`, `SELECTING_SPELL_TARGET`), ce qui évite les bugs de clics orphelins et simplifie le nettoyage de l'UI entre les actions.

La grille 3D (`HexGrid3D`) génère à la volée un `MeshInstance3D` par case (prisme hex texturé) et un `StaticBody3D` pour le picking. Les hauteurs sont encodées en `ELEVATION_UNIT = 0.5`, et le raycast caméra → plans Y remplace l'ancien `pixel_to_hex` 2D (qui ne gérait pas correctement l'élévation visuelle).

```
World3D (Node3D)
├── CameraPivot → CameraArm → Camera3D (orthographic)
├── HexGrid3D         ← mesh + colliders + décorations
├── Units3D           ← Unit3D × N
├── GameManager3D     ← tour / IA / phases
└── UI (CanvasLayer)  ← StatsPanel / CombatLog / ActionBar / EndScreen
```

## Lancer le jeu

Prérequis : **Godot 4.6.1** ([télécharger](https://godotengine.org/download)).

```bash
# Ouvrir le projet dans l'éditeur Godot puis F5
# Ou via CLI :
godot --path .
```

Scène principale : `res://scenes/world/World3D.tscn`. Le niveau chargé est défini par la variable `@export level_path` dans l'Inspector de `World3D` (par défaut `res://data/levels/level_01.json`).

## Ajouter un niveau

Créer un fichier JSON dans `data/levels/` :

```json
{
  "name": "Nom du niveau",
  "grid_width": 10,
  "grid_height": 8,
  "terrain": [
    "PPFFPPPPPP",
    "PPHHPPMMPP"
  ],
  "units": [
    { "data": "warrior", "team": "player", "pos": [1, 2] },
    { "data": "archer",  "team": "enemy",  "pos": [7, 3], "overrides": { "hp": 8 } }
  ]
}
```

Codes terrain : `P`=Plaine, `F`=Forêt, `H`=Colline, `M`=Montagne, `W`=Eau.

## État du projet

Migration 3D en cours (Issue #8). Les anciennes scènes 2D (`World.tscn`, `hex_grid.gd`) sont conservées pour référence mais ne sont plus maintenues. TODO principaux : polish des sprites 3D, génération de nouvelles classes d'unités, amélioration de l'IA.
