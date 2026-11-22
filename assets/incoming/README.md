# Incoming packages (not in the game)

- `WaterfrontSideGame_Luau_Package.zip` (owner upload, 2026-11-22): a standalone ocean / watercraft / first-person
  rock-climb / waterfall-dive side game, 7 Luau scripts. Reviewed by the lead and **held for later** (owner: "if it is
  not a fairly easy job ... we will wait and save it for later"). Not wired into any Rojo project. Why: it drives
  standard Roblox Humanoid characters and VehicleSeats (the game's bodies are its own, with no Humanoid), it expects a
  marina breakwater the map does not have (the sea is backdrop past the world clamp), and it builds a large extra world
  at start-up against a town near its part budget. No unsafe calls found (no HttpService, loadstring, required ids,
  DataStores or Teleport). Reuse its ideas on the game's own movement in a future waterfront update.
