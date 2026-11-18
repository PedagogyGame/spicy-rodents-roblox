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
-- squirrel in the rafters over the lanes).
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
