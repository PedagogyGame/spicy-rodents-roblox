# Changelog: saved place versions

One line per saved place version (BUILD_PLAN §1.2): version -> git sha -> build tag. Saves are made
with `tools/cloud/cloud.mjs save_place`; the CI place takes test payloads, the main place owner builds.

| Date | Place | Version | Git | Tag / note |
|---|---|---|---|---|
| 2026-11-09 | CI (118507593202954) | 1 | n/a | Stock place created by the owner in Step 0. W0 spike S1 ran Luau Execution tasks against it (ping, inject-mode BootSmoke). No new version could be saved: the API key lacks the `assets` and `universe-places:write` permissions (see docs/spikes/S1.md). |
| 2026-11-09 | CI (118507593202954) | 35 | uncommitted w0-foundation tree | Character fixes after the owner's Studio playtest: rounded ball-and-cylinder animal puppets (fox squirrel, mangy red-eyed spicy rodent, red fox, white-tailed deer), smooth gait bob, client visual-root smoothing and AI ground contact, hidden AI name labels. Playtest and PlayBuild suites PASS. |
| 2026-11-09 | CI (118507593202954) | 36 | uncommitted w0-foundation tree | Review fixes on v35: believable deer (doe 4 st shoulder, solid neck, buck x1.1) and fox (2 st shoulder) sizes, faces and hair on placeholder people, no skin-coloured shirts (role palettes and cast), red/blue Neon patrol beacons, placeholders regenerated. Playtest and PlayBuild PASS. |
