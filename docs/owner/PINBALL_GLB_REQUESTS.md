# Pinball: the GLB request for ChatGPT

To ChatGPT, give one file: **`pinball_blender/Pinball_ChatGPT_Pack.zip`**. Ask it to follow `BRIEF_FOR_CHATGPT.md` inside.

What is in the pack:
- **The brief:** what to make, the strict rules (names, origins, metres, Y up), the art for each machine, the content rules (mild rating, no gambling imagery, the rodent never green) and a triangle budget for every file so the alley stays smooth on phones.
- **`pinball_data.json`:** every part of the three machines and the cabinet, in metres, taken straight from the game's code.
- **`reference/`:** a plain blockout of each of the 20 GLB files ChatGPT starts from (the 21st, the pod hoods, is new). Each is already correct in placement, names, pivots and scale, so ChatGPT refines shapes rather than guessing positions.
- **`check_glb.py`:** a checker ChatGPT runs on its own files. It checks each file for:
  - every required name;
  - pivots within 1 mm;
  - the outline of every part the ball touches, within 3 mm;
  - scale;
  - triangle budgets and texture sizes.
- **`images/`:** the labelled plans, cabinet and parts drawings, and pictures of the machines in the game today.

**What comes back:** 24 files (21 GLB models and 3 backglass pictures), with the checker's output saying "24 of 24 files pass". Send them to me and I will fit them into the game.

The files, in short:
- **Shared:** `Pinball_Flipper`, `Pinball_PopBumper`, `Pinball_Plunger`, `Pinball_Gate`, `Pinball_Cabinet`.
- **Per machine** (`Acorn_`, `Rodent_`, `Space_`): `Playfield`, `Guides`, `Slingshots`, `Targets`.
- **Extras:** `Acorn_Spinner`, `Rodent_Wire`, `Space_Ramps`, `Space_PodHoods` (new), and three `<Machine>_Backglass.png` pictures.

The pack is rebuilt from the game's code by `tools/review/pinball_blender/chatgpt_pack.py` (see its header) whenever a table changes.
