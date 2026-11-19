--!strict
-- A bought thing stays its buyer's (owner, D16 #26: "purchased items (unless otherwise specified) remain only in the
-- original buyer's inventory"): Server/Items/Lending's pure rules and Server/Items/ItemService's borrowed use.
--   pick-up: the buyer has it back, anyone else borrows it, nothing the store sells is finders-keepers
--   a loan ends when the buyer leaves, the borrower is gone, it is held holdSecs, or walked off past its reach
--   (60 studs from the buyer, or 20 past where it was picked up if that was further)
--   the ledger: a loan is its holder's and that item's only; taken once
--   ItemService: a borrowed thing is used only with its own loan's token, only thrown (back), and throwing it takes
--   nothing from anyone's inventory; the words are mild and short
local Lending = require("@server/Items/Lending")
local ItemRules = require("@shared/Items/ItemRules")
local ItemService = require("@server/Items/ItemService")
local Inventory = require("@server/Items/Inventory")

return function(t)
	t.test("pick-up: the buyer has it back, anyone else borrows it, nothing sold is finders-keepers", function()
		t.eq(Lending.pickUp(false, 11, 11), "own")
		t.eq(Lending.pickUp(false, 11, 12), "lend")
		t.eq(Lending.pickUp(true, 11, 12), "keep", "(a thing the game gave)")
		t.eq(Lending.pickUp(true, 11, 11), "own")
		for _, d in ItemRules.CATALOG do
			t.falsy(ItemRules.findersKeep(d.id), `{d.id} stays its buyer's`)
		end
	end)

	t.test("a loan ends: the buyer gone, the borrower gone, held too long, walked off with", function()
		local C = Lending.C
		t.eq(Lending.reach(30), C.walkOff)
		t.eq(Lending.reach(55), 55 + C.walkSlack, "picked up far off: some room to come back")
		t.eq(Lending.reach(nil), C.walkOff)
		local loan = Lending.ledger()
			.lend("sam", { item = "football", owner = "pip", ownerKey = 11, ownerName = "Pip" }, 100, 30)
		local here = { ownerHere = true, holderHere = true, dist = 30 }
		t.eq(Lending.due(loan, 100, here), nil)
		t.eq(Lending.due(loan, 100 + C.holdSecs - 0.1, here), nil)
		t.eq(Lending.due(loan, 100 + C.holdSecs, here), "idle")
		t.eq(Lending.due(loan, 101, { ownerHere = true, holderHere = true, dist = C.walkOff + 1 }), "walked")
		t.eq(Lending.due(loan, 101, { ownerHere = true, holderHere = true, dist = nil }), nil, "no body: not walked")
		t.eq(Lending.due(loan, 101, { ownerHere = true, holderHere = false, dist = 1 }), "holderGone")
		t.eq(Lending.due(loan, 101, { ownerHere = false, holderHere = false, dist = 1 }), "ownerGone", "first")
	end)

	t.test("the ledger: a loan is its holder's, for that item only, and taken once", function()
		local L = Lending.ledger()
		local thing = { item = "frisbee", owner = "pip", ownerKey = 11, ownerName = "Pip" }
		local a = L.lend("sam", thing, 0)
		local b = L.lend("kim", { item = "football", owner = "pip", ownerKey = 11, ownerName = "Pip" }, 0)
		t.truthy(a.token ~= b.token)
		t.truthy(L.holds("sam", "frisbee", a.token))
		t.falsy(L.holds("kim", "frisbee", a.token), "not Kim's")
		t.falsy(L.holds("sam", "football", a.token), "not that item")
		t.falsy(L.holds("sam", "frisbee", "1"), "a token is a number the server made")
		t.falsy(L.holds("sam", "frisbee", nil))
		t.eq(#L.of("sam"), 1)
		t.eq(#L.all(), 2)
		t.eq(L.take(a.token), a)
		t.eq(L.take(a.token), nil, "once")
		t.falsy(L.holds("sam", "frisbee", a.token))
	end)

	-- ItemService over a fake world: Sam holds a loan (token 5) of Pip's frisbee, and of a bubble wand (token 6)
	local function rig(): (any, any, { { [string]: any } }, { string }, any)
		local inv = Inventory.new()
		local acts: { { [string]: any } } = {}
		local refused: { string } = {}
		local clock = 100
		local sam = { UserId = 12 }
		local svc = ItemService.new({
			inventory = inv,
			now = function(): number
				clock += 10
				return clock
			end,
			pose = function(): ItemService.Pose?
				return { x = 0, y = 3, z = 0, lx = 0, lz = 1 }
			end,
			speciesOf = function(): string?
				return "human"
			end,
			night = function(): boolean
				return false
			end,
			zoneAt = function(): string?
				return nil
			end,
			nearby = function(): { ItemService.Target }
				return {}
			end,
			filter = function(_p: any, text: string): string?
				return text
			end,
			notify = function() end,
			refuse = function(_p: any, words: string)
				table.insert(refused, words)
			end,
			act = function(_p: any, e: { [string]: any }): boolean?
				table.insert(acts, table.clone(e))
				return true
			end,
			lent = {
				holds = function(p: any, id: string, token: any): boolean
					return p == sam and ((id == "frisbee" and token == 5) or (id == "bubbles" and token == 6))
				end,
			},
		})
		return svc, sam, acts, refused, inv
	end

	t.test("a borrowed thing: only with its own loan, only thrown back, nobody's inventory touched", function()
		local svc, sam, acts, refused, inv = rig()
		local ok, why = svc:use(sam, "frisbee")
		t.falsy(ok)
		t.eq(why, ItemService.WORDS.notOwned, "without the loan it is not his")
		ok, why = svc:use(sam, "frisbee", { lent = 4 })
		t.falsy(ok, "somebody else's loan")
		t.truthy(svc:use(sam, "frisbee", { lent = 5 }))
		t.eq(acts[1].kind, "throw")
		t.eq(acts[1].lent, 5, "the world is told which loan flies")
		t.eq(inv.count(sam, "frisbee"), 0)
		ok, why = svc:use(sam, "bubbles", { lent = 6 })
		t.falsy(ok)
		t.eq(why, "That is somebody else's: you can only throw it back.")
		t.eq(refused[#refused], why)
		-- with one of his own as well, his own throw is his own (no loan named): it leaves his inventory
		inv.add(sam, "frisbee")
		t.truthy(svc:use(sam, "frisbee"))
		t.eq(inv.count(sam, "frisbee"), 0)
		t.eq(acts[#acts].lent, nil)
	end)

	t.test("the words are mild and short", function()
		local all: { [string]: string } = table.clone(Lending.WORDS) :: any
		all.onlyThrow = ItemService.WORDS.onlyThrow
		for k, w in all do
			t.truthy(#w < 90, `{k} is short`)
			for _, bad in { "steal", "stole", "thief", "loser", "!!" } do
				t.falsy(string.find(string.lower(w), bad, 1, true), `{k}: {bad}`)
			end
		end
	end)
end
