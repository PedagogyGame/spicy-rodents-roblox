# Reputation, the kick ball and the two-seat golf cart: what to try (15 minutes)

Your words (22 November): "make reputation metrics occur in the background too, like lets put a kick ball in the store and if a person kicks it at another player or winds up and throws it at another player, their reputation score goes down, or practically runs over people, same thing, but do not mark this or score this often, only in extreme situations ... it should just show you that, then go away, not be a constant meter, but be checkable with money, in paused and or side screen". And: "i would like for the golf carts to be able to seat two".

All of it is tested without a screen. Nobody has seen it inside Roblox yet, so this list is the part only you can judge. You need two players for most of it (Studio's Test tab, "2 Players").

## 1. Reputation: how it works
- Everybody starts at **0, "Good"**.
- It only goes down for bad behaviour that is clearly on purpose. One accident never counts.
  - **The kick ball:** three hard hits on people within 30 seconds, or one hard throw at someone close by after a long wind-up. A soft toss never counts.
  - **Running people over** with a golf cart, moped or scooter: three different people within a minute, or the same person twice within 30 seconds. Gently bumping into someone never counts.
  - **Other helpers' rules:** keeping an errand's delivery, or a doctor driving past a bite victim. Those helpers decide when it counts.
- Each one costs 10 points. After it counts, the same kind of thing does not count again for 2 minutes. That keeps it rare.
- When it goes down, a short message shows on **your screen only** for a few seconds, then goes away. For example: "Reputation down: you kept hitting people with the ball (now Fair)". There is no meter on the screen.
- Below 0 it slowly comes back: one point every 3 minutes, as long as you behave.
- **The words:**
  - **Trusted:** 30 and up
  - **Good:** -4 and up
  - **Fair:** -24 and up
  - **Poor:** below -24

  One bad act puts you at Fair. Three put you at Poor.
- Good things you do still raise it quietly, as before: a kick that lands on the rodent, or a job done well. A rise is never announced.
- The townsperson queue already counted reputation, and now it reads this score.

## 2. Please check: seeing it
| # | What to try | What you should see |
|---|---|---|
| 1 | Press **M** (the menu) | Under the role buttons: "Money  S$3.00   ·   Reputation  Good (0)" |
| 2 | With the menu open on a wide screen | Beside the wallet in the bottom-right corner, a "Reputation  Good (0)" line under your balance. It goes away when the menu closes |
| 3 | Play normally | No reputation on screen at all |

## 3. Please check: the kick ball
The kick ball is on sale in **Pepper's Corner Store for 7c**. It is a red rubber ball with a cream band. Look on the fourth low shelf unit, on the far side from the duct tape, at the front end.

| # | What to try | What should happen |
|---|---|---|
| 1 | Buy it, hold it, and **click** (or tap, or press the trigger) | You kick it: it drops to your foot and shoots off low and fast |
| 2 | **Hold the click**, then let go | You wind up and throw it from your hand. The longer you hold (up to about 1.2 seconds), the harder it goes. A very quick hold is a soft lob |
| 3 | Walk up to the ball lying on the ground and press **F** | You kick it along the ground, like the townsperson's kick. It is still the buyer's ball |
| 4 | Kick it hard at the second player | They stagger a little (a short push, a moment without control, never a fall) and read "Ouch! A ball hit you." Your reputation does not change for one hit |
| 5 | Hit them hard three times within 30 seconds | You alone read "Reputation down: you kept hitting people with the ball (now Fair)". Press M: "Fair (-10)" |
| 6 | Toss it gently to them | They catch it, as with the frisbee. It goes back to you after 20 seconds, or if they walk off with it |
| 7 | Kick it at a computer townsperson | Their arms come up. Hard hits on townspeople count the same as hits on players |

## 4. Please check: the two-seat golf cart
| # | What to try | What should happen |
|---|---|---|
| 1 | Player 1 drives a golf cart (E). Player 2 walks up to it | Over the cart: "E  sit beside the driver" (SIT on a phone) |
| 2 | Player 2 presses **E** | They sit on the bench beside the driver, on the right-hand side. Player 1 drives them about |
| 3 | Player 2 presses **E** again (GET OFF on a phone) | They get off on their own side |
| 4 | The driver gets out while the passenger stays | The passenger stays seated in the parked cart until they press E |
| 5 | Drive the cart into people | Bumps and knock-overs work as before. Your passenger is never bumped by your own cart |

Mopeds and scooters still carry one person.

## 5. Questions for you (each already has a default built in)
1. **Should reputation be saved between servers?** Default: no, like the money. It lasts as long as the server runs, including if you leave and come back. The save file already has a reputation slot ready if you want it saved.
2. **What should the menu show: the word and the number ("Fair (-10)"), or just the word?** Default: both.
3. **Should hitting the computer's townspeople with the ball count?** Default: yes, the same as hitting players.
4. **How fast should it come back?** Default: one point every 3 minutes. From one bad act (-10), you are back to Good after about 18 minutes.
5. **Is 7c the right price for the kick ball?** The frisbee is 5c and the football 6c.

## 6. What it costs (phones)
- **The kick ball:** 2 parts in the hand, a ball and its band (2 more on the shelf, plus 2 copies beside it). While a hard ball is flying, the server checks about 100 nearby people once per frame. Nothing runs when no ball is flying.
- **Reputation:** no work per frame. The server updates the numbers every 10 seconds. One attribute per player.
- **Golf cart passenger seat:** one hidden part per cart (3 in the town). No new triangles.
