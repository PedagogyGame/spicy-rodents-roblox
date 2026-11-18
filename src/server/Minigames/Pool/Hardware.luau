--!strict
-- ServerScriptService.Server.Minigames.Pool.Hardware
-- A cue-sport table's balls on the server (pool's two tables and the bumper pool table): the baked ball
-- Models under the table's Model (Shared/Minigames/Pool/Furniture names them: "CueBall", "Ball<id>"), set down
-- where the rules say they lie. The server never simulates a ball in the world: the rules run the table model
-- (Shared/Minigames/Pool) and every client plays the shot's script on these same parts; this module only
--   lays the table out from the game's state (a ball on the cloth at its spot; a ball that is down in its own
--     place in the tray, Furniture.home; a ball that is in neither out of sight inside the table);
--   shows a shot coarsely while it runs (SHOW times a second), so that somebody who only now walks in, or
--     whose client has no script, still sees balls on their way; and
--   turns each ball's number as its roll and spin say (Pool/Roll), ending where every client's own drawing
--     ends, so nothing jumps when the shot is over.
-- A table whose Model or balls are not there (another game's test site, a part of the building not built)
-- gives nil: the game then has no hardware and touches nothing.
-- Interface: new(opts { model, place, station, table }) -> Hardware?; Hardware:layout(spots, away?) (away:
--   ball ids kept out of sight, not in the tray); Hardware:show(script, t) (a shot in flight at time t);
--   Hardware:landed(script) (turn every ball's number on to the end of the shot); Hardware:fresh() (every ball
--   faces the way it was baked); Hardware:board(text) (the scoreboard beside the table, "ScoreBoard": its
--   TextLabels); Hardware:position(id) -> Vector3?; Hardware.ids; SHOW

local Import = require("../../Import")
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../../shared/Attractions/AlleyLayout"))
local Furniture =
	Import.shared("Minigames/Pool/Furniture") :: typeof(require("../../../shared/Minigames/Pool/Furniture"))
local Roll = Import.shared("Minigames/Pool/Roll") :: typeof(require("../../../shared/Minigames/Pool/Roll"))
local Shot = Import.shared("Minigames/Pool/Shot") :: typeof(require("../../../shared/Minigames/Pool/Shot"))

local Hardware = {}
Hardware.__index = Hardware

Hardware.SHOW = 10 -- times a second the server moves the balls of a shot in flight

function Hardware.new(opts: { [string]: any }): any
	local model = opts.model :: Instance?
	if model == nil then
		return nil
	end
	local tb = opts.table
	local ids: { number } = {}
	local balls: { [number]: Model } = {}
	local rots: { [number]: { number } } = {}
	for id = 0, 15 do
		local m = model:FindFirstChild(Furniture.ballName(id))
		if m and m:IsA("Model") then
			balls[id] = m
			rots[id] = Roll.identity()
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return nil
	end
	local self = setmetatable({}, Hardware) :: any
	self.model = model
	self.place = opts.place
	self.station = opts.station
	self.table = tb
	self.ids = ids
	self.balls = balls
	self.rots = rots
	self.yaw = CFrame.Angles(0, AlleyLayout.yawOf(opts.place), 0)
	-- the little scoreboard beside the table: every TextLabel under "ScoreBoard" (one on each face)
	self.labels = {} :: { TextLabel }
	local board = model:FindFirstChild("ScoreBoard")
	if board then
		for _, d in board:GetDescendants() do
			if d:IsA("TextLabel") then
				table.insert(self.labels, d)
			end
		end
	end
	self.shownAt = -1 -- the last coarse step shown of the shot in flight
	return self
end

-- A ball's Model at a table point (y is its centre above the cloth), facing the way its number has turned.
function Hardware._put(self: any, id: number, x: number, y: number, z: number)
	local m = self.balls[id] :: Model?
	if m == nil then
		return
	end
	local X, Y, D = Furniture.bed(self.station, x, z, y)
	local wx, wy, wz = AlleyLayout.toWorld(self.place, X, Y, D)
	local r = self.rots[id]
	m:PivotTo(
		CFrame.new(wx, wy, wz) * self.yaw * CFrame.new(0, 0, 0, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
	)
end

-- The table as the rules have it: every ball on the cloth at its spot, every other ball at home in the tray
-- (or, if `away` names it, out of sight inside the table: bumper pool's other five in practice, a cue ball
-- that went down and is not back yet).
function Hardware.layout(self: any, spots: { { id: number, x: number, z: number } }, away: { [number]: boolean }?)
	local r = self.table.ballR
	local on: { [number]: boolean } = {}
	for _, s in spots do
		on[s.id] = true
		self:_put(s.id, s.x, r, s.z)
	end
	for _, id in self.ids do
		if not on[id] then
			local x, y, z = Furniture.off(self.table, id, away ~= nil and away[id] == true)
			self:_put(id, x, y, z)
		end
	end
	self.shownAt = -1
end

-- A shot in flight, t seconds after the strike: its balls where the script has them (coarsely: clients draw
-- every frame from the same script and never see this).
function Hardware.show(self: any, script: any, t: number)
	local step = math.floor(math.max(0, t) * Hardware.SHOW)
	if step == self.shownAt then
		return
	end
	self.shownAt = step
	local r = self.table.ballR
	for i, id in script.ids do
		if #script.tracks[i] > 0 then
			local x, z, y = Shot.pose(script, i, t)
			self:_put(id, x, r + y, z)
		end
	end
end

function Hardware.landed(self: any, script: any)
	for i, id in script.ids do
		local r = self.rots[id]
		if r then
			Roll.final(r, script, i)
		end
	end
	self.shownAt = -1
end

function Hardware.fresh(self: any)
	for _, id in self.ids do
		self.rots[id] = Roll.identity()
	end
end

-- The scoreboard's words (every face of it).
function Hardware.board(self: any, text: string)
	for _, label in self.labels do
		label.Text = text
	end
end

function Hardware.position(self: any, id: number): Vector3?
	local m = self.balls[id] :: Model?
	return if m then m:GetPivot().Position else nil
end

return Hardware
