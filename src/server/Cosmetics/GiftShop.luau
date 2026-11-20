--!strict
-- ServerScriptService.Server.Cosmetics.GiftShop
-- The bowling alley's gift shop sells its shirt (the one piece of clothing on sale today: Shared/Items/Clothing),
-- at the cash desk (tools/bake/alley/Shops: GiftShop.Desk). One prompt on the desk, E (a click, a tap, gamepad X):
--   not owned   buys it through the town's wallet (Economy/Credits.buy "alley_shirt": 10c, EconomyRules' price and
--               name) and hands it over to the Wardrobe, which puts it on and saves it (owner D16 #25: clothing
--               carries over between servers). Short of money: the wallet's words, nothing taken.
--   owned       puts it on, or takes it off if it is on (saved too).
-- Only a person shops (an animal is told so). A second press while one is being served is refused with words; a
-- press within COOLDOWN of the last one is ignored without words (a held E or an autoclicker does nothing more, and
-- each change is saved by PlayerSaves at most once every few seconds anyway).
-- The souvenirs (postcard, toy pin, mug) are not sold here yet; they would stay on the server, like every other item.
-- The prompt is made at boot on the baked desk (no bake change): 1 Attachment and 1 ProximityPrompt, no parts.
-- Interface: press(deps, player) -> (ok, words) (pure over deps); start(opts) -> Shop? (nil without the desk);
--   ITEM; WORDS; COOLDOWN
-- Engine only inside start; no side effects on require.

local GiftShop = {}

GiftShop.ITEM = "alley_shirt"
GiftShop.COOLDOWN = 0.5 -- seconds between one player's presses that count

GiftShop.WORDS = table.freeze({
	animal = "Only people shop here.",
	noBody = "Pick a person from the menu first (M).",
	busy = "One moment: still serving you.",
	paid = "%s It is yours on every server.",
	on = "You put on your alley shirt.",
	off = "You take off your alley shirt.",
})

export type Deps = {
	wallet: { buy: (player: any, id: string, deliver: () -> (boolean?, string?)) -> (boolean, string) },
	wardrobe: {
		owns: (self: any, player: any, id: string) -> boolean,
		worn: (self: any, player: any, slot: string) -> string?,
		give: (self: any, player: any, id: string) -> (boolean, string?),
		wear: (self: any, player: any, id: string) -> (boolean, string?),
		takeOff: (self: any, player: any, slot: string) -> string?,
	},
	speciesOf: (player: any) -> string?,
	present: (player: any) -> boolean,
	tell: (player: any, words: string) -> (),
	serving: { [any]: boolean }?,
	now: (() -> number)?, -- a clock for the press cooldown (os.clock); none: no cooldown
	lastPress: { [any]: number }?,
}

local function withNote(words: string, extra: string?): string
	return if extra then `{words} {extra}` else words
end

-- One press of the desk's prompt.
function GiftShop.press(d: Deps, player: any): (boolean, string)
	local function say(ok: boolean, words: string): (boolean, string)
		d.tell(player, words)
		return ok, words
	end
	local species = d.speciesOf(player)
	if species == nil then
		return say(false, GiftShop.WORDS.noBody)
	end
	if species ~= "human" then
		return say(false, GiftShop.WORDS.animal)
	end
	local serving = d.serving or {}
	d.serving = serving
	local key = player.UserId or player
	if d.now then
		local t = d.now()
		local presses = d.lastPress or {}
		d.lastPress = presses
		local last = presses[key]
		if last and t - last < GiftShop.COOLDOWN then
			return false, GiftShop.WORDS.busy -- (not said: a held E would only flood the screen)
		end
		presses[key] = t
	end
	if serving[key] then
		return say(false, GiftShop.WORDS.busy)
	end
	local id = GiftShop.ITEM
	if d.wardrobe:owns(player, id) then
		if d.wardrobe:worn(player, "shirt") == id then
			d.wardrobe:takeOff(player, "shirt")
			return say(true, GiftShop.WORDS.off)
		end
		local _, extra = d.wardrobe:wear(player, id)
		return say(true, withNote(GiftShop.WORDS.on, extra))
	end
	serving[key] = true
	local extra: string? = nil
	local ok, words = d.wallet.buy(player, id, function(): (boolean?, string?)
		if not d.present(player) then
			return false, "gone"
		end
		local given, note = d.wardrobe:give(player, id)
		extra = note
		return given
	end)
	serving[key] = nil
	if not ok then
		if d.present(player) then
			return say(false, words)
		end
		return false, words
	end
	-- (the wallet's "Paid 10c for an alley shirt. You have S$2.90.", then where it is kept)
	if extra then
		return say(true, withNote(words, extra))
	end
	return say(true, string.format(GiftShop.WORDS.paid, words))
end

export type Opts = {
	attractions: Instance?, -- Workspace.Attractions (the alley's bake)
	wallet: any,
	wardrobe: any,
	possession: any, -- Actors/Possession: actorOf(player) -> { species, body }
	tell: (player: any, words: string) -> (),
}

export type Shop = { prompt: ProximityPrompt, stop: () -> () }

function GiftShop.start(opts: Opts): Shop?
	local root = opts.attractions
	local shop = root and root:FindFirstChild("GiftShop", true)
	local desk = shop and shop:FindFirstChild("Desk")
	if not (desk and desk:IsA("BasePart")) then
		return nil
	end
	local att = Instance.new("Attachment")
	att.Name = "GiftShopPoint"
	att.Position = Vector3.new(0, desk.Size.Y / 2 + 0.6, 0) -- on the counter's top
	att.Parent = desk
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GiftShopPrompt"
	prompt.ActionText = "Alley shirt"
	prompt.ObjectText = "Gift shop: buy, put on or take off (10c)"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt:SetAttribute("Door", true) -- E belongs to the prompt, not to the vehicles (Client/Minigames/MinigameClient)
	prompt.Parent = att
	local Players = game:GetService("Players")
	local deps: Deps = {
		wallet = opts.wallet,
		wardrobe = opts.wardrobe,
		speciesOf = function(player: any): string?
			local a = opts.possession and opts.possession:actorOf(player)
			return if a and a.body then a.species else nil
		end,
		present = function(player: any): boolean
			return player.Parent == Players
		end,
		tell = opts.tell,
		serving = {},
		now = os.clock,
		lastPress = {},
	}
	local gone = Players.PlayerRemoving:Connect(function(player: Player)
		(deps.lastPress :: { [any]: number })[player.UserId] = nil
	end)
	local conn = prompt.Triggered:Connect(function(player: Player)
		local ok, err = pcall(function()
			GiftShop.press(deps, player)
		end)
		if not ok then
			warn(`[GiftShop] press failed: {err}`)
		end
	end)
	return {
		prompt = prompt,
		stop = function()
			conn:Disconnect()
			gone:Disconnect()
			att:Destroy()
		end,
	}
end

return GiftShop
