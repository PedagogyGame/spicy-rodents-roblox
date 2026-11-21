--!strict
-- ReplicatedStorage.Shared.Speech.Lines
-- Every short line a townsperson can say in a speech bubble, grouped by situation (owner 2026-11-10:
-- "make sure some of the people say, oh my god, its one of those squirrels again, and various other
-- phrases of concern"). Data only. The lines are mild rewrites of v5.4's (humans_actors §7.2-§7.4,
-- §11; hospital_police_infection §7.5): the only strong phrase allowed is "Oh my god" (brief v2 §15
-- mild rating; tests/unit/speech.spec.luau holds the banned-word list and the 60-character limit).
-- Situations: spotting (a person sees the Spicy Rodent or an infected squirrel), fleeing (running
-- from it), bitten (the victim, at the bite), witness (someone who saw a bite), bystander (in the
-- crowd at a scene), patient (the victim on the ground), symptoms (the delayed tell), crew (the
-- ambulance crew at the patient), cured (leaving the hospital), rafters (people in the bowling alley who notice a
-- squirrel in the rafters over the lanes), drain (someone who saw a squirrel go down a storm drain, BRIEF_ADDENDUM
-- D8), stakeout (the officer standing over the grate the rodent went down); overhead (a person in town who looks up
-- and sees a squirrel stalking above them on a wire, fence, branch or roof edge: Stealth/OverheadWatch, owner playtest
-- 2026-11-19), overheadUneasy (a creep lingering over them: they feel watched), overheadReply (the neighbour they told answers), overheadWary (keeping an eye on it: stepping back,
-- calling others over), overheadLost (it has gone from sight). The one who points it out names the place only when it
-- is so (review of the overhead watch, L5): overheadWire, overheadFence, overheadTree, overheadRoof by what it is on
-- (Server/Stealth/OverheadService.SURFACE), the plain "overhead" lines anywhere else; no line says how it moves.
-- An ordinary squirrel (owner D21, Server/Wildlife/TownSquirrels) frightens nobody: squirrelNear is the friendly word
-- someone now and then has for one going by; jumpedAt is the yelp of someone it jumped right on or at (a start, never
-- an alarm: no line calls anyone or tells anyone to run).
-- Interface: GROUPS { [situation]: { string } }; SITUATIONS { string } (stable order); THE_LINE;
--   all() -> { string }; of(situation) -> { string }
-- Pure. No side effects on require.

local Lines = {}

-- The line the owner asked for by name.
Lines.THE_LINE = "Oh my god, it's one of those squirrels again!"

Lines.GROUPS = table.freeze({
	spotting = table.freeze({
		Lines.THE_LINE,
		"Oh no! It's one of those squirrels!",
		"Is that squirrel... red?",
		"Look out! The spicy one is back!",
		"I told you about those squirrels!",
		"What is WRONG with that squirrel?!",
		"Everybody watch your ankles!",
	}),
	fleeing = table.freeze({
		"Run! Get inside!",
		"Nope. Nope. Nope!",
		"Not today, squirrel!",
		"Stay away from me!",
		"Somebody do something!",
	}),
	bitten = table.freeze({
		"Ow! Get off me!",
		"Yikes! A squirrel!",
		"Shoo! Shoo!",
		"My ankle!",
		"Somebody call the police!",
		"Not again!",
		"Why is it RED?!",
		"Help! Spicy rodent!",
	}),
	witness = table.freeze({
		"That squirrel just bit someone!",
		"Call an ambulance!",
		"Look out! Get inside!",
		"Get away from it!",
	}),
	bystander = table.freeze({
		"Somebody call an ambulance!",
		"Stay back, it might still be here!",
		"Is that another squirrel bite?",
		"Give them some room!",
		"Are they going to be okay?",
		"That's the third one this week!",
	}),
	patient = table.freeze({
		"Ow! My knee!",
		"Ohhh... that really hurts.",
		"I need a doctor!",
		"Somebody help me, please!",
	}),
	symptoms = table.freeze({
		"I don't feel so good...",
		"Why is everything so... spicy?",
		"I need to get to the hospital.",
		"My eyes are burning!",
	}),
	crew = table.freeze({
		"We are here. Give us some room, please.",
		"Can you hear me? Stay still.",
		"Keep the path clear, please.",
		"Off to the hospital with you.",
	}),
	cured = table.freeze({
		"I feel so much better!",
		"Good as new. Thank you, nurse!",
		"No more squirrels for me.",
	}),
	-- people in the bowling alley's lane hall who notice a squirrel in the rafters (Stealth/RafterWatch, addendum D9)
	rafters = table.freeze({
		"Is that a squirrel up there?",
		"There's a squirrel in the rafters!",
		"Look, up in the beams!",
		"Something's running across the ceiling!",
	}),
	drain = table.freeze({
		"Where did it go?",
		"Did that squirrel just go into the sewer?",
		"I am NOT following it down there.",
		"It's gone down a grate!",
	}),
	stakeout = table.freeze({
		"It went down the drain!",
	}),
	-- town people who look up and see a squirrel stalking overhead (Stealth/OverheadWatch; owner 2026-11-19: "awareness
	-- and discussion and chatter, if i ... am prowling and stalking from above on a powerline or branch")
	overhead = table.freeze({
		"Look! Up there!",
		"Wait, is that a squirrel up there?",
		"Don't look now, but there's a squirrel above us.",
		"That squirrel is following us...",
		"Why is that squirrel staring at me?",
		"Hey, is that the red one? Up there!",
	}),
	-- ... the same, on what it is on
	overheadWire = table.freeze({
		"Look! Up on the wire!",
		"Wait, is that a squirrel on the power line?",
		"There's a squirrel on the power line!",
		"Hey, is that the red one? On the wire!",
	}),
	overheadFence = table.freeze({
		"Up there! On the fence!",
		"There's a squirrel on that fence!",
		"Hey, is that the red one? On the fence!",
		"Look, on top of the fence!",
	}),
	overheadTree = table.freeze({
		"Hey, is that the red one? Up in the tree!",
		"There's a squirrel in that tree!",
		"Look! Up in the branches!",
		"Something's up in that tree...",
	}),
	overheadRoof = table.freeze({
		"Look! Up on the roof!",
		"There's a squirrel on that roof!",
		"Hey, is that the red one? On the roof!",
		"Up there, on the edge of the roof!",
	}),
	-- a creep lingering over them: they feel watched before they see anything
	overheadUneasy = table.freeze({
		"Did you hear something?",
		"Something's up there...",
		"I feel like I'm being watched.",
		"Was that a rustle up there?",
		"Hmm. Funny feeling about this street.",
		"Is something following us?",
	}),
	overheadReply = table.freeze({
		"Where? Oh! I see it.",
		"Don't make eye contact.",
		"It's just sitting there. Watching.",
		"Keep walking. Slowly.",
		"I'm not standing under that.",
		"Is it red? Please say it isn't red.",
		"Wow. It really is looking at us.",
	}),
	overheadWary = table.freeze({
		"Everybody, look up! Squirrel!",
		"Watch out below!",
		"Step back, folks. Give it room.",
		"I'm keeping my eye on you, squirrel.",
		"Come on down, I dare you.",
		"Stay out from under it!",
	}),
	overheadLost = table.freeze({
		"Where'd it go?",
		"It was right there a second ago.",
		"I lost it. Did you see where it went?",
		"Huh. Gone.",
		"Is it still up there somewhere?",
		"I don't see it anymore.",
	}),
	-- an ordinary squirrel going by: a friendly word now and then (owner D21: nobody runs from a regular squirrel)
	squirrelNear = table.freeze({
		"Aw, a squirrel.",
		"Hello, little one.",
		"Look at that fluffy tail!",
		"Busy day, squirrel?",
		"Cute little thing.",
		"Mind the road, little guy.",
		"Well, hello there.",
		"Off to find some acorns?",
	}),
	-- ... and one that jumped right on them or at them: a yelp, then they carry on
	jumpedAt = table.freeze({
		"Whoa!",
		"Yikes! You made me jump!",
		"Hey! Watch it, squirrel!",
		"Eek!",
		"Oh! Goodness, you startled me!",
		"Hey! Not on me!",
		"Whoa there, little guy!",
	}),
}) :: { [string]: { string } }

Lines.SITUATIONS = table.freeze({
	"spotting",
	"fleeing",
	"bitten",
	"witness",
	"bystander",
	"patient",
	"symptoms",
	"crew",
	"cured",
	"rafters",
	"drain",
	"stakeout",
	"overhead",
	"overheadWire",
	"overheadFence",
	"overheadTree",
	"overheadRoof",
	"overheadUneasy",
	"overheadReply",
	"overheadWary",
	"overheadLost",
	"squirrelNear",
	"jumpedAt",
})

function Lines.of(situation: string): { string }
	return Lines.GROUPS[situation] or {}
end

-- Every line, in situation order.
function Lines.all(): { string }
	local out = {}
	for _, s in Lines.SITUATIONS do
		for _, line in Lines.GROUPS[s] do
			table.insert(out, line)
		end
	end
	return out
end

return Lines
