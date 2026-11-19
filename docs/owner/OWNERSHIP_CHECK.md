# Who owns what: what to try (5 minutes)

Two of your answers from 19 November (addendum D16), built and tested without a screen. Try them with a second player (Studio's two-player test, or a friend).

## 1. A bought thing stays yours (#26)

What you said: "purchased items (unless otherwise specified) remain only in the original buyer's inventory".

**What I built.** Your frisbee or football can still be played with by anyone, but it never becomes theirs:
- Someone who **catches** it (it hits them in flight) or **picks it up** (E) gets it in their hand, named "Pip's frisbee", only to throw it back. It is never in their inventory.
- It goes home to you (into your hotbar) when they **hold it 20 seconds** without throwing, **walk off with it** (more than 60 studs from you), change body, or leave the game.
- **Left lying** for a minute, it comes back to you (it was 2 minutes).
- **If you leave the server**, everything of yours goes back into your things at once: the ball someone holds, one on the ground, your whoopee cushion, your lawn chair. If you come back to the same server, they are still yours (as you said in #25, bought things stay on the server they were bought on).
- **Whoopee cushion:** if someone else presses E on yours, it goes back into your things, not theirs.
- Nothing the game sells is "finders keepers". If the game ever gives an item away that should pass on, it can be marked so in one line (`findersKeep`).

**Why this way:** a game of catch still works (catch, click, it flies back), and nobody can keep something they did not buy. The other way (nobody else can touch your ball at all) would make catch impossible.

**Try:**
1. Buy a football. Throw it to the other player. They press E on it (or stand in its way). They read "Pip's football: throw it back. It goes home by itself in 20 seconds." You read "Sam has your football."
2. They click to throw it back. Catch it, or press E on it: it is back in your hotbar.
3. Throw it again. Let them pick it up and run off: past 60 studs it jumps back to you ("Your football is back in your hands.").
4. Throw it and leave the game: it is gone from the ground. Rejoin the same server: it is in your hotbar.

**Open for you:** the 20 seconds, the 60 studs and the minute on the ground are guesses. Default: as built.

## 2. One hollow tree each (#21)

What you said: "limit squirrels to claiming only one tree".

**What I built.** A squirrel (a player's or the computer's) holds at most one tree. While it holds one, it cannot fill another: inside a second tree its nuts stay in its cheeks, and it reads "You already have a tree: the Bur Oak. A squirrel keeps just one, so your nuts stay with you." When its claim lapses (three game days away, or the store runs low), it reads "The Bur Oak is not your tree any more. You can claim a new one," and it can claim any other. A new claim says "The American Elm is your tree now! Visit it at least every 3 game days to keep it." Inside someone else's tree it reads "This tree belongs to Pip. Your nuts stay with you." The Spicy Rodent claims nothing, as before.

**Why refuse rather than ask to move the claim:** claiming happens just by being there (no button, your brief section 3). Asking would need a new prompt, and the E key is already used at the knotholes. Moving the claim by itself would let a squirrel that dives into the nearest tree to hide from the police lose its home without meaning to. Refusing loses nothing. A "let my tree go" button belongs with the nut meter on screen (#22, next), and I can add it there.

**Try:** nothing to try yet without nut sources (they come with #22). The rule is tested headless on the real town.

## Costs
- Nothing new to draw. A borrowed ball is one Tool. Every 0.1 s, the server checks each borrowed or lying ball (a distance and a clock), only while there are any.
- The hollow check looks through 12 trees for a squirrel's own claim, only when it carries nuts into a tree.
