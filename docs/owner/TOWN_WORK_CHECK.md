# Town work: banks, errands, jobs, penalties, the Lookout's people (D30)

What you asked for, what was built, and how to check it in a test session. Nothing here has run in Studio yet.

## 1. Banks and errands

**Where the banks are.** Three of the half-timbered buildings in Bellwether Quay, the old market quarter by the
river, now say **BANK** over the shop window:

- the **South Quay bank**: west bank of the river, south of the bridge (it was a second "FERRY & FINCH");
- the **North Quay bank**: west bank of the river, north of the bridge (it was a third "THE COBBLER");
- the **Market bank**: on the market row east of the river, south of the clock tower (another "THE COBBLER").

The rest of the town is mostly houses, so the banks are in the commercial quarter. If you want one in the old town
or on the west side, that needs a new small building; say so.

**The errand board.** Outside each bank, on the quay beside the door, is a dark green sandwich board: "BANK
ERRANDS, deliveries around town".

Check:
1. Walk up to a board as a person. Press **E** ("Errands"). A line at the top of the screen tells you the errand,
   for example "Take this parcel to Pepper's Corner Store. You have 9 minutes; it pays 14c." or "Bring these
   flowers to Mrs. Abbott at the Victorian house south-west of the old town crossroads."
2. The parcel, letter, flowers, cake box or book is in your person's right hand.
3. Nothing is marked on the map or the screen. You have to know where the place is. When you come within about
   45 studs of it, you get one quiet line: "You're close to ...".
4. Walk up to the place's door. The thing leaves your hand and you get paid: "Delivered ... +14c."
5. You can only carry one errand at a time. If you press a board while carrying one, it tells you what you carry
   and for whom.
6. If you can't find the place, go back to any bank's board and press **E** twice. You hand it back with no pay
   and no penalty.
7. A squirrel can't take an errand. If you pick a squirrel while carrying one, the thing leaves your hand. It comes
   back when you are a person again, but the clock keeps running.

The places are Pepper's Corner Store, the Neighbourhood Shop, the Gilded Acorn, the bowling alley's front doors,
the Chili Pepper Grill, the clock tower in the Quay Market, the Bellwether Galleria, the sky lift's station at the
foot of Lookout Hill, the West Topeka police station, the Westside fuel station and Westside Storage. The people are
the residents of the four old-town houses, at their own front doors.

**Pay.** An errand pays 4c, plus 1c for every 100 studs from the bank, up to 30c. Most errands pay 15 to 30c, which
is about five to ten in-game hours at the minimum wage.

**Time.** You get the straight distance at a slow walk plus two minutes. That is usually 5 to 10 minutes, enough to
walk the long way round. A minute before the end you get a reminder.

**Spicy Stock Options at the bank.** Each board has a second prompt, **R** "Spicy Stock Options". It opens the
purchase window from the stock options work.

## 2. Jobs at the bowling alley and the Lookout

Before this, nothing paid a player for work. The ladder had a rule for it, but nothing used it. There are now three
jobs, each with a prompt **E** "Work here":

- **Shoe desk attendant**: the shoe rental at the bowling alley. Duties: the desk, the cubbies, the returns window,
  the spray bench.
- **Lane attendant**: the lanes at the bowling alley. Duties: dust-mop the back of the approaches, wipe the house
  balls.
- **Lookout attendant**: the Lookout at the top of the sky lift. Duties: the counter, the tables, the terrace, the
  telescope.

Check:
1. As a townsperson, press **E** at the post. You are told the job, the pay (3c an in-game hour) and your first
   duty.
2. Walk to the named duty and stand there a few seconds. You get "Done. Next: ...".
3. Each in-game hour (about 30 real seconds) in which you did at least one duty pays 3c ("+3c for an hour as ...").
   An hour with nothing done pays nothing. After three idle hours you are clocked off.
4. Press **E** at the post again to clock off.
5. Two players at most per job, and one job at a time. Police and doctors can't take these jobs: they already have
   jobs.

## 3. Penalties

**An errand runner who keeps the item loses S$100.** That happens if they:
- are still carrying it when the time runs out;
- keep it inside their own home for 20 seconds in all (the home is the house the stock options work gave them);
- leave the server with it.

They also get a reputation mark ("you kept an errand's delivery for yourself").

**A doctor demoted for ignoring a bite victim** (or abandoning a patient) loses S$100. After that, their money is
brought down to the lowest townsperson's money level. The doctors' work decides the demotion and gives the
reputation mark; this part only takes the money.

What "the lowest townsperson station's money level" means here: the townsperson is the lowest station on the
ladder. Its money level is the least money any townsperson in the server holds right now. If there is no other
townsperson, it is what a newcomer starts with (S$3.00 of pocket money). The penalty never raises anyone's money.

**Please decide: S$100 is very large in this game's money.** Wages are 2 to 6 cents an in-game hour, and a newcomer
gets S$3.00. In practice the S$100 penalty takes everything a player has. The wallet never goes below zero: there
is no debt anywhere in the game, so a player with less than S$100 loses what they have. The amount is one setting
(`work.penaltyCents`). If you meant something smaller, tell me the amount. Saved stock options are never touched by
a penalty.

## 4. The people at the top of the sky lift now move

**Why they did not move:** the town's walkers can't go up to the Lookout, so the sky lift held its host as a statue
by the lectern. It also put every visitor straight from the cabin onto a chair, and back.

**Now:**
- The **host walks a round**. He greets at the lectern by the door, sees to a table, collects at the counter,
  goes out to the terrace's tables, and comes back.
- **Visitors walk.** They step off the cabin, go along the platform and through the hall door, then walk to a free
  table and sit down to eat for a few minutes. Afterwards they get up and walk round the back walkway to the
  boarding platform, then take a cabin down. Every third visitor doesn't sit: they look through the telescope and
  stand at the rail looking at the view.

Check: ride up and watch. The host should never stand still for more than about 12 seconds. People walk in from the
lift hall and leave the same way.

## Cost (phones)

- The bank boards and job posts add 9 parts in all.
- The Lookout's walkers are the host and at most four visitors. Each is placed once a step with a few sums.
- Errands and jobs are checked four times a second, only for players who are carrying an errand or working a shift.
