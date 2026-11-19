# Clothing carries over between servers: what is saved, and how to check it (15 minutes)

You said (19 November, #25): "Clothing carries over between servers; all other items stay in the current server only." This is now built. Until now the game saved nothing between visits. Now it saves your clothing, and nothing else.

Everything below has been tested without a screen, including failing saves, two servers at once and a server shutting down. Nobody has tried it in Roblox yet.

## What counts as clothing
| Item | Where it is sold | Saved between servers? |
|---|---|---|
| **Alley shirt** (10c, a navy shirt) | The bowling alley's gift shop, at the cash desk | **Yes**, and whether you have it on |
| **Paintball gear** (100c) | The paintball lobby's gear counter, which is not built yet | **Yes**, once the counter sells it |
| The sewer fashion stand's hats, jackets and trousers | Not built yet | **Yes**, once it is built (the stand will use the same wardrobe) |

**Not clothing, so they stay on the server where they were bought:**
- **Lane shoes:** rented and handed back at the shoe desk, so you never own them.
- **The gift shop's souvenirs:** the postcard, the toy pin and the mug.
- **All 22 corner-store items:** this includes the umbrella, which you hold rather than wear.
- **Food, drinks, the bowling ball, rides and the pass.**
- **Money.**

Two more things are not saved by the game, because they are not yours to buy:
- **Your own Roblox avatar.** The game reads it again every time you join.
- **The townspeople's work clothes.** These belong to the person you are playing, not to you.

## What is saved
- **Two things only:** the clothing you own, and what you are wearing.
- **When it is saved:** the moment you buy, put on or take off a piece; every 30 seconds while you play; when you leave; and when the server shuts down.
- **One server at a time:** your saved clothes are locked to the server you are on. If you hop to a new server before the old one has let go, the new one waits a moment and then tries again on its own. Anything you buy in the meantime is added when your saved clothes arrive.

## Money is not saved (your call)
Your money still lasts only as long as the server does, as you asked. The **Spicy buck** you set up on 19 November (4 S$ per Robux) stays switched off until money is saved too. Nobody can buy it before then, so nothing paid for in Robux can be lost. **Tell me when you want money saved,** and I will add it to the same profile.

## When saving goes wrong
Play never stops or waits for saving, and nothing you have bought is ever taken back.

| What goes wrong | What you see |
|---|---|
| Your saved clothes do not load (Roblox's saving service is down or slow) | "Your saved clothes have not loaded yet. Play on: we keep trying, and nothing you buy is lost." The game tries again after 15 s, then 30 s, then 60 s, and so on (at most every 4 minutes) for as long as you stay. When it works: "Your saved clothes are back." |
| A save fails | "Saving your clothes is slow right now. ..." The game tries again every 30 s. When it works: "Your clothes are saved." |
| Another server took your saved clothes (only after a server freezes for minutes) | "Your clothes were opened on another server, so changes made here stay on this server." The old server never writes over the new one. |
| Your saved clothes are from a newer version of the game, or damaged | "Your saved clothes could not be read on this server. They are left as they were." The game never writes over them. |
| No saving at all (Studio without API access) | Nothing on screen. The Output says saving is off. A purchase says "Saving is off on this server, so it stays here." |

## How to check it in Studio
**First, turn saving on for Studio:** Home > Game Settings > Security > **Enable Studio Access to API Services**, then Save. Without this, Studio cannot save anything (Roblox's rule), and the game says so in the Output. Studio uses the same saved data as the live game, so the shirt you buy in Studio is really yours in the live game too.

| # | What to try | What you should see |
|---|---|---|
| 1 | Press Play, pick a person, and walk into the bowling alley's lobby. Go into the gift shop (the glass shopfront marked GIFT SHOP) and press **E** at the cash desk (**Alley shirt**) | "Paid 10c for an alley shirt. You have S$2.90. It is yours on every server." The shirt on your person turns navy. Your money drops by 10c, once |
| 2 | Press **E** at the desk again, and then once more | "You take off your alley shirt." and then "You put on your alley shirt." Each time is free |
| 3 | In the Explorer, select your player under Players and look at its Attributes | **ClothesSaved** = `saved`, and **Clothes** = `alley_shirt` while you have it on |
| 4 | Pick another person from the menu (M) | The shirt moves with you to the new person, and the first person's shirt goes back to its own colour |
| 5 | Pick a squirrel | The squirrel shows no shirt, but you still own it. Pick a person again and it is back on |
| 6 | Stop, then Play again | Your person has the navy shirt on straight away, and **Clothes** = `alley_shirt`. Your money is back to the pocket money: money is not saved |
| 7 | Buy something at the corner store, then stop and Play again | It is gone: only clothing carries over |
| 8 | Turn API access off, then Play | Everything still works. **ClothesSaved** = `off`, and the Output says "saving is off on this server". Buying the shirt says "Saving is off on this server, so it stays here." |

## What it costs
- **No parts and no triangles.** The shirt colours parts the body already has.
- **One prompt** on the gift shop's desk.
- **About once a second:** a cheap check of each player's body, which only does real work when the body or the clothes change.
- **Roblox's saving service:** one read when you join, one write when you change clothes, one every 30 seconds, and one when you leave. That is well inside Roblox's limits.

## Your choices (the defaults stay unless you say)
1. **The shirt's look.** It is a plain navy shirt, the colour of the alley's counters. It shows only on people: squirrels and the rodent wear no clothes. Do you want a printed design, or something squirrels can wear?
2. **What the gift shop sells.** It sells only the shirt for now. Should the souvenirs (postcard, toy pin and mug, each with its price) be on sale too? They would stay on the server where they were bought, like every other item.
3. **Saving money.** Say when, and the Spicy buck can go live at the same time.
