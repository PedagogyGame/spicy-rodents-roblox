--!strict
-- ServerScriptService.Server.Movement.BodyPin
-- The server's hands on a squirrel body for its validator (Movement/MovementService's Engine, wired by Boot/Game), and
-- the one rule about a body the server keeps until its driver's first packet passes the gate (MovementService's pin):
--   * while kept, the body's root carries attribute C.ATTR, and only the pin's own release (engine.pin(id, false),
--     called from MovementService's unpin and nowhere else) unanchors it or hands its physics to a player;
--   * every other server path that lets a body go asks first (letGo, giveTo): the validator's hold giving a body back
--     (here), the sky lift's ride end and its telescope's look (Rides/SkyLiftService). A body kept is left anchored and
--     the server's;
--   * a hold gives the body back only if it is still the same hand-off (actor.possessions), the same driver, the latest
--     hold, not riding and not kept: a hold's timer never undoes a pin taken since.
-- Bodies are anything with a PrimaryPart root (Anchored, SetNetworkOwner, Get/SetAttribute); tests drive fakes.
-- No side effects on require.
-- Interface: C; kept(root) -> boolean; pin(root); unpin(root, driver, riding) -> boolean; drop(root);
--   letGo(root, anchored) -> boolean; giveTo(root, player) -> boolean; engine(deps) -> Engine

local BodyPin = {}

BodyPin.C = table.freeze({
	ATTR = "MovePin", -- on the root while the server keeps the body for its validator (true)
	RIDE = "Ride", -- the body's attribute while it rides the sky lift (Rides/SkyLiftService): never handed back then
})
local C = BodyPin.C

-- kept(root): the server keeps this body for its validator (the pin); nothing but the pin's release lets it go
function BodyPin.kept(root: any): boolean
	if root == nil then
		return false
	end
	local ok, v = pcall(function(): any
		return root:GetAttribute(C.ATTR)
	end)
	return ok and v == true
end

-- pin(root): the server takes the body (its own, anchored, still) and marks it kept
function BodyPin.pin(root: any)
	pcall(function()
		root:SetAttribute(C.ATTR, true)
	end)
	pcall(function()
		if not root.Anchored then
			root:SetNetworkOwner(nil)
		end
	end)
	pcall(function()
		root.Anchored = true
	end)
	pcall(function()
		root.AssemblyLinearVelocity = Vector3.zero
	end)
end

-- unpin(root, driver, riding) -> handed back: the pin's own release. Not while the body rides (the lift keeps it; the
-- pin stays, and is released again once it is off), nor with no driver. The body unanchored and its physics the
-- driver's (a stub driver in the engine checks is no Player: the unanchored body only). An unanchoring that fails is
-- taken back (still kept).
function BodyPin.unpin(root: any, driver: any, riding: boolean): boolean
	if riding or driver == nil then
		return false
	end
	local ok = pcall(function()
		root:SetAttribute(C.ATTR, nil)
		root.Anchored = false
	end)
	if not ok then
		BodyPin.pin(root)
		return false
	end
	pcall(function()
		root:SetNetworkOwner(driver)
	end)
	return true
end

-- drop(root): the mark only (the body went back to the AI, which anchors it itself)
function BodyPin.drop(root: any)
	pcall(function()
		root:SetAttribute(C.ATTR, nil)
	end)
end

-- letGo(root, anchored) -> done: put the root's Anchored back as another path found it; a body kept stays anchored
function BodyPin.letGo(root: any, anchored: boolean): boolean
	if root == nil then
		return false
	end
	if not anchored and BodyPin.kept(root) then
		return false
	end
	return (pcall(function()
		root.Anchored = anchored
	end))
end

-- giveTo(root, player) -> done: hand the body's physics to a player; never a body kept
function BodyPin.giveTo(root: any, player: any): boolean
	if root == nil or BodyPin.kept(root) then
		return false
	end
	return (pcall(function()
		root:SetNetworkOwner(player)
	end))
end

-- the validator's hands (MovementService.Engine), over:
export type Deps = {
	-- the actor of an id and its driver (nil: the AI or none)
	heldBy: (actorId: any) -> (any?, any?),
	-- MovementService:isPinned: the validator still keeps the body
	isPinned: (actorId: any) -> boolean,
	-- put the body's feet at x, y, z (its facing kept)
	place: (body: any, x: number, y: number, z: number) -> (),
	-- tell the driver (Net "Correction")
	tell: (driver: any, msg: any) -> (),
	-- run fn after `seconds` (task.delay)
	delay: (seconds: number, fn: () -> ()) -> (),
}

local function riding(body: any): boolean
	local ok, v = pcall(function(): any
		return body:GetAttribute(C.RIDE)
	end)
	return ok and v ~= nil
end

function BodyPin.engine(deps: Deps): any
	local holds: { [any]: number } = {} -- actorId -> the latest hold's number (until it ends)
	local before: { [any]: boolean } = {} -- actorId -> whether the body was anchored before that run of holds
	local count = 0
	local function bodyOf(actorId: any): (any?, any?, any?, any?)
		local actor, driver = deps.heldBy(actorId)
		local body = if actor then actor.body else nil
		local root = if body then body.PrimaryPart else nil
		return actor, driver, body, root
	end
	return {
		-- on: the server takes a newly held squirrel (kept); off: hands it to its driver -> whether it did (false while it
		-- rides: the validator keeps it pinned and releases it again later). A body back with the AI loses the mark.
		pin = function(actorId: any, on: boolean): boolean
			local _actor, driver, body, root = bodyOf(actorId)
			if body == nil or root == nil then
				return not on
			end
			if on then
				BodyPin.pin(root)
				return true
			end
			if driver == nil then
				BodyPin.drop(root)
				return true
			end
			return BodyPin.unpin(root, driver, riding(body))
		end,
		correct = function(actorId: any, msg: any)
			local actor, driver, body = bodyOf(actorId)
			if actor == nil then
				return
			end
			if msg.snap and body then
				pcall(deps.place, body, msg.x, msg.y, msg.z)
			end
			if driver then
				deps.tell(driver, msg)
			end
		end,
		hold = function(actorId: any, x: number, y: number, z: number, seconds: number)
			local actor, driver, body, root = bodyOf(actorId)
			if actor == nil or body == nil or root == nil or driver == nil then
				return
			end
			-- (a hold over one not yet ended keeps that one's view of the body before: anchored by a hold is no "before")
			local wasAnchored = if holds[actorId] then before[actorId] == true else root.Anchored == true
			count += 1
			local mine = count
			holds[actorId] = mine
			before[actorId] = wasAnchored
			local token = actor.possessions
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
			pcall(function()
				root.Anchored = true
			end)
			pcall(deps.place, body, x, y, z)
			deps.delay(seconds, function()
				if holds[actorId] ~= mine then
					return -- (a later hold gives it back)
				end
				holds[actorId] = nil
				before[actorId] = nil
				local now, nowDriver = deps.heldBy(actorId)
				if
					now ~= actor
					or nowDriver ~= driver
					or actor.possessions ~= token
					or root.Parent == nil
					or riding(body)
					or deps.isPinned(actorId)
				then
					return -- (handed off since, riding, or kept by a pin: the hold has nothing to give back)
				end
				if BodyPin.letGo(root, wasAnchored) and not wasAnchored then
					BodyPin.giveTo(root, driver)
				end
			end)
		end,
	}
end

return BodyPin
