--!strict
-- ReplicatedStorage.Shared.Combat.PlayRules
-- The first playable build's combat rules (owner directive 2026-11-09; brief v2 §15 Power table via
-- Rodent/PowerRules): rodent and squirrel health, the townsperson kick, the rodent's bite on contact,
-- victims' mild shouts (brief v2 §15 mild rating), and the on-screen death messages. Deliberately
-- small: W2's CombatRules (pounce wind-up, bite chance, strikes, regen) replaces the bite and kick
-- maths behind the same calls. Pure (Lune-tested in tests/unit/play_rules.spec.luau).
-- Interface: HEALTH, KICK_DAMAGE, KICK_RANGE, KICK_COS, KICK_COOLDOWN, BITE_RANGE, BITE_HEIGHT,
--   BITE_COOLDOWN, SHOUTS, kickTarget(kicker, look, targets) -> id?, biteVictims(rodent, people, now,
--   last) -> { id }, damage(health, amount) -> (health, dead), shout(n) -> string,
--   deathMessage(cause) -> (title, line)

local Lines = require("../Speech/Lines")

export type Point = { id: any, x: number, y: number, z: number }

local PlayRules = {}

PlayRules.HEALTH = 100 -- rodent and squirrel (owner directive)
PlayRules.KICK_DAMAGE = 55 -- two kicks knock a rodent out
PlayRules.KICK_RANGE = 7 -- studs from the kicker's root to the target's root
PlayRules.KICK_COS = 0.2 -- the target must be in front (cosine of the half-angle, about 78 degrees)
PlayRules.KICK_HEIGHT = 5 -- studs: a squirrel up a tree is out of reach
PlayRules.KICK_COOLDOWN = 0.7 -- seconds between kicks
PlayRules.BITE_RANGE = 3.5 -- studs, horizontal, rodent root to person root
PlayRules.BITE_HEIGHT = 5 -- studs, vertical
PlayRules.BITE_COOLDOWN = 2.5 -- seconds before the same person can be bitten again

-- Mild lines only (brief v2 §15: v5.4's swearing is rewritten). The lines live with every other
-- spoken line in Speech/Lines (group "bitten"); the server picks the victim's bubble through
-- Speech/SpeechRules, and `shout(n)` stays for callers that want the plain cycle.
PlayRules.SHOUTS = Lines.GROUPS.bitten

-- The nearest target in front of the kicker within reach, or nil.
-- kicker: the kicker's root; look: the kicker's facing (x, z, need not be unit).
function PlayRules.kickTarget(kicker: Point, look: { x: number, z: number }, targets: { Point }): any?
	local lm = math.sqrt(look.x * look.x + look.z * look.z)
	if lm < 1e-6 then
		return nil
	end
	local lx, lz = look.x / lm, look.z / lm
	local best, bestD = nil, PlayRules.KICK_RANGE
	for _, t in targets do
		if t.id ~= kicker.id then
			local dx, dz = t.x - kicker.x, t.z - kicker.z
			local d = math.sqrt(dx * dx + dz * dz)
			local inFront = d < 1 or (dx * lx + dz * lz) / d >= PlayRules.KICK_COS
			if d <= bestD and inFront and math.abs(t.y - kicker.y) <= PlayRules.KICK_HEIGHT then
				best, bestD = t.id, d
			end
		end
	end
	return best
end

-- People the rodent bites this check: within reach and not bitten in the last BITE_COOLDOWN seconds.
-- `last` maps person id -> time of their last bite; it is updated for every victim returned.
function PlayRules.biteVictims(rodent: Point, people: { Point }, now: number, last: { [any]: number }): { any }
	local out = {}
	for _, p in people do
		if p.id ~= rodent.id then
			local dx, dz = p.x - rodent.x, p.z - rodent.z
			if
				dx * dx + dz * dz <= PlayRules.BITE_RANGE * PlayRules.BITE_RANGE
				and math.abs(p.y - rodent.y) <= PlayRules.BITE_HEIGHT
				and now - (last[p.id] or -math.huge) >= PlayRules.BITE_COOLDOWN
			then
				last[p.id] = now
				table.insert(out, p.id)
			end
		end
	end
	return out
end

-- New health after `amount` damage (never below 0) and whether it is a knock-out.
function PlayRules.damage(health: number, amount: number): (number, boolean)
	local h = math.max(0, health - amount)
	return h, h <= 0
end

-- The n-th shout (wraps), so a run of bites cycles through the lines.
function PlayRules.shout(n: number): string
	local list = PlayRules.SHOUTS
	return list[((math.floor(n) - 1) % #list) + 1]
end

-- The big on-screen message for a death (title, then one plain line).
function PlayRules.deathMessage(cause: string): (string, string)
	if cause == "traffic" then
		return "RUN OVER!", "A car got you. Pick a new body from the menu."
	elseif cause == "kick" then
		return "KICKED OUT!", "Two good kicks and you are out. Pick a new body from the menu."
	end
	return "KNOCKED OUT!", "Pick a new body from the menu."
end

return PlayRules
