--!strict
-- ServerScriptService.Server.Players.PlaceRelease
-- Leaving the server loses your stash and your place (owner D37, 2026-11-22: "if you leave the server, you lose your
-- stash, and place"). Boot/Game calls release on PlayerRemoving (any leave: closing the game, a lost connection, the
-- idle kick of Server/Players/IdleService) with the player's claim key (Boot/Game's claimKey: "player <UserId>"):
--   * the branch-nook stashes (Foraging/BranchStash:clear): every knot-hole's nuts that player kept are gone;
--   * the hollow tree it held (Foraging/HollowService:release): freed for anyone, its nuts (the owner's) gone, and its
--     part towards claiming another tree forgotten.
-- The nooks' and hangouts' seats are the client's (Client/World/BranchNookClient: sitting holds nothing on the server),
-- and the nuts a squirrel carries are its body's (HollowService: dropped when the body changes hands). Joining again,
-- the same server or another, starts fresh.
-- Interface: keyOf(userId) -> "player <UserId>"; release(key, { stash: BranchStash?, hollows: HollowService? }) ->
--   { stash: boolean, tree: string? } (what was let go). Pure. No side effects on require.

local PlaceRelease = {}

export type Places = { stash: any?, hollows: any? }

function PlaceRelease.keyOf(userId: number): string
	return `player {userId}`
end

function PlaceRelease.release(key: string, places: Places): { stash: boolean, tree: string? }
	local out: { stash: boolean, tree: string? } = { stash = false, tree = nil }
	if places.stash then
		out.stash = places.stash:list(key) ~= ""
		places.stash:clear(key)
	end
	if places.hollows then
		out.tree = places.hollows:release(key)
	end
	return out
end

return PlaceRelease
