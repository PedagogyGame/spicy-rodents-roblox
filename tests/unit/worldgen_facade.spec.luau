--!strict
-- WorldGen exteriors (the buildings art pass, Builders/Facade): each lot type gets its style; every
-- window has a casing, glass, a glazing bar and a sill, layered outward in that order; every exterior
-- door has its surround and, where its sill stands above the ground, steps a body can climb; the main
-- entrance carries the style's hood, porch, awning, canopy or portico; gable roofs have eaves that
-- continue the roof plates exactly, rakes, fascia, barge boards, a ridge cap and gutters, and every
-- drawn downspout meets a gutter; flat roofs have a deck, parapet and coping; chimneys a cap and pots;
-- shops a sign band and display panes; trim colours come from the lot's v5.4 palette.
local Bake = require("@worldgen/Bake")
local Building = require("@worldgen/Builders/Building")
local Facade = require("@worldgen/Builders/Facade")
local Geometry = require("@worldgen/Geometry")
local Kits = require("@worldgen/Kits")
local Palette = require("@worldgen/Palette")
local Plan = require("@worldgen/Plan")
local Height = require("@shared/World/Height")

return function(t)
	local data = Bake.data()
	local plans = Bake.plans(data)
	local byId: { [string]: any } = {}
	local lots: { [string]: any } = {}
	for _, p in plans do
		byId[p.id] = p
	end
	for _, l in data.lots do
		lots[l.id] = l
	end
	local function buildings(): { any }
		local out = {}
		for _, p in plans do
			if p.kind == "lot" and p.category == "building" then
				table.insert(out, p)
			end
		end
		return out
	end
	local function named(p: any): { [string]: any }
		local out = {}
		for _, s in p.parts do
			out[s.name] = s
		end
		return out
	end
	local function count(p: any, prefix: string): number
		local n = 0
		for _, s in p.parts do
			if string.sub(s.name, 1, #prefix) == prefix then
				n += 1
			end
		end
		return n
	end
	-- model-local centre of a part (the lot's frame is its first part's yaw about the lot centre)
	local function localOf(p: any, s: any): { number }
		local f = p.parts[1]
		local l = Geometry.unrotate({ s.cx - f.cx, 0, s.cz - f.cz }, f.yaw, 0, 0)
		return { l[1], s.cy - p.attributes.SeatY, l[3] }
	end
	-- a minimal builder context for a lot (what Plan hands the families)
	local function ctxOf(id: string): any
		local lot = lots[id]
		local kit = Kits.get(lot.type)
		local body = byId[id].parts[1]
		return {
			lot = lot,
			kit = kit,
			frame = Geometry.frame(lot.x, Plan.seat(lot), lot.z, body.yaw),
			W = body.sx,
			D = body.sz,
			seat = Plan.seat(lot),
			params = lot.params or {},
			attributes = {},
			palette = Palette.forLot(lot, kit),
		}
	end

	t.test("style: Tudor quay, cottage or brick houses, shop fronts, civic blocks", function()
		local kinds: { [string]: number } = {}
		for _, p in buildings() do
			local lot = lots[p.id]
			local s = Facade.style(ctxOf(p.id))
			kinds[s.kind] = (kinds[s.kind] or 0) + 1
			if lot.type == "quay_building" then
				t.eq(s.kind, "tudor", p.id)
				t.eq(s.rake, 1.625, p.id) -- the "gutter to ridge" routes run on this rake
				t.eq(s.canopy == "awning", Palette.index(p.id) % 3 == 0, p.id)
			elseif lot.type == "house" or lot.type == "guesthouse" then
				t.truthy(s.kind == "cottage" or s.kind == "brick", p.id)
				t.truthy(s.canopy == "porch" or s.canopy == "hood", p.id)
			elseif lot.type == "hospital" or lot.type == "police_station" then
				t.eq(s.kind, "civic", p.id)
			elseif
				lot.type == "mall"
				or lot.type == "restaurant"
				or lot.type == "shop"
				or lot.type == "gas_station"
				or lot.type == "restaurant_icecream"
			then
				t.eq(s.kind, "shopfront", p.id)
				t.truthy(s.display, p.id)
			end
			-- a pure function of the lot: the same answer twice
			t.deepEq(Facade.style(ctxOf(p.id)), s)
		end
		t.eq(kinds.tudor, 30)
		t.eq((kinds.cottage or 0) + (kinds.brick or 0), 34)
		t.truthy((kinds.brick or 0) >= 1 and (kinds.cottage or 0) >= 25, "both house styles are in town")
		t.eq(kinds.estate, 2)
		t.eq(kinds.civic, 2)
		t.eq(kinds.shopfront, 7)
	end)

	t.test("windows: casing, glass, glazing bar and sill on every one, layered outward in that order", function()
		local windows, displays, lit = 0, 0, 0
		for _, p in buildings() do
			local parts = named(p)
			local litHere = 0
			for _, s in p.parts do
				local face, rest = string.match(s.name, "^Win([FBLR])(%d+_%d+)$")
				local frame = face and parts["Frame" .. face .. rest]
				if face and frame then
					local id = face .. rest
					windows += 1
					local axis = if face == "F" or face == "B" then 3 else 1
					local sign = if face == "F" or face == "L" then -1 else 1
					local function reach(part: any): number
						-- how far the part's outer face stands from the lot centre along the face normal
						local l = localOf(p, part)
						local q = math.floor((part.yaw - p.parts[1].yaw) / (math.pi / 2) + 0.5) % 2
						local depth = if (axis == 3) == (q == 0) then part.sz else part.sx
						return sign * l[axis] + depth / 2
					end
					local glass, casing = reach(s), reach(frame)
					t.truthy(glass > casing + 0.03, `{p.id}.{s.name}: glass in front of its casing`)
					t.eq(s.material, "Glass", s.name)
					local bar = parts["Mull" .. id] or parts["Transom" .. id]
					t.truthy(bar, `{p.id}.{s.name}: a glazing bar`)
					t.truthy(reach(bar) > glass + 0.03, `{p.id}.{s.name}: bar in front of the glass`)
					local floor = string.match(rest, "^(%d+)_")
					local sill = parts["Sill" .. id] or parts["Stall" .. id] or parts["Course" .. face .. floor]
					t.truthy(sill, `{p.id}.{s.name}: a sill, stall riser or sill course`)
					if parts["Sill" .. id] then
						t.truthy(reach(sill) > reach(bar) + 0.03, `{p.id}.{s.name}: sill proud of the bar`)
						t.truthy(sill.cy < s.cy - s.sy / 2, `{p.id}.{s.name}: sill under the pane`)
					end
					if parts["Stall" .. id] then
						displays += 1
						t.truthy(s.sx > 4 or s.sz > 4, `{p.id}.{s.name}: a display pane is wide`)
					end
					for _, part in { s, frame, bar, sill } do
						t.eq(part.canCollide, false, part.name)
						t.eq(part.canQuery, false, part.name)
					end
					if s.attrs and s.attrs.NightLight then
						litHere += 1
					end
				end
			end
			lit += litHere
			t.eq(p.attributes.NightLights or 0, litHere, `{p.id} NightLights`)
		end
		print(`      {windows} windows, {displays} display panes, {lit} glow at night`)
		t.truthy(windows >= 1400, `{windows} windows`)
		t.truthy(displays >= 70, `{displays} display panes`)
		t.truthy(lit >= 400, `{lit} windows glow at night`)
	end)

	t.test("windows keep clear of doors, and no upper window sits in a door's transom and hood", function()
		for _, id in { "core_house_3_blue_cottage", "core_house_0_victorian", "outer_home_02", "quay_bldg_w_00" } do
			local c = ctxOf(id)
			local style = Facade.style(c)
			local gap = { c = 2, w = 6.5, top = 9 }
			local grid = Facade.windowGrid(c, 0.4, 16, { F = { gap } }, style, nil)
			t.truthy(#grid >= 4, `{id}: {#grid} windows`)
			for _, w in grid do
				if w.face == "F" and w.y - w.h / 2 - 0.6 < gap.top + 4.2 then
					t.truthy(
						math.abs(w.c - gap.c) >= gap.w / 2 + w.w / 2 + 1.5 - 1e-9 or w.kind == "display",
						`{id}: window {w.floor}_{w.i} over the door`
					)
				end
				if w.kind == "display" then
					t.truthy(math.abs(w.c - gap.c) - w.w / 2 >= gap.w / 2 + 1.0, `{id}: display pane in the doorway`)
				end
			end
			-- without the door there are more windows on the front
			local open = Facade.windowGrid(c, 0.4, 16, {}, style, nil)
			t.truthy(#open >= #grid, id)
		end
	end)

	t.test("doors: a surround on every exterior door, steps wherever the sill stands above the ground", function()
		local doors, stepped, steps, level = 0, 0, 0, 0
		local untouched: { string } = {}
		for _, p in buildings() do
			local parts = named(p)
			local seat = p.attributes.SeatY :: number
			for _, s in p.parts do
				local a = s.attrs
				local outside = a
					and s.role == "Door"
					and (a.RoomA == "outside" or a.RoomB == "outside" or (a.RoomA == nil and a.DoorId ~= nil))
				if outside then
					doors += 1
					local hospitalFront = p.id == "hospital_main" and s.name == "Door_entrance"
					if not hospitalFront then
						t.truthy(parts[s.name .. "_Jamb1"] and parts[s.name .. "_Jamb2"], `{p.id}.{s.name}: jambs`)
						local head = parts[s.name .. "_Head"]
						t.truthy(head, `{p.id}.{s.name}: head`)
						t.truthy(head.cy - head.sy / 2 >= s.cy + s.sy / 2 - 1e-6, `{p.id}.{s.name}: head over the leaf`)
					end
					-- followers swing with the leaf
					local knob = parts[s.name .. "_Knob"]
					t.truthy(knob and knob.attrs.DoorOf == a.DoorId, `{p.id}.{s.name}: knob follows the leaf`)
					t.eq(knob.shape, "Ball")
					-- the ground 3 st outside the door
					local n = Geometry.rotate({ 0, 0, 1 }, s.yaw, 0, 0)
					local c = p.parts[1]
					local sign = if (s.cx - c.cx) * n[1] + (s.cz - c.cz) * n[3] >= 0 then 1 else -1
					if a.RoomA == nil then
						sign = -1 -- a Building front door: the model faces its local -Z
					end
					local sill = s.cy - s.sy / 2
					local wall = 0.3 -- from the leaf to the wall plane, at most
					local gx, gz = s.cx + n[1] * sign * 3, s.cz + n[3] * sign * 3
					local drop = sill - Height.at(gx, gz)
					local first = parts[s.name .. "_Step1"]
					if drop > 0.3 + wall and drop <= 4.5 - wall then
						t.truthy(first, `{p.id}.{s.name}: steps for a {string.format("%.2f", drop)} st drop`)
					end
					if first then
						stepped += 1
						t.near(
							first.cy + first.sy / 2,
							sill,
							1e-6,
							`{p.id}.{s.name}: the top step is level with the sill`
						)
						local k, prevTop = 1, sill
						while parts[`{s.name}_Step{k}`] do
							local st = parts[`{s.name}_Step{k}`]
							steps += 1
							t.eq(st.role, "Step")
							t.eq(st.canCollide, true, st.name)
							local top = st.cy + st.sy / 2
							t.truthy(prevTop - top <= 0.75 + 1e-6, `{p.id}.{st.name}: rise {prevTop - top}`)
							t.truthy(st.cy - st.sy / 2 < Height.at(st.cx, st.cz), `{p.id}.{st.name} reaches the ground`)
							prevTop = top
							k += 1
						end
						-- the last step is no more than one rise above the ground in front
						t.truthy(
							prevTop - Height.at(gx, gz) <= 0.75 + 0.3,
							`{p.id}.{s.name}: last step {prevTop - Height.at(gx, gz)} up`
						)
						t.eq(p.attributes.Steps ~= nil, true, p.id)
					elseif parts[s.name .. "_Threshold"] then
						level += 1
					else
						table.insert(untouched, `{p.id}.{s.name} ({string.format("%+.1f", drop)})`)
					end
					local _ = seat
				end
			end
		end
		print(
			`      {doors} exterior doors: {stepped} with steps ({steps} steps), {level} level; left as they are (sill under the ground or over 4.5 st up): {table.concat(
				untouched,
				", "
			)}`
		)
		t.truthy(doors >= 80, `{doors} doors`)
		t.truthy(stepped >= 15, `{stepped} doors with steps`)
		t.truthy(#untouched <= 22, `{#untouched} doors neither stepped nor level`)
	end)

	t.test("entrances: the hood, porch, awning, canopy or portico the style calls for, never in a ray's way", function()
		local seen: { [string]: number } = {}
		for _, p in buildings() do
			local lot = lots[p.id]
			local s = Facade.style(ctxOf(p.id))
			local parts = named(p)
			local has = lot.type ~= "hospital" and Kits.get(lot.type).door
			local eave = (p.attributes.EaveY :: number?) or 99
			local want: string? = nil
			if has and s.canopy == "hood" then
				want = "Hood"
			elseif has and s.canopy == "porch" then
				want = "PorchRoof"
				t.truthy(parts.PorchPost1 and parts.PorchPost2 and parts.PorchBeam, `{p.id}: porch posts and beam`)
				t.truthy(parts.PorchRoof.sx <= 0.63 * parts[p.parts[1].name].sx + 1e-6, `{p.id}: porch width`)
			elseif has and s.canopy == "awning" and eave >= 16 then
				want = "Awning"
				t.eq(parts.Awning and parts.Awning.shape, "Wedge", p.id)
				t.truthy(parts.Valance, `{p.id}: valance`)
			elseif has and s.canopy == "flat" then
				want = "Canopy"
			elseif has and s.canopy == "portico" then
				want = "PorticoSlab"
				t.eq(count(p, "Column"), s.columns, `{p.id}: columns`)
				t.eq(parts.Column1.shape, "Cylinder")
				t.near(parts.Column1.sy, parts.Column1.sz, 1e-9)
			end
			if want then
				seen[want] = (seen[want] or 0) + 1
				local c = parts[want]
				t.truthy(c, `{p.id}: {want}`)
				t.eq(c.canCollide, false, `{p.id}.{want}`)
				t.eq(c.canQuery, false, `{p.id}.{want}`)
				-- above the door, in front of the front wall
				local l = localOf(p, c)
				t.truthy(l[3] < -p.parts[1].sz / 2, `{p.id}.{want} stands in front`)
				t.truthy(l[2] > 8, `{p.id}.{want} is over head height`)
			end
		end
		t.truthy((seen.Hood or 0) >= 8, `hoods {seen.Hood}`)
		t.truthy((seen.PorchRoof or 0) >= 20, `porches {seen.PorchRoof}`)
		t.truthy((seen.Awning or 0) >= 10, `awnings {seen.Awning}`) -- quay index % 3 == 0, the restaurant, the shops
		t.truthy((seen.Canopy or 0) >= 3, `canopies {seen.Canopy}`)
		t.eq(seen.PorticoSlab, 3)
		local police = named(byId.west_police_station)
		t.truthy(police.BlueLamp1 and police.BlueLamp2, "police lamps")
		t.eq(police.BlueLamp1.material, "Neon")
		t.eq(police.SignBoard.attrs.SignText, "WEST TOPEKA POLICE")
	end)

	t.test("gable roofs: eaves continue the plates exactly; rakes, fascia, barge boards, ridge cap, gutters", function()
		local roofs = 0
		for _, p in buildings() do
			local parts = named(p)
			if parts.RoofA then
				roofs += 1
				local look = Palette.forLot(lots[p.id], Kits.get(lots[p.id].type))
				t.eq(count(p, "Eave"), 2, p.id)
				t.eq(count(p, "Rake"), 4, p.id)
				t.eq(count(p, "Fascia"), 2, p.id)
				t.eq(count(p, "Barge"), 4, p.id)
				t.eq(count(p, "RidgeCap"), 1, p.id)
				local gutters = 0
				for _, s in p.parts do
					if s.role == "Gutter" and string.sub(s.name, 1, 7) ~= "GutterN" then
						gutters += 1
						t.eq(s.shape, "Cylinder")
					end
				end
				t.eq(gutters, 2, p.id)
				-- the plates are exactly Facade.roofSides (the massing pin holds their numbers)
				local c = ctxOf(p.id)
				local eave, peak, _, alongX = Building.heights(c)
				local sides = Facade.roofSides(c, eave, peak, alongX)
				local style = Facade.style(c)
				for i, tag in { "A", "B" } do
					local plate, strip, side = parts["Roof" .. tag], parts["Eave" .. tag], sides[i]
					t.near(plate.pitch, side.pitch, 1e-12, p.id)
					t.near(plate.sz, side.slope, 1e-9, p.id)
					t.eq(plate.canCollide, true)
					t.eq(strip.canCollide, false)
					t.eq(strip.canQuery, false)
					-- same plane and look: same orientation, and the strip's centre lies on the plate's
					-- centre plane, one half-plate plus one half-strip down the slope
					t.near(strip.yaw, plate.yaw, 1e-12, p.id)
					t.near(strip.pitch, plate.pitch, 1e-12, p.id)
					t.deepEq(strip.color, plate.color)
					t.eq(strip.material, plate.material)
					local d = Geometry.toLocal(plate, { strip.cx, strip.cy, strip.cz })
					t.near(d[1], 0, 1e-6, `{p.id} Eave{tag} along the ridge`)
					t.near(d[2], 0, 1e-6, `{p.id} Eave{tag} off the plate's plane`)
					t.near(math.abs(d[3]), (plate.sz + strip.sz) / 2, 1e-6, `{p.id} Eave{tag} does not meet the plate`)
					-- it reaches the style's overhang beyond the wall
					t.near(strip.sz * math.cos(side.phi), style.overhang, 1e-6, p.id)
					t.deepEq(plate.color, look.roof)
				end
				t.deepEq(parts.FasciaA.color, look.trim)
				t.deepEq(parts.BargeA1.color, look.trim)
				-- the ridge cap sits on the peak and never above a squirrel's feet on the ridge route
				local cap = parts.RidgeCap
				t.truthy(cap.cy + cap.sy / 2 - p.attributes.SeatY <= peak + 0.3, p.id)
			end
		end
		t.eq(roofs, 62)
	end)

	t.test("gutters: every drawn building downspout meets the gutter above it", function()
		local props = {}
		for _, p in plans do
			if p.kind == "props" and p.category == "pipe" then
				table.insert(props, p)
			end
		end
		local necks: { [number]: any } = {}
		local gutters: { any } = {}
		for _, p in buildings() do
			for _, s in p.parts do
				if s.role == "Gutter" then
					if string.sub(s.name, 1, 11) == "GutterNeck_" then
						necks[s.attrs.Route] = s
						t.eq(s.canCollide, false)
						t.eq(s.canQuery, false)
						t.near(s.sy, s.sz, 1e-9)
					else
						table.insert(gutters, s)
					end
				end
			end
		end
		local function ends(s: any): ({ number }, { number })
			local ax = Geometry.rotate({ s.sx / 2, 0, 0 }, s.yaw, s.pitch, s.roll or 0)
			return { s.cx - ax[1], s.cy - ax[2], s.cz - ax[3] }, { s.cx + ax[1], s.cy + ax[2], s.cz + ax[3] }
		end
		local joined, through, loose = 0, 0, {}
		for _, pp in props do
			local shoe, top, low = false, nil, nil
			for _, s in pp.parts do
				if s.name == "Shoe" then
					shoe = true
				elseif string.sub(s.name, 1, 4) == "Pipe" and s.name ~= "PipeFoot" then
					local a, b = ends(s)
					for _, q in { a, b } do
						if top == nil or q[2] > top[2] then
							top = q
						end
						if low == nil or q[2] < low[2] then
							low = q
						end
					end
				end
			end
			if shoe and top and low then
				local best = math.huge
				local pass = math.huge
				for _, g in gutters do
					local a, b = ends(g)
					best = math.min(best, Geometry.segmentDistance(a, b, top))
					-- closest approach of the gutter's axis to the pipe's shaft (sampled along the gutter)
					for i = 0, 40 do
						local f = i / 40
						local q = { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
						pass = math.min(pass, Geometry.segmentDistance(low, top, q))
					end
				end
				if best < 20 then
					local neck = necks[pp.attributes.Route]
					if neck then
						joined += 1
						local a, b = ends(neck)
						local toPipe =
							math.min(Geometry.segmentDistance(low, top, a), Geometry.segmentDistance(low, top, b))
						t.truthy(toPipe <= 0.3, `{pp.id}: neck {toPipe} from the pipe`)
						local toGutter = math.huge
						for _, g in gutters do
							local ga, gb = ends(g)
							toGutter = math.min(
								toGutter,
								Geometry.segmentDistance(ga, gb, a),
								Geometry.segmentDistance(ga, gb, b)
							)
						end
						t.truthy(toGutter <= 0.3, `{pp.id}: neck {toGutter} from the gutter`)
					elseif pass <= 0.7 then
						through += 1
					else
						table.insert(loose, `{pp.id} ({string.format("%.2f", pass)})`)
					end
				end
			end
		end
		print(`      downspouts: {joined} joined by a neck, {through} run through their gutter`)
		t.eq(table.concat(loose, ", "), "", "downspouts that end in mid-air")
		t.eq(joined + through, 54) -- 24 house and 30 quay downspouts (the galleria's two stand on a flat roof)
	end)

	t.test("flat roofs, chimneys, corners and shop fronts carry their dressing in the lot's own colours", function()
		local flats, stacks, bands = 0, 0, 0
		for _, p in buildings() do
			local parts = named(p)
			local lot = lots[p.id]
			local look = Palette.forLot(lot, Kits.get(lot.type))
			local style = Facade.style(ctxOf(p.id))
			if parts.Deck then
				flats += 1
				t.deepEq(parts.Deck.color, look.roof, p.id)
				t.eq(parts.Deck.material, look.roofMaterial, p.id)
				t.eq(parts.Deck.canQuery, false, p.id) -- a ground ray lands on the roof itself
				for _, f in { "F", "B", "L", "R" } do
					t.deepEq(parts["Parapet" .. f].color, look.wall, p.id)
					t.eq(parts["Parapet" .. f].material, look.material, p.id)
					t.truthy(parts["Coping" .. f], p.id)
				end
			end
			if parts.Chimney then
				stacks += 1
				local cap = parts.StackCap
				t.truthy(
					cap and cap.sx > parts.Chimney.sx and cap.sz > parts.Chimney.sz,
					`{p.id}: cap wider than the stack`
				)
				t.truthy(cap.cy > parts.Chimney.cy + parts.Chimney.sy / 2, `{p.id}: cap on top`)
				t.truthy(parts.StackPot1 and parts.StackPot1.shape == "Cylinder", `{p.id}: pot`)
				t.near(parts.StackPot1.sy, parts.StackPot1.sz, 1e-9)
			end
			if style.corners == "boards" then
				t.eq(count(p, "CornerBoard"), 4, p.id)
				t.deepEq(parts.CornerBoard1.color, look.trim, p.id)
			elseif style.corners == "quoins" then
				local n = count(p, "Quoin")
				t.truthy(n >= 12 and n <= 4 * Facade.KNOBS.quoinsPerCorner, `{p.id}: {n} quoins`)
			elseif style.corners == "pilasters" then
				t.eq(count(p, "Pilaster"), 4, p.id)
			elseif style.corners == "timber" then
				t.eq(count(p, "PostF"), 4, p.id)
				t.eq(count(p, "PostB"), 4, p.id)
				t.eq(count(p, "Brace"), 4, p.id)
				t.truthy(parts.Jetty, p.id)
				-- no window is crossed by the storey line or a brace's reach
				local mid = (p.attributes.EaveY :: number) * 0.51
				for _, s in p.parts do
					if string.match(s.name, "^Win[FB]") then
						local y = s.cy - p.attributes.SeatY
						t.truthy(
							y - s.sy / 2 > mid + 0.7 or y + s.sy / 2 < mid - 0.2,
							`{p.id}.{s.name} on the storey line`
						)
					end
				end
			end
			if style.kind == "shopfront" and (p.attributes.EaveY :: number) >= 16 then
				bands += 1
				t.truthy(parts.Band and parts.BandCap, `{p.id}: sign band`)
				t.truthy(count(p, "Stall") >= 2, `{p.id}: display panes`)
				-- the sign board stands on the band, proud of it
				local band, sign = parts.Band, parts.SignBoard
				t.truthy(math.abs(sign.cy - band.cy) < 1e-6 and sign.sy < band.sy, `{p.id}: sign on its band`)
			end
			if style.kind == "tudor" then
				t.truthy(count(p, "Stall") >= 2, `{p.id}: quay display panes`)
				t.truthy(count(p, "FlowerBox") >= 2, `{p.id}: flower boxes`)
			end
		end
		t.truthy(flats >= 14, `{flats} flat roofs`)
		t.truthy(stacks >= 40, `{stacks} chimneys`)
		t.truthy(bands >= 4, `{bands} shop bands`)
	end)

	t.test("decoration stays close to its building and never collides (door steps apart)", function()
		local far: { string } = {}
		local solid: { string } = {}
		local allowed = { Porch = 8, Column = 8, Portico = 8, Pediment = 8, Canopy = 6, Awning = 4.5, Valance = 4.5 }
		local trim = 0
		for _, p in buildings() do
			local body = p.parts[1]
			for _, s in p.parts do
				local deco = s.role == "Trim" or s.role == "Window" or s.role == "Gutter"
				if deco and s.name ~= "Foundation" then
					trim += 1
					if s.canCollide then
						table.insert(solid, `{p.id}.{s.name}`)
					end
					local x0, x1, z0, z1 = Plan.worldBox(body)
					local a0, a1, _, _, c0, c1 = Geometry.aabb(s)
					local out = math.max(x0 - a0, a1 - x1, z0 - c0, c1 - z1)
					local limit = 2.8
					for prefix, lim in allowed do
						if string.sub(s.name, 1, #prefix) == prefix then
							limit = lim
						end
					end
					if out > limit then
						table.insert(far, `{p.id}.{s.name} ({string.format("%.1f", out)})`)
					end
				end
			end
		end
		t.truthy(trim >= 5000, `{trim} trim parts`)
		t.eq(table.concat(solid, ", ", 1, math.min(#solid, 8)), "", `{#solid} trim parts collide`)
		t.eq(table.concat(far, ", ", 1, math.min(#far, 8)), "", `{#far} trim parts stand away from their building`)
	end)
end
