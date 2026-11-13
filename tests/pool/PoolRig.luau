--!strict
-- tests/pool/PoolRig.luau: what the cue games' cases share on tests/lib/MinigameRig (pool and bumper pool): the
-- games room furnished with the tables' ball Models where the bake puts them (Shared/Minigames/Pool/Furniture,
-- at the stations Attractions/AlleyLayout names at run time: nothing here knows where a table stands), and a
-- player's hands: point the cue in the top view, set the tip on the cue-ball picture, pull the power bar, drag
-- the ball in hand, click a pocket. Everything goes through the real controller's mouse path, in the mouse's
-- own pixels, so a whole game played by a spec is played the way a person plays it.
-- ONLY IN AN ISOLATED RUN (it uses tests/lib/FakeEngine through the rig).
-- Interface: furnish(roots, places) (opts.furnish for MinigameRig.play); stand(stationId) -> opts.stand beside
--   that table; clock(w) (the playback's clock follows the rig's frames); controller(stationId) -> the
--   CueController; station(w, id) -> the service's station; state(w, id) -> the rules' state; ball(w, id,
--   ball) -> (x, z, y) of that ball's Model on this screen, in the table's frame (y above the cloth); top(w,
--   c) (the top view, settled); point(w, c, angle) (the cue pointed along `angle`); tip(w, c, x, y); pull(w,
--   c, power) (the bar pulled and let go: the strike); shoot(w, c, angle, power, tipX?, tipY?); carry(w, c, x,
--   z) (the ball in hand dragged there and set down); click(w, c, x, z) (a click on the table at that point);
--   play(w, c, inputs) (a list of { verb, args } as Pool/Computer gives them, played by hand); settle(w, id,
--   limit?) -> bool (run until no shot is in flight at that table and the client has caught up); board(w, id) ->
--   the scoreboard's words
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Furniture = require("@shared/Minigames/Pool/Furniture")
local Games = require("@shared/Minigames/Games")
local Tables = require("@shared/Minigames/Pool/Tables")
local CueController = require("@client/Minigames/Pool/CueController")
local Playback = require("@client/Minigames/Pool/Playback")
local FakeEngine = require("@tests/lib/FakeEngine")
local Rig = require("@tests/lib/MinigameRig")
local roblox = require("@lune/roblox")

local PoolRig = {}

local Kind = roblox.Enum.UserInputType
local Key = roblox.Enum.KeyCode

local function tableOf(game: string): Tables.Table
	return if game == "bumper_pool" then Tables.bumper() else Tables.eightBall()
end

-- The tables as the bake leaves them: a Model per station under GamesRoom, a Model per ball at its place on an
-- idle table, and a lamp over it.
function PoolRig.furnish(roots: { [string]: any }, places: { [string]: AlleyLayout.Place })
	local root = roots.bowling_alley
	local place = places.bowling_alley
	if root == nil then
		return
	end
	local room = root:FindFirstChild("GamesRoom")
	if room == nil then
		room = FakeEngine.new("Folder", "GamesRoom")
		room.Parent = root
	end
	local yaw = roblox.CFrame.Angles(0, AlleyLayout.yawOf(place), 0)
	for _, def in Games.stations({ bowling_alley = place }) do
		if def.game ~= "pool" and def.game ~= "bumper_pool" then
			continue
		end
		local tb = tableOf(def.game)
		local function at(x: number, y: number, z: number): any
			local wx, wy, wz = Furniture.world(place, def, x, y, z)
			return roblox.CFrame.new(wx, wy, wz) * yaw
		end
		local model = FakeEngine.model(Furniture.modelName(def.game, def.index), at(0, 0, 0), room)
		local spots = if def.game == "pool" then Tables.rack(1) else Tables.bumperStart()
		for _, s in spots do
			local ball = FakeEngine.model(Furniture.ballName(s.id), at(s.x, tb.ballR, s.z), model)
			ball.PrimaryPart = FakeEngine.part("Skin", at(s.x, tb.ballR, s.z), ball)
		end
		local lamp = FakeEngine.model("Lamp", at(0, Furniture.LAMP_Y, 0), model)
		FakeEngine.part("Shade", at(0, Furniture.LAMP_Y, 0), lamp)
		-- the scoreboard: a chalkboard with a label the server writes on
		local board = FakeEngine.model("ScoreBoard", at(0, 1, 0), model)
		local slate = FakeEngine.part("Board", at(0, 1, 0), board)
		local gui = FakeEngine.new("SurfaceGui", "Front")
		gui.Parent = slate
		local label = FakeEngine.new("TextLabel", "Score")
		label.Parent = gui
	end
end

function PoolRig.def(w: any, stationId: string): any
	return Games.station(stationId, { bowling_alley = w.places.bowling_alley })
end

-- Where a player walks up to a table: beside its long rail.
function PoolRig.stand(stationId: string, place: AlleyLayout.Place?): { site: string, x: number, y: number, d: number }
	local p: AlleyLayout.Place = place or { x = 0, z = 0, floorY = 0, yaw = 0 }
	local def = Games.station(stationId, { bowling_alley = p }) :: any
	local hw = Furniture.outer(tableOf(def.game))
	return { site = "bowling_alley", x = def.x - hw - 2, y = 3, d = def.d }
end

-- The playback draws by the rig's own frames (a spec's seconds are frames / 60).
function PoolRig.clock(w: any)
	Playback.clock = function(): number
		return w.frames / 60
	end
end

function PoolRig.controller(stationId: string): any
	return CueController.live[stationId]
end

function PoolRig.station(w: any, stationId: string): any
	return w.svc.stations[stationId]
end

function PoolRig.state(w: any, stationId: string): any
	local s = w.svc:sessionOf(stationId)
	return s and s.game and s.game.state
end

-- A ball's Model as this screen has it, in the table's frame: x, z, and its centre's height above the cloth.
-- What the scoreboard beside the table says.
function PoolRig.board(w: any, stationId: string): string
	local def = PoolRig.def(w, stationId)
	local room = w.roots.bowling_alley:FindFirstChild("GamesRoom")
	local model = room:FindFirstChild(Furniture.modelName(def.game, def.index))
	local board = model:FindFirstChild("ScoreBoard")
	local slate = board:FindFirstChild("Board")
	return slate:FindFirstChild("Front"):FindFirstChild("Score").Text
end

function PoolRig.ball(w: any, stationId: string, ball: number): (number, number, number)
	local def = PoolRig.def(w, stationId)
	local at = Playback.ballAt(def, ball)
	assert(at, `no ball {ball} at {stationId}`)
	local x, y, z = Furniture.fromWorld(w.places.bowling_alley, def, at.X, at.Y, at.Z)
	return x, z, y
end

local function mouseTo(x: number, y: number)
	FakeEngine.uis().mouse = roblox.Vector2.new(x, y)
	FakeEngine.input("changed", { UserInputType = Kind.MouseMovement })
end

-- The pixel a table point is drawn at, on the camera as it stands this frame.
local function pixelOf(c: any, x: number, z: number): (number, number)
	local wx, wy, wz = Furniture.world(c.place, c.def, x, c.tb.ballR, z)
	local p = workspace.CurrentCamera:WorldToViewportPoint(roblox.Vector3.new(wx, wy, wz))
	return p.X, p.Y
end

-- The top view, and a few frames for the camera to come to rest in it.
function PoolRig.top(w: any, c: any)
	if not c.top and c.phase ~= "place" then
		Rig.key(Key.T, true)
		Rig.key(Key.T, false)
	end
	Rig.run(w, 0.5)
end

-- Point the cue along `angle`: a click on the cloth in the top view, far enough from every pocket and ball
-- that it is only a pointing.
function PoolRig.point(w: any, c: any, angle: number)
	PoolRig.top(w, c)
	local s = c.byId[c.sel]
	assert(s, "no ball to point from")
	local dx, dz = math.sin(angle), math.cos(angle)
	local reach = 0.6
	for _, far in { 2.5, 1.8, 1.2, 0.6, 3.5, 5 } do
		local x, z = s.x + dx * far, s.z + dz * far
		local clear = true
		for _, hole in c.tb.holes do
			if (hole.x - x) ^ 2 + (hole.z - z) ^ 2 < (CueController.POCKET_REACH + 0.1) ^ 2 then
				clear = false
			end
		end
		for _, o in c.spots do
			if o.id ~= c.sel and (o.x - x) ^ 2 + (o.z - z) ^ 2 < (CueController.BALL_REACH + 0.1) ^ 2 then
				clear = false
			end
		end
		if clear then
			reach = far
			break
		end
	end
	local px, py = pixelOf(c, s.x + dx * reach, s.z + dz * reach)
	mouseTo(px, py)
	Rig.mouse(true)
	Rig.mouse(false)
end

-- The tip, set on the cue-ball picture.
function PoolRig.tip(_w: any, c: any, x: number, y: number)
	local ax, ay, as = c:pad()
	local reach = as / 2 - as * 0.16 / 2
	mouseTo(ax + as / 2 + x * reach, ay + as / 2 - y * reach)
	Rig.mouse(true)
	Rig.mouse(false)
end

-- The power bar pulled down to `power` and let go: the strike.
function PoolRig.pull(w: any, c: any, power: number)
	local sx, sy, sw, sh = c:strip()
	mouseTo(sx + sw / 2, sy + 4)
	Rig.mouse(true)
	Rig.frame(w)
	mouseTo(sx + sw / 2, sy + 4 + power * sh)
	Rig.frame(w)
	Rig.mouse(false)
end

function PoolRig.shoot(w: any, c: any, angle: number, power: number, tipX: number?, tipY: number?)
	PoolRig.point(w, c, angle)
	if (tipX or 0) ~= c.tipX or (tipY or 0) ~= c.tipY then
		PoolRig.tip(w, c, tipX or 0, tipY or 0)
	end
	Rig.frame(w)
	PoolRig.pull(w, c, power)
end

-- The ball in hand dragged to (x, z) and let go there (the place phase shows the top view by itself).
function PoolRig.carry(w: any, c: any, x: number, z: number)
	Rig.run(w, 0.5)
	local hand = c.hand
	assert(hand, "the cue ball is not in hand")
	local px, py = pixelOf(c, hand.x, hand.z)
	mouseTo(px, py)
	Rig.mouse(true)
	Rig.frame(w)
	px, py = pixelOf(c, x, z)
	mouseTo(px, py)
	Rig.frame(w)
	Rig.mouse(false)
	Rig.frame(w)
end

function PoolRig.click(w: any, c: any, x: number, z: number)
	local px, py = pixelOf(c, x, z)
	mouseTo(px, py)
	Rig.mouse(true)
	Rig.mouse(false)
	Rig.frame(w)
end

-- A turn's inputs as Pool/Computer gives them ({ verb, args }), played by hand.
function PoolRig.play(w: any, c: any, inputs: { { verb: string, args: { any } } })
	for _, input in inputs do
		local a = input.args
		if input.verb == "place" then
			PoolRig.carry(w, c, a[1], a[2])
			Rig.key(Key.Space, true)
			Rig.key(Key.Space, false)
			Rig.frame(w)
		elseif input.verb == "call" then
			local hole = c.tb.holes[a[1]]
			PoolRig.top(w, c)
			PoolRig.click(w, c, hole.x, hole.z)
		elseif input.verb == "shoot" then
			if c.mode.game == "bumper_pool" then
				if c.sel ~= a[1] then
					local s = c.byId[a[1]]
					PoolRig.top(w, c)
					PoolRig.click(w, c, s.x, s.z)
				end
				PoolRig.shoot(w, c, a[2], a[3], a[4], a[5])
			else
				if c.phase == "place" then
					Rig.key(Key.Space, true)
					Rig.key(Key.Space, false)
					Rig.frame(w)
				end
				PoolRig.shoot(w, c, a[1], a[2], a[3], a[4])
			end
		end
	end
end

-- Run until no shot is in flight at the table, on the server or on this screen.
function PoolRig.settle(w: any, stationId: string, limit: number?): boolean
	local st = PoolRig.station(w, stationId)
	Rig.run(w, 0.2)
	return Rig.untilTrue(w, limit or 45, function()
		return st.tbl.pending == nil and not Playback.playing(stationId)
	end)
end

return PoolRig
