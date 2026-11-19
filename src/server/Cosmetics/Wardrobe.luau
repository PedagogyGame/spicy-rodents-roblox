--!strict
-- ServerScriptService.Server.Cosmetics.Wardrobe
-- The clothing each player owns and has on (Shared/Items/Clothing: what counts as clothing), kept on this server
-- and saved between servers through Persistence/PlayerSaves (owner D16 #25: clothing carries over; everything else
-- a player buys stays on the server it was bought on, and money is not saved yet). It writes the profile's
-- `wardrobe` and `worn` and nothing else.
--   give(player, id)     a shop has been paid for a piece of clothing (inside wallet.buy's handing-over): it is the
--                        player's and goes on; saved as a purchase (at once when PlayerSaves' write gap and budget
--                        allow). Always true for clothing: a failing DataStore never undoes a purchase. The second
--                        return is what to add to the shop's words when it is not being saved (saving off, the
--                        profile not loaded yet, opened on another server).
--   wear(player, id) / takeOff(player, slot)    put on / take off an owned piece; the profile is marked dirty and
--                        PlayerSaves writes it within a few seconds (a burst of presses is one write).
--   loaded(player, data) PlayerSaves' hook: the saved wardrobe arrives; anything bought here before it did, and any
--                        slot changed here meanwhile, is merged in (true: data changed, save it).
--   sweep()              once a second: the clothes go on the body the player holds now (a shirt shows on a person;
--                        a squirrel keeps it in the wardrobe), and come off a body the player has left. Every body
--                        that changed hands is undressed before any is dressed, so a body handed from one wearer to
--                        another inside one sweep never takes the first wearer's colour as its own.
--   join(player)         a rejoin on this server: a worn choice changed here last time and never saved is dropped,
--                        so the saved choice (perhaps made on another server since) wins; owning only grows.
--   pending(player)      something bought or changed here is not in a profile yet (PlayerSaves' last look on leave).
-- A worn piece's look is its colour on the parts that show it: a rounded townsperson's parts tinted "shirt"
-- (Assets/PeopleArt's PeopleTint), else a stock body's UpperTorso; the old colour is put back when it comes off.
-- No parts are added (no triangles, no part count); a sweep reads one attribute per body part only when the body
-- or the clothes changed. The player attribute Clothes lists what is worn ("alley_shirt"), the body attribute
-- Wearing the same while it is on that body.
-- Interface: new(deps) -> Wardrobe; W:give(player, id) -> (ok, note?); W:wear(player, id) -> (ok, why?);
--   W:takeOff(player, slot) -> id?; W:owns(player, id) -> boolean; W:worn(player, slot) -> id?;
--   W:loaded(player, data) -> boolean; W:sweep(); W:join(player); W:leave(player); W:pending(player) -> boolean;
--   dress(body, def, rgb?) -> undo? (Instances);
--   WORDS
-- Engine only inside dress (Instances the caller hands in); no side effects on require.

local Import = require("../Import")
local Clothing = Import.shared("Items/Clothing") :: typeof(require("../../shared/Items/Clothing"))

type ClothingWardrobe = typeof(Clothing.empty())
type Def = typeof(Clothing.CATALOG[1])

export type Saves = {
	data: (self: any, player: any) -> any?, -- the profile while it is held, else nil
	dirty: (self: any, player: any, purchase: boolean?) -> (),
	status: (self: any, player: any) -> string?,
}

export type Deps = {
	saves: Saves,
	bodyOf: (player: any) -> (any?, string?), -- the body the player holds and its species
	players: () -> { any },
	rgb: ((r: number, g: number, b: number) -> any)?, -- (a Lune spec's Color3.fromRGB)
	setAttr: ((target: any, name: string, value: any) -> ())?,
}

type Entry = {
	w: ClothingWardrobe, -- this server's view (after a load: the saved one merged with this server's)
	boughtHere: { [string]: boolean }, -- every piece bought on this server (always merged: owning only grows)
	body: any?, -- the body dressed now
	look: string, -- what is on that body ("" for nothing)
	undo: (() -> ())?,
	boughtUnsaved: boolean, -- a purchase here not yet in a profile
	away: boolean, -- the player left this server (their entry is kept for a rejoin)
}

export type Wardrobe = {
	deps: Deps,
	entries: { [number]: Entry },
	give: (self: Wardrobe, player: any, id: string) -> (boolean, string?),
	wear: (self: Wardrobe, player: any, id: string) -> (boolean, string?),
	takeOff: (self: Wardrobe, player: any, slot: string) -> string?,
	owns: (self: Wardrobe, player: any, id: string) -> boolean,
	worn: (self: Wardrobe, player: any, slot: string) -> string?,
	loaded: (self: Wardrobe, player: any, data: any) -> boolean,
	sweep: (self: Wardrobe) -> (),
	join: (self: Wardrobe, player: any) -> (),
	leave: (self: Wardrobe, player: any) -> (),
	pending: (self: Wardrobe, player: any) -> boolean,
}

local Wardrobe = {}

-- added to a shop's words when the clothes are not being saved, by PlayerSaves' state
Wardrobe.WORDS = table.freeze({
	loading = "It is saved once your saved clothes load; until then it stays on this server.",
	unsaved = "It is saved once your saved clothes load; until then it stays on this server.",
	off = "Saving is off on this server, so it stays here.",
	lost = "It stays on this server (your clothes are open on another one).",
	corrupt = "It stays on this server (your saved clothes could not be read).",
} :: { [string]: string })

local function keyOf(player: any): number
	return player.UserId :: number
end

local function entryOf(self: Wardrobe, player: any): Entry
	local id = keyOf(player)
	local e = self.entries[id]
	if e == nil then
		e = {
			w = Clothing.empty(),
			boughtHere = {},
			body = nil,
			look = "",
			undo = nil,
			boughtUnsaved = false,
			away = false,
		}
		self.entries[id] = e
	end
	return e :: Entry
end

local function wornList(w: ClothingWardrobe): string
	local out = {}
	for _, slot in Clothing.SLOTS do
		local id = w.worn[slot]
		if id then
			table.insert(out, id)
		end
	end
	return table.concat(out, ",")
end

-- after any change: into the profile if it is held (marked dirty: PlayerSaves writes it within a few seconds; a
-- purchase sooner), else kept for the merge when it loads
local function changed(self: Wardrobe, player: any, e: Entry, purchase: boolean)
	local d = self.deps
	if d.setAttr then
		d.setAttr(player, "Clothes", wornList(e.w))
	end
	local data = d.saves:data(player)
	if data then
		Clothing.toSaved(e.w, data)
		table.clear(e.w.changed) -- in the profile now: nothing of this server's left to merge
		e.boughtUnsaved = false
		d.saves:dirty(player, purchase)
	elseif purchase then
		e.boughtUnsaved = true
	end
end

-- The note for a shop's words when this change is not being saved now (nil when it is).
local function note(self: Wardrobe, player: any): string?
	local state = self.deps.saves:status(player)
	if state == nil or state == "saved" then
		return nil
	end
	return Wardrobe.WORDS[state]
end

-- dress(body, def, rgb?): put a worn piece's look on a body; returns how to take it off again (the colours put
-- back). `rgb` makes the colour (default Color3.fromRGB; a Lune spec passes @lune/roblox's).
function Wardrobe.dress(body: any, def: Def, rgb: ((r: number, g: number, b: number) -> any)?): (() -> ())?
	local colour = def.color
	if colour == nil or body == nil then
		return nil
	end
	local parts: { any } = {}
	for _, d in body:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("PeopleTint") == def.slot then
			table.insert(parts, d)
		end
	end
	if #parts == 0 and def.slot == "shirt" then
		local torso = body:FindFirstChild("UpperTorso")
		if torso and torso:IsA("BasePart") then
			table.insert(parts, torso)
		end
	end
	if #parts == 0 then
		return nil
	end
	local was: { [any]: any } = {}
	local c: any = if rgb then rgb(colour[1], colour[2], colour[3]) else Color3.fromRGB(colour[1], colour[2], colour[3])
	for _, p in parts do
		was[p] = p.Color
		p.Color = c
	end
	body:SetAttribute("Wearing", def.id)
	return function()
		for p, old in was do
			if p.Parent ~= nil then
				p.Color = old
			end
		end
		if body:GetAttribute("Wearing") == def.id then
			body:SetAttribute("Wearing", nil)
		end
	end
end

-- what the body the player holds shows: the worn pieces its species shows, as one key ("" for none)
local function lookFor(w: ClothingWardrobe, species: string?): ({ Def }, string)
	local defs: { Def } = {}
	local ids: { string } = {}
	for _, slot in Clothing.SLOTS do
		local id = w.worn[slot]
		local d = if id then Clothing.def(id) else nil
		if d and species and d.species[species] then
			table.insert(defs, d)
			table.insert(ids, d.id)
		end
	end
	return defs, table.concat(ids, ",")
end

local function undress(e: Entry)
	if e.undo then
		pcall(e.undo :: () -> ())
	end
	e.undo, e.body, e.look = nil, nil, ""
end

function Wardrobe.new(deps: Deps): Wardrobe
	local self = { deps = deps, entries = {} } :: Wardrobe

	function self.give(me: Wardrobe, player: any, id: string): (boolean, string?)
		if not Clothing.isClothing(id) then
			return false, "not clothing"
		end
		local e = entryOf(me, player)
		e.w.owned[id] = true
		e.boughtHere[id] = true
		Clothing.wear(e.w, id)
		changed(me, player, e, true)
		return true, note(me, player)
	end

	function self.wear(me: Wardrobe, player: any, id: string): (boolean, string?)
		local e = entryOf(me, player)
		local ok, why = Clothing.wear(e.w, id)
		if not ok then
			return false, why
		end
		changed(me, player, e, false)
		return true, note(me, player)
	end

	function self.takeOff(me: Wardrobe, player: any, slot: string): string?
		local e = entryOf(me, player)
		local id = Clothing.takeOff(e.w, slot)
		changed(me, player, e, false)
		return id
	end

	function self.owns(me: Wardrobe, player: any, id: string): boolean
		local e = me.entries[keyOf(player)]
		return e ~= nil and Clothing.owns(e.w, id)
	end

	function self.worn(me: Wardrobe, player: any, slot: string): string?
		local e = me.entries[keyOf(player)]
		return if e then Clothing.wornIn(e.w, slot) else nil
	end

	function self.loaded(me: Wardrobe, player: any, data: any): boolean
		local e = entryOf(me, player)
		local saved = Clothing.fromSaved(data)
		local merged = Clothing.merge(saved, e.w)
		local differs = false
		for id in e.boughtHere do
			if not saved.owned[id] then
				differs = true
			end
			merged.owned[id] = true
		end
		if next(e.w.changed) ~= nil then
			differs = true
		end
		table.clear(merged.changed)
		e.boughtUnsaved = false
		e.w = merged
		if me.deps.setAttr then
			me.deps.setAttr(player, "Clothes", wornList(e.w))
		end
		if differs then
			Clothing.toSaved(e.w, data)
		end
		return differs
	end

	function self.sweep(me: Wardrobe)
		-- first every entry whose body or look changed comes off its old body, then the new looks go on: a body
		-- that changed hands has its own colours back before its new wearer's dress records them
		local moves: { { e: Entry, body: any?, defs: { Def }, look: string } } = {}
		for _, player in me.deps.players() do
			local e = me.entries[keyOf(player)]
			if e then
				local body, species = me.deps.bodyOf(player)
				local defs, look = lookFor(e.w, species)
				if body ~= e.body or look ~= e.look then
					undress(e)
					table.insert(moves, { e = e, body = body, defs = defs, look = look })
				end
			end
		end
		for _, m in moves do
			local e, body = m.e, m.body
			if body and #m.defs > 0 then
				local undos: { () -> () } = {}
				for _, d in m.defs do
					local ok, undo = pcall(Wardrobe.dress, body, d, me.deps.rgb)
					if ok and undo then
						table.insert(undos, undo)
					end
				end
				e.undo = function()
					for i = #undos, 1, -1 do
						undos[i]()
					end
				end
			end
			e.body, e.look = body, m.look
		end
	end

	function self.join(me: Wardrobe, player: any)
		local e = me.entries[keyOf(player)]
		if e and e.away then
			e.away = false
			table.clear(e.w.changed) -- (last visit's unsaved worn choice; what was bought here still merges)
		end
	end

	function self.pending(me: Wardrobe, player: any): boolean
		local e = me.entries[keyOf(player)]
		return e ~= nil and (e.boughtUnsaved or next(e.w.changed) ~= nil)
	end

	-- the player left: their clothes come off the body (the body goes back to the town); what they own stays known
	-- on this server for a rejoin, like their wallet
	function self.leave(me: Wardrobe, player: any)
		local e = me.entries[keyOf(player)]
		if e then
			undress(e)
			e.away = true
		end
	end

	return self
end

return Wardrobe
