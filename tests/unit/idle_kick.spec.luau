--!strict
-- Idle players are removed (owner D38: "15 minutes of inactivity, should kick you out, for any player, the spicy
-- rodent, 8 minutes") and leaving loses your stash and your place (owner D37: "if you leave the server, you lose your
-- stash, and place"):
--   Shared/Players/IdleRules: both limits, the warning a minute before, the words; what counts as input (a held
--   squirrel's motor packets only with a key down or a click; a phone's motion sensors and a resting stick never);
--   the client's ping at most every 20 s and only after input, at once while warned
--   Server/Players/IdleService: warned once, cleared by input, kicked with the friendly words; the limit follows the
--   role held now and the time already idle counts; a seated player who presses nothing is removed, one playing a
--   minigame (Net "Minigame.Input", through Net.heard) is not; the place's owner is not exempt; the flag turns it off
--   Server/Players/PlaceRelease: nuts stashed in a branch nook, leave, rejoin: empty; the hollow tree held is freed
--   and emptied, a part towards another tree forgotten
local Data = require("@shared/Data")
local Flags = require("@shared/Config/Flags")
local Games = require("@shared/Minigames/Games")
local HollowClaim = require("@shared/Foraging/HollowClaim")
local IdleRules = require("@shared/Players/IdleRules")
local Net = require("@shared/Net/Net")
local Tunables = require("@shared/Config/Tunables")
local BranchNooks = require("@shared/World/BranchNooks")
local BranchStash = require("@server/Foraging/BranchStash")
local HollowService = require("@server/Foraging/HollowService")
local IdleService = require("@server/Players/IdleService")
local PlaceRelease = require("@server/Players/PlaceRelease")

return function(t)
	t.test("the rules: 15 minutes for anyone, 8 for the Spicy Rodent, the warning a minute before", function()
		t.eq(Tunables.get("idle.anyone"), 900)
		t.eq(Tunables.get("idle.spicyRodent"), 480)
		t.eq(Tunables.get("idle.warn"), 60)
		t.eq(IdleRules.verdict(0, 0, false), "ok")
		t.eq(IdleRules.verdict(0, 839, false), "ok")
		t.eq(IdleRules.verdict(0, 840, false), "warn")
		t.eq(IdleRules.verdict(0, 899.5, false), "warn")
		t.eq(IdleRules.verdict(0, 900, false), "kick")
		t.eq(IdleRules.verdict(100, 1000, false), "kick", "measured from the last input")
		t.eq(IdleRules.verdict(0, 419, true), "ok")
		t.eq(IdleRules.verdict(0, 420, true), "warn")
		t.eq(IdleRules.verdict(0, 480, true), "kick")
		t.eq(IdleRules.warnText(), "Still there? You'll leave the server in a minute if you don't move.")
		t.eq(IdleRules.kickText(false), "You were away for 15 minutes, so you left the server. Come back any time!")
		t.eq(IdleRules.kickText(true), "You were away for 8 minutes, so you left the server. Come back any time!")
		-- under Roblox's own 20-minute idle kick, so ours comes first
		t.truthy(Tunables.get("idle.anyone") < 1200 and Tunables.get("idle.spicyRodent") < 1200)
	end)

	t.test("what counts as input: keys or a click in the motor packet; never the sensors or a resting stick", function()
		-- sitting (a nook's ledge, a seat): the motor gets no keys, its speed eases to nothing
		t.falsy(IdleRules.motorActive({ moveSpeed = 0, clickSeq = 0 }))
		t.falsy(IdleRules.motorActive({ moveSpeed = 0.01, clickSeq = 0 }), "a key let go, the speed eased away")
		t.truthy(IdleRules.motorActive({ moveSpeed = 7.2, clickSeq = 0 }), "walking: a key down")
		t.truthy(IdleRules.motorActive({ moveSpeed = 0, clickSeq = 3 }), "a click")
		t.falsy(IdleRules.motorActive({}))
		t.truthy(IdleRules.counts("Keyboard"))
		t.truthy(IdleRules.counts("MouseButton1"))
		t.truthy(IdleRules.counts("MouseMovement", 0), "the camera turning: the player is there")
		t.truthy(IdleRules.counts("Touch", 0))
		t.truthy(IdleRules.counts("Gamepad1"), "a pad button")
		t.falsy(IdleRules.counts("Gamepad1", 0.1), "a resting stick's drift")
		t.truthy(IdleRules.counts("Gamepad1", 0.8), "the stick pushed")
		t.falsy(IdleRules.counts("Gyro", 1))
		t.falsy(IdleRules.counts("Accelerometer", 1))
		t.truthy(IdleRules.INTENT["Minigame.Input"] and IdleRules.INTENT.Action and IdleRules.INTENT["Offer.Reply"])
		t.falsy(IdleRules.INTENT["Squirrel.State"], "the motor packets come every frame, keys or none")
	end)

	t.test("the client's ping: only after input, at most one every 20 s, at once while warned", function()
		local p = IdleRules.pinger()
		t.falsy(IdleRules.pingDue(p, 0, false), "no input: nothing")
		IdleRules.input(p, 1)
		t.truthy(IdleRules.pingDue(p, 1, false))
		t.falsy(IdleRules.pingDue(p, 2, false), "sent: nothing new")
		IdleRules.input(p, 5)
		t.falsy(IdleRules.pingDue(p, 5, false), "within 20 s")
		t.falsy(IdleRules.pingDue(p, 20.9, false))
		t.truthy(IdleRules.pingDue(p, 21, false), "20 s on")
		IdleRules.input(p, 22)
		t.truthy(IdleRules.pingDue(p, 22, true), "warned: at once")
		t.falsy(IdleRules.pingDue(p, 23, true), "but only after input")
	end)

	-- the service over fake players and a clock
	local function rig()
		local clock = { v = 0 }
		local players: { any } = {}
		local spicy: { [any]: boolean } = {}
		local told: { [any]: { any } } = {}
		local kicked: { [any]: string } = {}
		local idle = IdleService.new({
			players = function(): { any }
				return players
			end,
			now = function(): number
				return clock.v
			end,
			spicy = function(player: any): boolean
				return spicy[player] == true
			end,
			tell = function(player: any, msg: any)
				told[player] = told[player] or {}
				table.insert(told[player], msg)
			end,
			kick = function(player: any, text: string)
				kicked[player] = text
				local i = table.find(players, player)
				if i then
					table.remove(players, i)
				end
			end,
			enabled = function(): boolean
				return Flags.enabled("idleKick")
			end,
		})
		-- the server's step, once a second, up to `to`
		local function run(to: number)
			while clock.v < to do
				clock.v += 1
				idle:step()
			end
		end
		return idle, clock, players, spicy, told, kicked, run
	end

	t.test("the service: warned once, input clears it, kicked with the words; per player", function()
		local idle, clock, players, _spicy, told, kicked, run = rig()
		local a, b = { UserId = 1 }, { UserId = 2 }
		table.insert(players, a)
		table.insert(players, b)
		idle:step() -- (first seen: the clock starts)
		run(839)
		t.eq(told[a], nil, "no notice before 14 minutes")
		run(841)
		t.eq(#told[a], 1)
		t.eq(told[a][1].kind, "idle")
		t.eq(told[a][1].text, IdleRules.warnText())
		t.near(told[a][1].secs, 60, 1)
		run(860)
		t.eq(#told[a], 1, "said once")
		-- b moves: the notice goes, the clock starts again
		idle:touch(b)
		t.eq(told[b][2].clear, true)
		run(901)
		t.eq(kicked[a], "You were away for 15 minutes, so you left the server. Come back any time!")
		t.eq(kicked[b], nil, "b pressed something at 860")
		t.eq(idle:idleFor(a), nil, "forgotten")
		run(860 + 901)
		t.truthy(kicked[b] ~= nil)
		local _ = clock
	end)

	t.test("the Spicy Rodent: 8 minutes; the limit follows the role held now, the time already idle counts", function()
		local idle, _clock, players, spicy, told, kicked, run = rig()
		local r, s, q = { UserId = 3 }, { UserId = 4 }, { UserId = 5 }
		for _, p in { r, s, q } do
			table.insert(players, p)
		end
		spicy[r] = true
		idle:step()
		run(421)
		t.eq(#told[r], 1, "the rodent is warned at 7 minutes")
		t.eq(told[s], nil)
		-- s becomes the rodent after 7.5 minutes idle (the server handed the role: no press of theirs): warned at once
		run(450)
		spicy[s] = true
		run(451)
		t.eq(#told[s], 1)
		-- r stops being the rodent at 7.5 minutes: 15 minutes now, the notice goes
		spicy[r] = false
		run(452)
		t.eq(told[r][2].clear, true)
		run(481)
		t.eq(kicked[s], "You were away for 8 minutes, so you left the server. Come back any time!")
		t.eq(kicked[r], nil, "anyone's 15 minutes now")
		-- q became the rodent after 9 minutes idle: over its limit already, out at the next check
		run(540)
		spicy[q] = true
		run(541)
		t.eq(kicked[q], "You were away for 8 minutes, so you left the server. Come back any time!")
		run(901)
		t.eq(kicked[r], "You were away for 15 minutes, so you left the server. Come back any time!")
		local _ = idle
	end)

	t.test("sitting alone is idle; a seated player pressing things or playing a minigame is not", function()
		local idle, clock, players, _spicy, _told, kicked, run = rig()
		local sitter, gamer, owner = { UserId = 6 }, { UserId = 7 }, { UserId = 8 }
		for _, p in { sitter, gamer, owner } do
			table.insert(players, p)
		end
		-- the place's owner (a dev) is not exempt
		Flags.configure({ devUserIds = { 8 } })
		t.truthy(Flags.isDev(owner))
		-- the Net remotes as Boot/Game wires them: an accepted packet in IdleRules.INTENT is input
		local net = Net.new({
			send = function() end,
			players = function()
				return players
			end,
		}, {
			clock = function(): number
				return clock.v
			end,
		})
		net.heard = function(player: any, name: string)
			if IdleRules.INTENT[name] then
				idle:touch(player)
			end
		end
		net:on("Minigame.Input", function() end)
		local verb = Games.verbs()[1]
		idle:step()
		for at = 60, 1800, 60 do
			run(at)
			-- the sitter's motor packets: still, no keys
			if IdleRules.motorActive({ moveSpeed = 0, clickSeq = 0 }) then
				idle:touch(sitter)
			end
			-- the gamer presses a minigame key every five minutes
			if at % 300 == 0 then
				local ok = net:receive(gamer, "Minigame.Input", { gameId = "lane1", seat = 1, verb = verb }, clock.v)
				t.truthy(ok)
			end
		end
		t.truthy(kicked[sitter] ~= nil, "sat still for 15 minutes")
		t.truthy(kicked[owner] ~= nil, "the owner too")
		t.eq(kicked[gamer], nil, "a minigame's presses keep you in")
		-- a packet Net refuses (bad shape) is no evidence
		local before = idle:idleFor(gamer) :: number
		clock.v += 30
		t.falsy(net:receive(gamer, "Minigame.Input", { gameId = "lane1", seat = 99, verb = verb }, clock.v))
		t.truthy((idle:idleFor(gamer) :: number) > before)
		Flags.configure({ devUserIds = {} })
	end)

	t.test("the flag: off, nobody is removed", function()
		local idle, _clock, players, _spicy, told, kicked, run = rig()
		local a = { UserId = 9 }
		table.insert(players, a)
		Flags.set("idleKick", false)
		idle:step()
		run(2000)
		Flags.set("idleKick", true)
		t.eq(kicked[a], nil)
		t.eq(told[a], nil)
		t.eq(Flags.defaults.idleKick, true, "on by default")
	end)

	t.test("D37: nuts stashed in a branch nook, leave, rejoin: the stash is empty", function()
		local d = Data.default()
		local nooks = BranchNooks.new(d:module("BranchNooks") :: any)
		local nook: any = nil
		for _, p in nooks.places do
			if p.kind == "nook" and p.stash ~= nil then
				nook = p
				break
			end
		end
		t.truthy(nook, "a nook with a stash")
		local held: { [number]: number } = {}
		local hollows = {
			carried = function(_self: any, id: number): number
				return held[id] or 0
			end,
			carry = function(_self: any, id: number, n: number): number
				local cur = held[id] or 0
				local taken = math.max(0, math.min(n, Tunables.get("forage.carryMax") - cur))
				held[id] = cur + taken
				return taken
			end,
			drop = function(_self: any, id: number)
				held[id] = nil
			end,
			-- (every nut here was picked up by its holder: HollowService:mine keeps them all)
			mine = function(_self: any, id: number): number
				return held[id] or 0
			end,
		}
		local clock = 0
		local stash = BranchStash.new({
			nooks = nooks,
			hollows = hollows,
			placeOf = function(_id: number): (number?, number?, number?)
				return nook.at[1], nook.at[2], nook.at[3]
			end,
			keyOf = function(id: number): string
				return PlaceRelease.keyOf(if id == 1 then 7 else 9)
			end,
			now = function(): number
				return clock
			end,
		})
		held[1], held[2] = 6, 4
		t.truthy(stash:use(1, nook.route).ok)
		t.truthy(stash:use(2, nook.route).ok)
		t.eq(stash:stored("player 7", nook.route), 6)
		-- player 7 leaves (closing the game, or the idle kick)
		local gone = PlaceRelease.release(PlaceRelease.keyOf(7), { stash = stash })
		t.eq(gone.stash, true)
		-- and joins again (a new body: id 3, the same player)
		clock += 1
		t.eq(stash:stored("player 7", nook.route), 0)
		t.eq(stash:list("player 7"), "")
		local back = stash:use(1, nook.route)
		t.eq(back.word, "empty", back.text)
		t.eq(stash:stored("player 9", nook.route), 4, "the others' stashes stay")
		t.eq(PlaceRelease.release("player 7", { stash = stash }).stash, false, "nothing left to lose")
	end)

	t.test("D37: the hollow tree held is freed and emptied; a part towards another forgotten", function()
		local svc = HollowService.new({ world = {} :: any, cover = false })
		local ids = {}
		for id in svc.claims do
			table.insert(ids, id)
		end
		table.sort(ids)
		t.truthy(#ids >= 2)
		local own, other = svc.claims[ids[1]], svc.claims[ids[2]]
		local h = svc.layout.hollow(ids[1]) :: any
		local cap = h.meter.capacity
		local ownAt, margin = Tunables.get("forage.ownThreshold"), Tunables.get("forage.keepMargin")
		-- (a few nuts into another tree first, then its own tree claimed)
		HollowClaim.deposit(other, "player 7", 1, 1, 1000, ownAt, margin)
		HollowClaim.deposit(other, "player 9", 2, 1, 1000, ownAt, margin)
		t.eq(other.brought["player 7"], 1)
		HollowClaim.deposit(own, "player 7", math.ceil(cap * ownAt), 1, cap, ownAt, margin)
		t.eq(svc:owner(ids[1]), "player 7")
		t.eq(other.brought["player 9"], 2)
		local gone = PlaceRelease.release("player 7", { hollows = svc })
		t.eq(gone.tree, ids[1])
		t.eq(svc:owner(ids[1]), nil, "freed")
		t.eq(svc:meter(ids[1]), 0, "its nuts went with its owner")
		t.eq(svc:heldBy("player 7"), nil)
		t.eq(other.brought["player 7"], nil)
		t.eq(other.brought["player 9"], 2, "another squirrel's part stays")
		t.eq(PlaceRelease.release("player 9", { hollows = svc }).tree, nil, "player 9 held none")
	end)
end
