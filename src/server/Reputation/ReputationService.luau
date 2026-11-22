--!strict
-- ServerScriptService.Server.Reputation.ReputationService
-- Every player's reputation, kept by the server in the background (owner D30: "make reputation metrics occur in the
-- background ... do not mark this or score this often, only in extreme situations ... it should just show you that,
-- then go away, not be a constant meter, but be checkable with money, in paused and or side screen").
--   * The score: [-100, 100] (Reputation/ReputationRules), 0 for everyone at first; by UserId for as long as this
--     server runs (leaving and coming back finds it as it was; a new server starts everyone at 0, as the wallet does:
--     ProfileSchema has a `reputation` field ready for when it is saved). Below 0 it creeps back toward 0 with time
--     (Reputation/Conduct.recover), worked out when it is read, so nothing runs per frame.
--   * What lowers it is decided by Reputation/Conduct (the rules, pure): ball(player, hit) for the kick ball's hard hits
--     (Items/ItemWorld), runOver(player, hit) for a shared vehicle's knocks (Vehicles/RideBumps through Boot/Game),
--     report(player, kind, severity) for the acts other services judge (Shared/Reputation/Reputation.report: the
--     errand thief, the doctor who drives past a victim). Most calls count nothing: a single accident never does.
--   * The Ladder's own reputation events (Roles/RoleService: a kick that lands on the rodent, a gig well done) go
--     through event(player, name) (ReputationRules.tick), quietly: a rise is never announced.
--   * When it drops, and only then, the player is told once, on their own screen (deps.tell, the game's "notice"
--     toast, a few seconds): "Reputation down: you kept hitting people with the ball (now Fair)". Nobody else is told.
--   * The player attribute Reputation (a whole number, written when it changes; Client/UI/PlayMenu and WalletHud show
--     it with the money where money is shown): only this module writes it.
--   * The human queue's reputation term (Roles/Ladder params.w.reputation) is this score: RoleService reads get(player).
-- Interface: new(deps) -> Service { join(player), get(player) -> number, event(player, name), ball(player, hit) ->
--   Drop?, runOver(player, hit) -> Drop?, report(player, kind, severity?) -> boolean (it counted), step() (publish
--   what recovered), export(player) -> number?, import(player, rep) };
--   start(opts) -> Service (the engine's: the attribute, the notice, the joins, a 10 s publish, Reputation.bind)
-- Pure over deps (Lune drives it with PlayerLike stubs); start is the engine half. No side effects on require.

local Import = require("../Import")
local ReputationRules =
	Import.shared("Reputation/ReputationRules") :: typeof(require("../../shared/Reputation/ReputationRules"))
local Conduct = Import.shared("Reputation/Conduct") :: typeof(require("../../shared/Reputation/Conduct"))
local Reputation = Import.shared("Reputation/Reputation") :: typeof(require("../../shared/Reputation/Reputation"))

local ReputationService = {}

ReputationService.ATTRIBUTE = "Reputation" -- the Player's attribute (a whole number)
ReputationService.PUBLISH_SECS = 10 -- how often start() writes what recovered

-- (Conduct's exported types do not cross the Import shim: restated)
export type Drop = { kind: string, points: number, words: string }
type Book = { [string]: any }

export type Deps = {
	now: () -> number, -- seconds (os.clock in the game)
	tell: ((player: any, words: string) -> ())?, -- the brief notice on that player's screen
	publish: ((player: any, rep: number) -> ())?, -- the Reputation attribute
	log: ((words: string) -> ())?,
}

type Account = {
	player: any,
	low: number, -- the score as of `since` (below 0 it recovers from there)
	since: number, -- when nothing new last counted (recovery runs from here)
	book: Book, -- Conduct's memory of recent hits
	shown: number?, -- the whole number last published
}

export type Service = {
	join: (player: any) -> (),
	get: (player: any) -> number,
	event: (player: any, name: string) -> (),
	ball: (player: any, hit: { [string]: any }) -> Drop?,
	runOver: (player: any, hit: { [string]: any }) -> Drop?,
	report: (player: any, kind: string, severity: number?) -> boolean,
	step: () -> (),
	export: (player: any) -> number?,
	import: (player: any, rep: number) -> (),
}

local function keyOf(player: any): any
	local ok, id = pcall(function()
		return (player :: any).UserId
	end)
	return if ok and id ~= nil then id else player
end

function ReputationService.new(deps: Deps): Service
	local accounts: { [any]: Account } = {}
	local Rc = Conduct.C.recoverSecs

	local function account(player: any): Account
		local k = keyOf(player)
		local a = accounts[k]
		if a == nil then
			a = { player = player, low = ReputationRules.RULES.start, since = deps.now(), book = Conduct.newBook() }
			accounts[k] = a
		end
		a.player = player -- (a rejoin is a new Player instance with the same UserId)
		return a
	end

	-- the score now, with the recovery due folded in (so a change starts from it, keeping the part-step earned)
	local function settle(a: Account): number
		local now = deps.now()
		if a.low < 0 then
			local steps = math.floor((now - a.since) / Rc)
			if steps > 0 then
				a.low = Conduct.recover(a.low, steps * Rc)
				a.since += steps * Rc
			end
		else
			a.since = now
		end
		return a.low
	end

	local function publish(a: Account)
		local n = math.floor(a.low + 0.5)
		if n ~= a.shown then
			a.shown = n
			if deps.publish then
				deps.publish(a.player, n)
			end
		end
	end

	local function lower(a: Account, d: Drop?): Drop?
		if d == nil then
			return nil
		end
		settle(a)
		a.low = ReputationRules.clamp(a.low - d.points)
		a.since = deps.now()
		publish(a)
		if deps.tell then
			deps.tell(a.player, Conduct.notice(d, a.low))
		end
		if deps.log then
			deps.log(`{keyOf(a.player)} -{d.points} ({d.kind}) -> {a.low}`)
		end
		return d
	end

	local self: Service = {
		join = function(player: any)
			local a = account(player)
			settle(a)
			a.shown = nil
			publish(a)
		end,
		get = function(player: any): number
			local a = account(player)
			return settle(a)
		end,
		event = function(player: any, name: string)
			local a = account(player)
			settle(a)
			a.low = ReputationRules.tick(a.low, name)
			publish(a)
		end,
		ball = function(player: any, hit: { [string]: any }): Drop?
			local a = account(player)
			return lower(a, Conduct.ball(a.book :: any, deps.now(), hit :: any))
		end,
		runOver = function(player: any, hit: { [string]: any }): Drop?
			local a = account(player)
			return lower(a, Conduct.runOver(a.book :: any, deps.now(), hit :: any))
		end,
		report = function(player: any, kind: string, severity: number?): boolean
			if type(kind) ~= "string" or kind == "" then
				return false
			end
			local a = account(player)
			return lower(a, Conduct.reported(a.book :: any, deps.now(), kind, severity)) ~= nil
		end,
		step = function()
			for _, a in accounts do
				if a.low < 0 then
					settle(a)
					publish(a)
				end
			end
		end,
		export = function(player: any): number?
			local a = accounts[keyOf(player)]
			return if a then settle(a) else nil
		end,
		import = function(player: any, rep: number)
			if type(rep) ~= "number" or rep ~= rep then
				return
			end
			local a = account(player)
			a.low = ReputationRules.clamp(rep)
			a.since = deps.now()
			publish(a)
		end,
	}
	return self
end

export type StartOpts = {
	fire: (player: any, payload: { [string]: any }) -> (), -- the game's event channel ("notice")
	players: boolean?, -- false: no PlayerAdded / publishing loop (a spec's place)
}

-- The game's: the attribute on each Player, the notice through `fire`, every player who joins given their account (0
-- at first), what recovered written every PUBLISH_SECS, and Shared/Reputation/Reputation.report pointed here.
function ReputationService.start(opts: StartOpts): Service
	local Players = game:GetService("Players")
	local service = ReputationService.new({
		now = os.clock,
		tell = function(player: any, words: string)
			opts.fire(player, { kind = "notice", text = words })
		end,
		publish = function(player: any, rep: number)
			if typeof(player) == "Instance" and (player :: Instance).Parent == Players then
				(player :: Player):SetAttribute(ReputationService.ATTRIBUTE, rep)
			end
		end,
	})
	Reputation.bind(service)
	if opts.players ~= false then
		Players.PlayerAdded:Connect(function(p: Player)
			service.join(p)
		end)
		for _, p in Players:GetPlayers() do
			service.join(p)
		end
		task.spawn(function()
			while true do
				task.wait(ReputationService.PUBLISH_SECS)
				service.step()
			end
		end)
	end
	return service
end

return ReputationService
