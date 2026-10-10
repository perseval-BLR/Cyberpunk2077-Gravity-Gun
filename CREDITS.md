# Credits

## Third-party content in the release archive
| What | Author / owner | Source | Terms |
|---|---|---|---|
| 3D model "Half-Life 2 RTX: Gravity Gun" (mesh, PBR textures; the inventory icon is a render of it) | Cassio Soares (https://www.artstation.com/artwork/m89nv9); published on Sketchfab by thippppp | https://sketchfab.com/3d-models/0042fc3936c549e2924b975bd5d8568c | CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) as stated on Sketchfab |
| Gravity gun sounds (`physcannon_*`, `superphys_*`, `physgun_off`) | Valve Corporation (Half-Life 2) | The Sounds Resource, Half-Life 2 → Weapons | © Valve. Used in a free, non-commercial fan mod; removed on request of the rights holder |
| The gravity gun design, *Half-Life* | Valve Corporation | — | Trademarks / copyright of Valve |
| *Cyberpunk 2077* (the Igla shotgun used as the base item) | CD PROJEKT S.A. | — | Used under CD PROJEKT RED's modding guidelines |

**Changes to the model (CC BY 4.0 requires indicating them):** converted from glTF to Cyberpunk 2077 meshes; the
pose baked, glass and crystal parts removed, turned, scaled to 0.72 and placed on the Igla shotgun's receiver;
split into pieces and re-skinned to the receiver's bones; textures resized from 4096 to 2048 px and repacked
(metal/roughness channels separated).

## Behaviour
Gameplay constants and logic follow Half-Life 2's `weapon_physcannon.cpp` and `player_pickup.cpp` (Source SDK 2013,
Valve) — reimplemented in Lua, no Valve code is included.

## Frameworks and tools
Cyber Engine Tweaks (yamashi and contributors), RED4ext (WopsS), redscript (jac3km4), ArchiveXL, TweakXL and Codeware
(psiberx), Audioware (Roms1383), WolvenKit (WolvenKit team), the Cyberpunk 2077 Blender add-on (WolvenKit team),
Blender. References: the RED Modding wiki, the entSpawner mod (spawning helper entities), Let There Be Flight and
EasyTrainers (vehicle physics calls), Push and Pull NPCs (ragdoll impulses).

## Built with AI
Made by perseval-BLR with Claude Code (Anthropic, Claude Opus 5.5): API research, the physics port, the model
conversion pipeline and the item files. Tested in game by perseval-BLR.
