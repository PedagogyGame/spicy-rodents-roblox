# assets/ -> ReplicatedStorage.Assets

Content, not code (BUILD_PLAN §1.2): Lune-generated placeholder rigs, vehicles, kit templates and
KeyframeSequences as `.rbxm` or `.model.json`. Nothing here may contain a SurfaceAppearance,
union (PartOperation) or BaseWrap: the place must stay publishable through Open Cloud (§6.4).
Skinned rigs with SurfaceAppearance live in the Art Inbox place and load at runtime by ID (D12).

`Placeholder.model.json` keeps the folder non-empty and gives the place test one known instance.
