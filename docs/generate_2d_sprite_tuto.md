# Générer des sprites 2D avec IA — Style Vandal Hearts

## Pour les sprites d'unités (personnages)

**Meilleures options :**
- **Midjourney** — le meilleur pour du pixel art / sprite art stylisé. Prompt type : `"tactical RPG character sprite, top-down view, knight with sword, 32-bit style, transparent background, sprite sheet"`
- **Stable Diffusion** (local ou via ComfyUI) — gratuit, très personnalisable avec des modèles fine-tunés pour le pixel art. Cherche des checkpoints comme `pixel-art-xl` sur CivitAI.

## Pour les tilesets (terrain hex)

- **Stable Diffusion + ControlNet** — tu peux lui donner la forme hexagonale comme guide et générer des textures cohérentes (herbe, forêt, eau, etc.)
- **Midjourney** puis découpe manuelle dans un éditeur d'image

## Pour un style Vandal Hearts spécifiquement

Vandal Hearts a un style assez unique : personnages en 3D pré-rendue sur grille iso, couleurs saturées, proportions trapues. Pour reproduire ça :

- **Prompts clés** : `"vandal hearts style, tactical RPG, isometric character, saturated colors, PS1 era, low poly pre-rendered sprite"`
- Génère en plus grand puis réduis à la taille voulue (64x64 ou 128x128) — ça donne un look plus propre

## Workflow recommandé pour le projet

1. Génère les sprites en **batch** (toutes les unités dans un style cohérent) avec le même seed/style
2. Exporte en **PNG avec transparence**
3. Place-les dans `res://assets/sprites/` et charge-les dans `UnitData.tres` (il faudra ajouter un champ `texture`)

## Outil bonus

- **Aseprite** (15$) — indispensable pour retoucher/animer les sprites générés par l'IA. Tu peux prendre un sprite statique et en faire un idle animation facilement.
