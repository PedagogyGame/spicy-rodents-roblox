# tests/engine -> ServerStorage.EngineTests (ci.project.json only)

ModuleScripts that run inside the real engine through Open Cloud Luau Execution (BUILD_PLAN §6.5).
They never auto-run: a task script in `tools/cloud/tasks/` requires one and returns JSON.
`BootSmoke` is the W0 suite (every module requires; project properties hold; string requires work).
