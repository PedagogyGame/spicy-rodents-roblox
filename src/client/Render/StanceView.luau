--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.StanceView
-- How a person in the duel stands on this client (brief v2 §8; owner playtest 2026-11-18: the tough people should be
-- readable). The server writes one attribute on a person's body while they face the rodent, Stance
-- (Server/Combat/CombatService, Combat/Duel), and nothing otherwise; this module turns the R15's joints for it, on top
-- of whatever clip plays (each joint's C0 is turned, and put back exactly when the stance ends):
--   squared  a vigilante squaring up: both fists up in front, a step apart (the vigilante's tell: nobody else
--            stands like this)
--   guard    one forearm up across the body (backing off, or standing their ground)
--   windup   a kick or a swing coming: the right leg drawn back, the arms out for balance
--   flinch   both arms up over the face, the body leaning away
--   point    (the body's Gesture attribute, while no Stance is set: Server/Stealth/OverheadService) the right arm up and
--            forward, pointing at a squirrel overhead
--   flinch   also as a Gesture (Server/Wildlife/TownSquirrels: an ordinary squirrel jumped right on them or at them,
--            owner D21): the same start, for under a second
-- Nothing gory, no weapon: a stance. The bodies are R15s (the rounded townspeople keep the same Motor6Ds:
-- Assets/PeopleArt); a body without the joints is left as it is.
-- No service access at require time (Lune requires this module).
-- Interface: start(opts { bodies }) -> stop(); turns(stance) -> { [jointName]: { x, y, z } } (radians; pure);
--   effective(stance, gesture) -> pose (pure); JOINTS

local StanceView = {}

StanceView.JOINTS = table.freeze({ "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightHip", "LeftHip" })

-- the turn of each joint (about the joint's own axes; +x lifts an arm forward, -x draws a leg back)
local TURNS: { [string]: { [string]: { number } } } = {
	squared = {
		RightShoulder = { 1.25, 0, 0.25 },
		LeftShoulder = { 1.25, 0, -0.25 },
		RightElbow = { 1.1, 0, 0 },
		LeftElbow = { 1.1, 0, 0 },
		RightHip = { -0.15, 0, 0 },
		LeftHip = { 0.15, 0, 0 },
	},
	guard = {
		LeftShoulder = { 1.4, 0, -0.5 },
		LeftElbow = { 1.5, 0, 0 },
	},
	windup = {
		RightHip = { -0.6, 0, 0 },
		RightShoulder = { 0.3, 0, 0.6 },
		LeftShoulder = { 0.3, 0, -0.6 },
	},
	flinch = {
		RightShoulder = { 2.2, 0, -0.4 },
		LeftShoulder = { 2.2, 0, 0.4 },
		RightElbow = { 1.3, 0, 0 },
		LeftElbow = { 1.3, 0, 0 },
	},
	point = {
		RightShoulder = { 2.5, 0, 0.15 },
		RightElbow = { 0.15, 0, 0 },
	},
}

function StanceView.turns(stance: any): { [string]: { number } }
	return if type(stance) == "string" then (TURNS[stance] or {}) else {}
end

-- the pose a body shows: the duel's Stance, else its Gesture (a stance always wins): pointing, or a start
function StanceView.effective(stance: any, gesture: any): any
	if type(stance) == "string" then
		return stance
	end
	return if gesture == "point" or gesture == "flinch" then gesture else nil
end

type Entry = { body: Model, conn: RBXScriptConnection, conn2: RBXScriptConnection?, base: { [Motor6D]: CFrame } }

function StanceView.start(opts: { bodies: Instance }): () -> ()
	local entries: { [Instance]: Entry } = {}

	local function joint(body: Model, name: string): Motor6D?
		local j = body:FindFirstChild(name, true)
		return if j and j:IsA("Motor6D") then j else nil
	end

	local function apply(e: Entry)
		-- back to the clip's own frame first
		for j, c0 in e.base do
			j.C0 = c0
		end
		table.clear(e.base)
		local pose = StanceView.effective(e.body:GetAttribute("Stance"), e.body:GetAttribute("Gesture"))
		for name, r in StanceView.turns(pose) do
			local j = joint(e.body, name)
			if j then
				e.base[j] = j.C0
				j.C0 = j.C0 * CFrame.Angles(r[1], r[2], r[3])
			end
		end
	end

	local function add(child: Instance)
		if not child:IsA("Model") or entries[child] then
			return
		end
		local body = child :: Model
		local e: Entry = { body = body, conn = nil :: any, base = {} }
		e.conn = body:GetAttributeChangedSignal("Stance"):Connect(function()
			apply(e)
		end)
		e.conn2 = body:GetAttributeChangedSignal("Gesture"):Connect(function()
			apply(e)
		end)
		entries[child] = e
		if body:GetAttribute("Stance") ~= nil or body:GetAttribute("Gesture") ~= nil then
			apply(e)
		end
	end

	local function remove(child: Instance)
		local e = entries[child]
		if e then
			entries[child] = nil
			e.conn:Disconnect()
			if e.conn2 then
				e.conn2:Disconnect()
			end
			for j, c0 in e.base do
				j.C0 = c0
			end
		end
	end

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, opts.bodies.ChildAdded:Connect(add))
	table.insert(conns, opts.bodies.ChildRemoved:Connect(remove))
	for _, child in opts.bodies:GetChildren() do
		add(child)
	end
	return function()
		for _, c in conns do
			c:Disconnect()
		end
		for child in entries do
			remove(child)
		end
	end
end

return StanceView
