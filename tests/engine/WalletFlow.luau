--!strict
-- ServerStorage.EngineTests.WalletFlow (CI place only; injected with --inject ci.project.json)
-- The town's wallet as a running game has it, as plain results (Server/Economy/Credits, wired by
-- Server/Boot/Game.wallet). One PlayerLike stub { UserId, Name, attrs, events } is taken through what every
-- shop, door and game will do with money:
--   pocket    arriving gives S$25.00 once (owner D31), and the balance is on the player for the screen (attrs.Cents)
--   a sale    12c for a coffee: ok and the words, the balance and the note beside it (attrs.CentsNote)
--   too dear  refused in words, and nothing moves
--   no price  a price that is nil is the shop's mistake: "That is not for sale yet.", nothing taken
--   the pass  bought once on the day clock: has, five days left, attrs.PassUntil, never sold twice
--   the games ctx.town.charge is the same money and ctx.town.pass the same pass (opts.town: a
--             MinigameService's `town`)
--   tell      a shop's words reach that player as the "notice" toast (the stub's events)
--   leaving   the account is closed and kept: nothing can be spent, and coming back gives nothing more
-- play() needs no engine, so the Lune suite runs this same flow first on the game's own wiring
-- (tests/isolated/wallet.luau: Game.wallet on the fake engine, with the real MinigameService's town); the
-- check is itself checked before a cloud run is spent on it. tests/engine/PlayBuild runs it on the booted game.
-- Interface: play(wallet, opts) -> Result { ok, failures, numbers }; opts = { player (a PlayerLike stub in
--   the game, with nothing spent yet), town? (MinigameService.town) }

local WalletFlow = {}

export type Opts = {
	player: any,
	town: any?,
}

function WalletFlow.play(wallet: any, opts: Opts): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: any, msg: string)
		if not cond then
			table.insert(failures, msg)
		end
	end
	local player = opts.player
	player.attrs = player.attrs or {}
	player.events = player.events or {}
	local attrs = player.attrs

	-- pocket money, once
	wallet.join(player)
	numbers.pocket = wallet.balance(player)
	-- owner D31: S$25.00 of pocket money, and prices x10
	check(numbers.pocket == 2500, `pocket money {tostring(numbers.pocket)} (want 2500)`)
	check(attrs.Cents == 2500, `Cents on the player {tostring(attrs.Cents)}`)
	check(wallet.join(player) == 0, "joining twice gave more pocket money")
	check(wallet.counted(player) == 0, `pocket money counts toward the queue ({tostring(wallet.counted(player))})`)

	-- a sale
	local paid, paidWords = wallet.spend(player, 12, "coffee")
	check(paid and paidWords == "Paid 12c for coffee. You have S$24.88.", `a coffee: {tostring(paidWords)}`)
	check(
		attrs.Cents == 2488 and string.match(tostring(attrs.CentsNote), "^%d+|%-12|coffee$") ~= nil,
		`the balance on the player did not follow ({tostring(attrs.Cents)}, {tostring(attrs.CentsNote)})`
	)

	-- a sale by id, as the shops sell (the list's price and the thing's name), handed over and then given back
	local served = false
	local byId, byIdWords = wallet.buy(player, "nachos", function(): (boolean?, string?)
		served = true
		return true
	end)
	check(byId and served and byIdWords == "Paid 50c for nachos. You have S$24.38.", `by id: {tostring(byIdWords)}`)
	wallet.add(player, 50, "nachos handed back")

	-- too dear, and a price that is missing
	local short, shortWords = wallet.spend(player, 10000, "a jet ski")
	check(not short and shortWords == "You need S$100.00; you have S$24.88.", `too dear: {tostring(shortWords)}`)
	local noPrice: any = nil
	local sold, soldWords = wallet.spend(player, noPrice, "lane shoes")
	check(not sold and soldWords == "That is not for sale yet.", `no price: {tostring(soldWords)}`)
	check(wallet.balance(player) == 2488, `a refusal moved the balance to {tostring(wallet.balance(player))}`)

	-- the pass, on the day clock
	local cents, days, offer = wallet.pass.offer()
	check(cents == 200 and days == 5 and type(offer) == "string", `the pass on offer: {tostring(offer)}`)
	check(not wallet.pass.has(player), "a pass before one was bought")
	local bought, boughtWords = wallet.pass.buy(player)
	check(bought and wallet.pass.has(player), `the pass: {tostring(boughtWords)}`)
	numbers.passDays = wallet.pass.left(player)
	check(math.abs(numbers.passDays - 5) < 0.01, `a new pass has {tostring(numbers.passDays)} days`)
	check(type(attrs.PassUntil) == "number", "no PassUntil on the player")
	local again, againWords = wallet.pass.buy(player)
	check(not again and againWords == "You already have a pass.", `a second pass: {tostring(againWords)}`)
	check(wallet.balance(player) == 2288, `after the pass {tostring(wallet.balance(player))}c (want 2288)`)

	-- the minigames' town is the same wallet
	local town = opts.town
	if town then
		local okC, wordsC = town.charge(player, 10000, "a game")
		check(
			not okC and wordsC == "You need S$100.00; you have S$22.88.",
			`ctx.town.charge is not the wallet: {tostring(wordsC)}`
		)
		local okT, wordsT = town.charge(player, 3, "a token")
		check(okT and wordsT == "Paid 3c for a token. You have S$22.85.", `ctx.town.charge: {tostring(wordsT)}`)
		check(town.pass == wallet.pass, "ctx.town.pass is not the wallet's pass")
		check(town.pass.has(player), "the games do not see the pass the wallet sold")
		wallet.add(player, 3, "a token handed back")
	end
	numbers.town = town ~= nil

	-- a shop's words, on that player's screen
	local before = #player.events
	wallet.tell(player, "The till is closed.")
	local last = player.events[#player.events]
	check(
		#player.events == before + 1
			and type(last) == "table"
			and last.kind == "notice"
			and last.text == "The till is closed.",
		"wallet.tell did not reach the player as a notice"
	)

	-- leaving and coming back
	wallet.leave(player)
	local gone, goneWords = wallet.spend(player, 1, "bubble gum")
	check(not gone and goneWords == "You have left the game.", `spent after leaving: {tostring(goneWords)}`)
	check(wallet.join(player) == 0, "coming back gave more pocket money")
	check(wallet.balance(player) == 2288, `back with {tostring(wallet.balance(player))}c (want 2288)`)
	check(wallet.pass.has(player), "the pass did not survive leaving and coming back")
	numbers.cents = wallet.balance(player)

	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

return WalletFlow
