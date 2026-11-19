--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.DuelWords
-- What the rodent's player reads about the duel (Server/Combat/CombatService's "duel" events and Boot/Game's "hurt"),
-- short and mild (brief v2 §15). Every line says what happened and, where it helps, what to do instead.
-- Interface: news(what, zone) -> string? ; hurt(by) -> string (pure)
-- No side effects on require.

local DuelWords = {}

DuelWords.NEWS = table.freeze({
	batted = "Batted away! They saw you coming: catch them off guard, after a swing or mid-flinch.",
	batZone = "Batted away! Everyone here is on alert after that bite: get clear first.",
	missed = "Missed. Get closer before you pounce.",
	dodged = "Dodged it!",
	winded = "Too winded to feint: let the meter fill.",
	notyet = "Too soon: that lunge could not bite. Give each pounce a beat.",
}) :: { [string]: string }

function DuelWords.news(what: any, zone: boolean): string?
	if what == "batted" then
		return if zone then DuelWords.NEWS.batZone else DuelWords.NEWS.batted
	end
	return DuelWords.NEWS[what]
end

function DuelWords.hurt(by: any): string
	if by == "swing" then
		return "SWAT! You were knocked aside"
	elseif by == "baton" then
		return "WHACK! An officer's baton"
	end
	return "OUCH! You were kicked"
end

return DuelWords
