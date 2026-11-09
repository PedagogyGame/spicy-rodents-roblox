# Changelog: saved place versions

One line per saved place version (BUILD_PLAN §1.2): version -> git sha -> build tag. Saves are made
with `tools/cloud/cloud.mjs save_place`; the CI place takes test payloads, the main place owner builds.

| Date | Place | Version | Git | Tag / note |
|---|---|---|---|---|
| 2026-11-09 | CI (118507593202954) | 1 | n/a | Stock place created by the owner in Step 0. W0 spike S1 ran Luau Execution tasks against it (ping, inject-mode BootSmoke). No new version could be saved: the API key lacks the `assets` and `universe-places:write` permissions (see docs/spikes/S1.md). |
