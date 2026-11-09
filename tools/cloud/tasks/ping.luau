--!strict
-- Smallest possible Luau Execution task: proves the create/poll/logs/JSON-return loop against
-- any place version (needs none of our modules). Returned JSON includes the version it ran on.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/ping.luau --version <v>

print(`ping from place {game.PlaceId} version {game.PlaceVersion}`)

return {
	suite = "ping",
	ok = true,
	placeId = game.PlaceId,
	placeVersion = game.PlaceVersion,
	hasEngineTests = game:GetService("ServerStorage"):FindFirstChild("EngineTests") ~= nil,
	serverTime = workspace:GetServerTimeNow(),
}
