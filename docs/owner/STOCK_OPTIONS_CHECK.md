# Spicy Stock Options: how buying and withdrawing work, and what you need to do on Roblox (20 minutes)

You said (22 November, D30): "purchasing spicy bucks ... will be spicy stock options, and those will equate to 1 spicy buck, when taken out, players can access their computers at home, to withdraw 100 spicy bucks per server experience maximum from their purchased total spicy bucks via spicy stock options."

This is now built. Every buying and withdrawing case has been tested without a screen, including failed saves, the same purchase arriving twice, and a purchase arriving on a different server. Nobody has tried it in Roblox yet, and no real purchase has been made.

## What a player buys
- **What it is:** your existing developer product (id 3730438620) now sells **Spicy Stock Options**.
- **The rate:** 4 options for every Robux paid, as you set on 19 November (4 S$ per Robux).
- **What one option is worth:** 1 option = S$1.00 to spend in the game.
- **The price:** the game works out the options from what each purchase actually cost. If you change the price on the Creator Hub, the number of options changes with it, and nothing in the game needs editing.
- **Saved for good:** options are kept in the player's saved profile (the same one that saves clothing). They carry over to every server and every visit.
- **No real value:** options are play money for this game only. They cannot be cashed out, sold or traded.

## Where to buy
- **The menu (M):** a **Stock options** button at the bottom right of the menu opens a screen with:
  - what options are, in plain words;
  - how many the player has saved;
  - how much they can still withdraw on this server;
  - which house is their home;
  - a **Buy with Robux** button;
  - a **Show my home** button (puts a HOME marker over the house for a minute, because the town has no compass).
- **The Roblox purchase window** shows the price. The screen also says what one purchase gives: "One purchase: 25 Robux for 100 options".
- **The banks:** the banks being built alongside this can open the same purchase window.

## Homes and home computers
- **Every player gets a home** the first time they walk the town as a person. It is whichever of the town's four furnished houses is nearest to where they first appear:
  - the Victorian house;
  - the bungalow;
  - the brick house;
  - the blue cottage.
- **One home per server:** the home stays the same for as long as the server runs, even if the player leaves and comes back. A new server gives a new home.
- **Sharing:** several players can share a house. Its one computer shows each of them their own options.
- **The computers:**
  - The brick house's study and the bungalow's den already had a desk with a computer.
  - The Victorian house and the blue cottage now have one too, on a desk in the bedroom.
  - Each new desk is 8 parts, so the town is now 26,827 parts (the limit is 27,000).
- **Using it:** stand at the desk and press **E** ("Use computer").
  - At **your own** computer, you see your saved options and buttons to withdraw S$5, S$10, S$25, S$50, or the most you can.
  - At **someone else's** computer, you are told which house is yours.
  - **Animals** cannot use computers.

## Withdrawing
- **The limit:** at most **S$100 per server**, in total. Leaving and coming back to the same server does not reset it. On a new server you can withdraw another S$100.
- **The order is always:**
  1. The options are taken off your saved profile.
  2. The profile is **saved**.
  3. Only then are the Spicy Dollars put in your wallet.
- **If the save fails:** nothing is taken, nothing is paid, and the player reads "Saving is slow right now, so nothing was taken. Try again in a minute."
- **Withdrawn Spicy Dollars belong to that server**, like all wallet money. They are not saved when you leave (your earlier call: only clothing and options are saved). The screen says so before anyone withdraws: "take out only what you will use".

## How a purchase is made safe (real money)
- **Only the server grants options**, and only when Roblox tells it about a purchase.
- **Saved first:** the options are written into the player's saved profile, and saved, **before** the game tells Roblox the purchase is done.
- **When in doubt, the game holds the purchase:** if anything is not certain, it tells Roblox "not done yet" and Roblox offers the purchase again later. That happens when:
  - the profile has not loaded;
  - the save failed;
  - the product or the amount looks wrong;
  - the player has left;
  - the switch is off.
- **Never granted twice:** each purchase's receipt is kept inside the player's profile, so the same purchase is never granted twice, even if it arrives again on another server.
- **Still loading:** if a player buys while their profile is still loading, the game waits up to 15 seconds for it.

**The switch:** `stockOptions` in `Shared/Config/Flags` (on by default). Turning it off stops buying and withdrawing at once. Purchases made meanwhile are held by Roblox and granted once it is back on, so nothing paid for is lost.

## What you need to do on Roblox
1. **Rename the product** (the API key cannot do this). In the Creator Hub, go to your experience, then **Monetization**, then **Developer Products**, and open product **3730438620**:
   - **Name:** `Spicy Stock Options`
   - **Description** (suggested): `In-game play money for Spicy Rodent. 4 options for each Robux; 1 option = S$1 to spend in the game. Saved with your profile. Withdraw up to S$100 per server at your home computer. No value outside the game.`
   - Keep whatever price you like.
2. **When you publish this,** use **"Migrate to Latest Update"** (or shut down the old servers). The saved profile now has a new version. An old server that meets a new profile leaves it alone and does not load the player's clothes there, so no old servers should keep running next to new ones.
3. **Test one real purchase** in a live server. Studio test purchases are free and may report 0 Robux spent. The game refuses to guess an amount, so in Studio the count may not go up.

   In the live server:
   1. Open the menu (M), then Stock options, then Buy with Robux.
   2. Check the count goes up, and say how many Robux it cost.
   3. Go to your home's computer and withdraw S$5.
   4. Check your wallet goes up by S$5 and the count goes down by 5.
   5. Leave, join another server, and check the count is the same.

## Roblox rules I know about (please read)
- **Not random:** every purchase gives exactly 4 options per Robux. Roblox's rules on paid random items (loot boxes) do not apply.
- **Describe it plainly:** the product description should say what is bought. The screen and the suggested description both do.
- **The name "Stock Options":** this is your name for it, and it is used as a joke name. As far as I know, Roblox's rules do not allow anything in a game to have real-world value or be cashed out, and a reviewer could misread the name as a real financial product. Everything the player sees says it is play money with no value outside the game, and never mentions returns, investing, interest, prizes or luck (a test checks these words). If Roblox moderation ever questions it, a plainer name ("Spicy Bucks") changes in one place.
- **Wallet money does not last:** players should not lose something they paid for without being told. The screen says plainly that withdrawn dollars stay on that server, and the S$100 cap keeps any such loss small. You may want to save the wallet too one day; say so if you do.

## One known edge (written down, rare)
Sometimes a save is reported as failed even though it actually went through. If that happens during a withdrawal and the server then shuts down before its next save, the player loses that one withdrawal's options without getting the dollars. The game cannot tell the two kinds of failure apart. A purchase never has this problem, because its receipt is kept and checked.

## Questions for you (my defaults in brackets)
1. **Home:** nearest of the four furnished houses, shared when needed (built that way). Would you rather everyone had their own house? Most of the town's other houses cannot be entered yet.
2. **Withdraw buttons:** S$5, S$10, S$25, S$50 and "all I can" (built that way).
3. **Withdrawn dollars:** stay on that server only (built that way, to match "money is not saved").
