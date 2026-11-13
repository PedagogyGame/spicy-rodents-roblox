# Source status — read before editing

The final **v2 GLBs** in `../GLB/` are the current delivered art and include all additions. They can be imported directly into Blender; no rebuilding is needed to use the models.

The three `*_BASE_v1.blend` files are the recovered, packed Blender authoring scenes from the first pass. They remain intact as editable historical sources and do **not** contain the two new boards or v2 flair.

`Import_v2_Into_Blender.py` assembles final editable Blender scenes from the current GLBs, preserving imported parts and materials and packing their images. It writes only to `Source/V2_Generated/` and refuses to overwrite those generated copies unless `--force` is provided. It was syntax-checked but was **not executed** in this delivery environment.

`Build_Visual_Additions_v2.py` is the executed authoring logic for this update, adapted to package-relative paths. It uses Python 3, NumPy, Pillow and trimesh. It rebuilds the new graphics and mesh additions from the original seed GLBs under `Seed_Assets_v1/`. The new board meshes derive from the already-authored Blender skateboard geometry; the jacket and other v2 detail geometry were generated directly as GLB meshes. Running it replaces the generated art files in this extracted pack, so keep a copy before editing them.

No font files are bundled. The image-generation script uses local system fonts with fallbacks. Typography can vary slightly on a different system.

The other authoring and rendering scripts are the historical v1 Blender sources. Their output should not be mistaken for the finished v2 GLBs.
