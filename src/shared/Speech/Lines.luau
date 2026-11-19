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
-- 2026-11-19), overheadReply (the neighbour they told answers), overheadWary (keeping an eye on it: stepping back,
-- calling others over), overheadLost (it has gone from sight).
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
		"Look! Up on the wire!",
		"Wait, is that a squirrel on the power line?",
		"Something's creeping along the power line.",
		"Don't look now, but there's a squirrel above us.",
		"Up there! On the fence!",
		"That squirrel is following us...",
		"Why is that squirrel staring at me?",
		"Hey, is that the red one? Up in the tree!",
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
		"Step back from the wire, folks.",
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
	"overheadReply",
	"overheadWary",
	"overheadLost",
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
