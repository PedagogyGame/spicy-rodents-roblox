--!strict
-- ServerScriptService.Server.Minigames.Paintball.PaintballService
-- The paintball server (checklist PB-3, PB-4, PB-6, PB-11, PB-12, PB-14, PB-15): everything behind
-- paintball's Table in the minigame framework (Server/Minigames/Games/Paintball hands each hook of
-- the Table to a method here). It owns the match loop, the five remotes, validation,
-- lag-compensated hits, splats, the roster, the audience and the access pass.
-- OWNED BY THE SERVER LANE. `new`, `port` and the Service's methods keep the names and signatures the
-- contract gave them. Beside this file, the lane's own: Stream (what is kept for a person, and the
-- judgment of its Moves and of a shot's origin), PassDesk (the pass), RealEngine (the hands on real
-- bodies). Files named Bot*.luau are the match-and-bots lane's.
-- WHERE THE LANE READ THE CONTRACT ONE WAY OF TWO (each is one line of code, named here):
--   * "sprint" (onFire c) counts only Moves stamped at or before f: a Move stamped after the click says
--     nothing of it (Stream.sprinting);
--   * the origin's "Body.JUMP_HEIGHT more while the newest Move says BIT.air" is allowed below the eye
--     as well as above it: a body coming down from a hop is lower than its newest Move (Stream.originOk);
--   * a slot's splats and pose history are emptied when its occupant changes, when the roster is read;
--   * a person who trades sides in the briefing stands, until the match has placed them anew, in
--     what has just become the other team's spawn room: their Moves from there are dropped, not refused
--     as "inside the other team's spawn room" (the "side" verb; Stream, owedSince);
--   * at "start", "unless that team already has Rules.teamMax people" counts the people GOING to a side
--     (their remembered sides, in seat order), not the people the new deal has just handed it: with
--     sixteen people the deal fills both sides, and two who had crossed would each be refused (onStart).
-- WHERE IT DID NOT DO AS WRITTEN, FOR THE HONEST PLAYER (as written each of these refuses or drops
-- somebody who did nothing wrong; nothing another lane sends or hears changes; all reported):
--   * a body has a footprint (Stream, "the height rule"): a pose whose feet point is up to a stud past
--     the edge of a floor is still standing on it. The contract's point test refuses a player who
--     stands at an edge;
--   * a running jump off a ledge is a hop (Stream, "the height rule"): an unsupported pose may be as
--     high as a hop from the surface the body last stood on, not merely "no higher than the last
--     accepted pose" (which refuses every Move of the hop that rises past the edge);
--   * the body rule (onMove e, "the body") counts height only for a body that stands: while a pose is
--     falling, and a quarter of a second after, the replicated body is still on its way down behind its
--     own Moves and only the sideways distance is held to TRUST.bodySlack (Stream, "the body rule");
--   * the body rule is not kept for TRUST.placeGrace after a placement (Stream, "the body rule"): the
--     body the server reads may still be where its own client last sent it from, before it heard, and
--     an honest Move from the new place would be refused against it, three times, and corrected;
--   * silence is measured from a placement as well as from a Move (Stream.placed): a client back from
--     being tagged out is owed all of Clock.DROP_SECS, not what its time out left of it;
--   * a click that came later than its own delay explains is also judged at its own stamp for WHERE it
--     left from, no further back than the shooter's own window (Stream.lateWindow, at most
--     Clock.MAG_LATE), while the sprint, the spawn rooms and the stance are held to f as well (onFire;
--     Stream, "a click that came late"): as written, a strafing shooter's click behind one lost packet
--     is refused, which the lane guide's own "three shots bunched half a second late are all accepted"
--     says it must not be.
-- AND WHERE IT DID NOT DO AS WRITTEN BECAUSE AS WRITTEN A LIAR GAINS (all reported):
--   * a fall must fall (Stream, "the height rule"): an unsupported pose must come down at a quarter of
--     gravity or faster from the height of a hop; it is not allowed to walk level for the whole of
--     TRUST.fallSecs (a third of a second is what is left of that);
--   * after a CORRECTION the distance budget is EMPTY, not full (Stream.placed): a full one hands half a
--     second of free distance to whoever gets themselves refused, 28 studs a second on corrections alone;
--   * a correction whose anchor hangs in mid-air (a "fall" that never came down) puts the body on the
--     walking surface under it, not back in the air (correct());
--   * the "side" verb is honoured for one person once in SIDE_EVERY seconds: every change puts a bot
--     of the other side, wherever it is fighting, back in a spawn room with a full magazine and its
--     protection (Rules.assign), and a client that sends the verb as fast as the framework lets it
--     through (twenty a second, tagged out, there and back) would keep both sides' bots out of the match.
--
-- WHAT IT IS BUILT FROM. new(ctx, deps): ctx is the framework's ServerGame.Ctx for the arena's
-- station; deps is ctx.opts.paintball (a spec's stand-ins; nil in the game). The arena is pure data
-- (ArenaData.build()) placed with Arena.placeOf(ctx.place). The FURNITURE is the baked model
-- ctx.root[Arena.MODEL]: without it `hw` is nil and the service is inert, as the framework asks of
-- every game (no remote bound, nothing stepped, nothing sent, "The arena is closed." to a join). The
-- PORT is how it reaches paintball's own remotes: deps.port, else PaintballService.port(ctx.net).
-- It is bound only when hw is there, so nobody else's test ever sees a paintball remote; a spec that
-- wants the stream passes tests/lib/PaintballRig's port. The match model is the Session's:
-- state() = ctx.session.game.state while ctx.session.phase is "playing" or "done" (a Rules.State).
-- ONE CLOCK: every `now` below is ctx.stamp(), the shared clock (Clock). ctx.now() is read for one
-- thing only, how long the end card has been up (ctx.session.doneEnds is on that clock).
-- THE FEEL: service.feel is the feel the NEXT match will be played with (deps.feel, else the
-- defaults); the match in play keeps its own (state.feel), and everything below that says `feel`
-- means state.feel.
--
-- WHAT THE SERVICE KEEPS FOR A PERSON. It is kept BY PLAYER, not by seat (the people still seated are
-- dealt new seats at every new match, and their clients' controllers live on across it); "the slot's"
-- below means "of the person who holds that slot". All of it starts afresh when a person is seated
-- (joined); at a new match (`start`) `place`, `up`, `lastM` and `shot` carry on and the rest starts afresh.
--   place     the placement number (Wire.nextPlace each time the server moves the body; 0 until the
--             first placement: until then the person's Moves are dropped and inPlay says yes)
--   moves     the last Clock.MOVES_KEPT accepted Moves, by their own t; emptied by every placement
--   anchor    the last accepted pose (after a placement: the pose the server placed)
--   up        a Clock.View fed by Clock.observe(up, move.t, now) for every Move that gets as far as
--             being judged: the smoothed upstream delay
--   budget    the horizontal distance it may still move (Contract, "distance"); full after a placement
--   crouch    the crouch fraction, eased by the service (step 5)
--   lastM     the magazine time of its last accepted shot; shot: the counter of its last judged click
--   heardAt   when a Move last got as far as being judged (silence is measured from it)
--   idle      the pose and the time its idleness is measured from
-- "THE SLOT'S POSE AT t" (used at a snapshot tick and at a fire time): the straight line between the
-- two Moves of `moves` either side of t (x, y, z); held at the newest Move when t is past it, at the
-- oldest when t is before it; the anchor when `moves` is empty. Yaw, pitch and the client's bits
-- (crouch, sprint, air) are the newer of the two Moves'.
--
-- THE FRAMEWORK'S HOOKS (ServerGame.Table), in the order the service uses them
--   join(player, via)     via.id == Contract.DESK: the pass desk. pass.buy(player) and return false
--                         with its words (the framework shows them and seats nobody). Otherwise the
--                         door, in this order: a player who is already seated: true, nothing done.
--                         While ctx.session.phase is "done" (the end card): false with
--                         Contract.nextMatch(seconds until the service rolls on); the framework would
--                         otherwise wipe the table for the newcomer and tell nobody who was dropped.
--                         Then refuse with words when deps.fit says no ("infected": decision D6),
--                         when the player holds no pass (pass.has; a pass is checked only here, so a
--                         match in progress always finishes: D5), or when all Rules.slots seats are
--                         people ("full"). Then THE ROSTER: if a match is on and a bot is seated,
--                         take one off with ctx.removeComputer (a bot on the side with fewer people;
--                         of those, the lowest seat) and the framework gives the person that seat,
--                         and Rules.join that bot's team.
--   joined(player, seat)  the person is seated (the first one has just started the match: "start"
--                         came first). Start their slot afresh (above), remember that the service
--                         has placed them, engine.ghost(body, true), put them in the audience now
--                         ("paintball_watch" and the splat pools). Their body goes to the spawn room
--                         by the "respawn" event Rules emitted, in the next step. Then balance (below),
--                         Bots.sync, and "paintball_watch" again to the whole audience (the roster
--                         changed).
--   command(player, verb, args)   the framework's own table verbs are not a player's to send in a
--                         match that starts itself, rolls on by itself and seats its own bots:
--                         "start", "again", "addai" and "mode" are refused with words. ("leave" is
--                         left to the framework.)
--   input(player, seat, verb, args)   always answered here (never nil).
--                         "reload" { t }: m = the magazine time of t (the fifth result of
--                         Clock.stamp(now, now, t, lastM, up)); Rules.reload(state, seat, m); false
--                         with words when it does nothing.
--                         "side" {}: honoured when the phase is "briefing" or the sender is tagged
--                         out in the first SIDE_LIVE (60) seconds of live play (later, a change would
--                         make a winner of a loser on the end card), the sender has no ball in
--                         flight, and the other team has a bot (the
--                         lane's choice of which: one that is itself out, else one in its own spawn
--                         room, else one in the fight; the lowest seat of the first kind there is):
--                         Rules.assign the sender to the other team and that bot to
--                         the sender's, Bots.sync, ctx.dirty(), "paintball_watch" to the audience.
--                         Otherwise false with Contract.textFor("side").
--   step(dt)              THE LOOP, below. Runs before the Session's own step.
--   event(e)              "start": a match begins. match += 1; Rules.tune(state, service.feel);
--                         Rules.sync(state, now); every splat, ball, pose history and Move buffer is
--                         dropped. PEOPLE KEEP THEIR SIDES: every seated person whose team at the end
--                         of the last match is remembered is put back on it (Rules.assign), in seat
--                         order, unless that team already has Rules.teamMax people. Everybody the
--                         service had placed who is no longer seated is put at arena.lobby. The
--                         audience is told (a new `match`). The framework then seats bots up to the
--                         Spec's fill, each on the smaller side (Rules.join); the next step balances.
--                         "left": a seat was left. A person: forget their slot's stream,
--                         engine.ghost(body, false), put their body at arena.lobby (if they still
--                         have one), forget that they were placed; while the match is on and a person
--                         remains, seat a bot at once (ctx.addComputer: it takes the vacated seat and
--                         its team). Bots.sync and "paintball_watch" to the audience either way.
--                         "done": the clock ran out; the framework shows Rules.result's card. Remember
--                         each seated person's team (for the next "start").
--                         "reset": the table was emptied (nobody left, only bots left, the end card
--                         timed out, a fault): everybody the service had placed is put at arena.lobby
--                         and un-ghosted, everything is dropped, the remembered sides are forgotten,
--                         "paintball_unwatch" to the audience.
--   state(player, seat)   Contract.Extras for that player's "state" message.
--   inPlay(player, body)  the framework's walk-away check, for an arena: true while the body is
--                         inside the arena volume (Arena.inVolume with 4 studs to spare), until the
--                         server has first placed it, and for TRUST.placeGrace after the server
--                         moved it. False takes the player off.
--   screen(view), sig(view)   the monitors: every part named Arena.MONITOR under hw (the lobby's,
--                         and the old sets on each floor: the arena lane's bake) shows the phase, the
--                         clock and both scores; idle, it shows the station's name.
--   prompt()              one action line for both prompts ("Paintball"): each label says the rest.
--   doneText(view)        the end banner: Result.text.
--   debug(...)            scripted outcomes for the engine check (tests/engine/PaintballFlow) and the
--                         playtest: "tag" (by, id); "end" (the clock runs out now); "tune" (key,
--                         value): service.feel = Contract.tuned(service.feel, key, value), in force
--                         from the next match, (false, words) for a bad key or value (written in the
--                         stub already); "rewind" (seconds, 0.1 to 0.4): Clock.MAX_REWIND on this
--                         server, from the next match (the lane's own: a knob for the owner's playtest
--                         at a slow connection; reported); "botSkill" (-0.5 to 0.5): the bots' Opts.skill,
--                         for every bot seated from then on (the owner's knob for how hard they are).
-- THE ROSTER, AND BALANCE. A slot's team is its own (Rules, "teams"). The service changes who is on
-- which side in three ways only: it chooses WHICH bot gives its seat to a person who joins (above);
-- it trades a person and a bot on the "side" verb; it puts people back on their sides at "start".
-- BALANCE, after the fill at a start (in the next step) and after every seat taken or left: while
-- the two sides are not the same size, or either is under Rules.teamMin, and a seat is free:
-- ctx.addComputer() (the bot joins the smaller side). It never takes a bot off to balance.
-- ROLLING ON. While ctx.session.phase is "done": when Rules.endCardSecs of end card have passed
-- (ctx.session.doneEnds - ctx.now() <= Rules.endCardSpare), take every bot off (ctx.removeComputer)
-- and call ctx.again(). The people still seated are dealt seats 1, 2, 3 ... in their old order;
-- "start" puts them back on their sides and the fill and the balance rebuild the rest (never under
-- teamMin a side). If only bots are left the framework resets.
--
-- THE LOOP (step(dt), every server step; now = ctx.stamp())
--   0. Nothing at all unless hw is there and ctx.session.phase is "playing" or "done" (PB-15: an
--      idle arena costs nothing). Rules.sync(state, now): the model is slaved to the shared clock
--      (Rules, "time"). DURING THE END CARD ("done") people may still walk about and see each other:
--      of the steps below only 1, the silence of 2 (no idleness), 5 and 6 run, the bots stand where
--      they stood, nothing is fired (Rules refuses: the phase), and the roll into the next match is
--      watched for (above).
--   1. Rules.drain(state):
--      "phase"    ctx.dirty() (the view carries it).
--      "respawn"  place the slot at arena.spawns[team][spawn]. A person: place = Wire.nextPlace(place);
--                 engine.teleport (world: Arena.toWorld and Arena.yawToWorld with the place); the
--                 anchor is the spawn point, `moves` is emptied, the budget is full, crouch is 0; the
--                 slot is in play again. A bot: its pose is set and Bots.place called. Either way
--                 ctx.broadcast "paintball_respawn" { id, x, y, z, yaw, at, place (a bot: 0) }.
--      "reload"   a person's: ctx.send "paintball_reload" to that player alone. A bot's: nothing
--                 (everybody hears a reload from BIT.reload in the snapshots).
--      "tag"      nothing: the message went out where Rules.tag said yes (step 4).
--   2. People. SILENCE is measured from heardAt, and not at all while the slot is out or within
--      TRUST.placeGrace of a placement (a client sends nothing while out): after Clock.STALE_SECS the
--      slot may not fire ("stale"); after Clock.DROP_SECS ctx.leave(player, "dropped", its words).
--      IDLENESS, counted only while the phase is "live": a person whose accepted pose has stayed
--      within 0.5 studs and 0.05 rad (yaw and pitch) of the `idle` pose and who has fired no accepted
--      shot for Rules.idleSecs: ctx.leave(player, "idle", its words). A Move beyond those bounds, or
--      an accepted shot, restarts it; a placement by the server does not (a respawn moves the `idle`
--      pose to the placed pose, a correction moves neither; while out no Move is judged, so nothing
--      the body does then counts). A pose inside an arena.exits room: ctx.leave(player, "exit", its words). Each arrives back as "left".
--   3. Bots.step(bots, state, poses, heard, now, dt): `heard` is every ball born, ball ended and tag
--      since the last tick (people's and bots'; a ball's "ended" before its "tag"). The bots move their
--      own poses. A "fire" command is DROPPED unless Bots.judge agrees: its direction within
--      BOT.aimSlack of Body.look(pose.yaw, pose.pitch), its origin at the pose's eye, the pose in no
--      spawn room, no BIT.sprint in the pose nor within Body.SPRINT_FIRE_DELAY - MARGIN.sprint, then
--      Rules.fire(state, id, now); the ball is born now with no rewind. "reload" goes through
--      Rules.reload; "say" out as "paintball_say". A bot's POSE is not judged at run time: the
--      match-and-bots lane's Sim legs check and BotCheck pin every brain step to a person's rules.
--      Its cost is Stats.botsMs.
--   4. Balls (Stats.ballsMs): Projectiles.step against arena.sweep and, with Hit.body, against every
--      slot that is on, is on the other team from the ball (the ball keeps the team it was born with),
--      Rules.canBeHit(state, id, now), and whose REWOUND pose (its history at now - ball.rewind) is
--      not inside its own team's spawn room (Arena.inRoom, feet + 0.1). BEFORE a slot's history is
--      sampled it is passed over if its newest snapshot pose is further from the box round the ball's
--      step than Body.RADIUS + Body.speed(0, true, feel) x TRUST.speedTolerance x (Clock.MAX_REWIND
--      + Clock.MAX_LATE) sideways, or 2 x Arena.FLOOR_HEIGHT up or down: nothing that near could
--      have been there. A ball that ends on a body: Rules.tag(state, by, id, now, ball's birth); on
--      true, ctx.broadcast "paintball_tag" (the ball's id, the ENTRY point, state.scores, by's tags,
--      id's outs, at = id's outUntil), and from that moment the tagged person's Moves are dropped and
--      its pose held where it stood, until its respawn. NO ctx.dirty() for a tag. Every ball that
--      ends on something makes one Splat record (wall: point and face; body: Wire.toBody offset from
--      the rewound pose, yaw from the newest), kept in the pools (Wire, "two pools") and batched per
--      tick to the audience. Born balls go out as one Shot batch per tick (Wire.SHOTS_PER_MESSAGE at
--      most in a message).
--   5. Every 1 / Clock.SNAP_HZ seconds, the snapshot tick T = now. For every slot that is on:
--      a person   crouch = Body.crouchStep(crouch, the crouch bit of its newest Move, 1 / SNAP_HZ,
--                 feel); its pose is "the slot's pose at Clock.poseTime(up, T)" with that crouch
--                 fraction (while out: the pose it was tagged in, unchanged);
--      a bot      its pose as its brain left it (the brain eases its own crouch: never the service);
--      the bits   the client's or the brain's crouch, sprint and air, with Rules.bits(state, id, T)
--                 (out, safe, reload) and BIT.safe when the pose is inside its own team's spawn room.
--      The pose is quantised (Wire.quantPose), pushed into the slot's PoseHistory at T (x, y, z and
--      the crouch fraction), written to service.poses[id] (what the bots read) and sent
--      (Wire.encodeSnap with the match number) to the audience. THE HISTORY IS THE SNAPSHOT STREAM
--      (Clock): nothing else is ever pushed.
--   6. Every Clock.AUDIENCE_SECS: the audience. Of ctx.town.people(), whoever stands within
--      Arena.AUDIENCE_MARGIN of the arena volume (Arena.toLocal, Arena.inVolume), and everybody
--      seated, is in it: on coming in they get "paintball_watch" (ctx.send: the match number, who
--      holds which slot on which team, the feel) and both splat pools as one Splat batch; on going
--      out "paintball_unwatch". The streams go to the audience and to nobody else. "paintball_watch"
--      goes out again to all of it when the roster changes and when a match starts.
--      THE SWEEP, in the same pass: anybody of ctx.town.people() whose position is inside the arena
--      volume itself (no margin) and who is not seated here is put at arena.lobby (engine.teleport
--      of ctx.bodyOf(key)). That, with "start" and "reset", is what makes "nobody outside the match
--      is ever inside the arena" true whatever the framework did to the table.
--   Everything in the step that is not 3 or 4 is Stats.restMs. The shares are Contract.COST.
-- THE REMOTES (Wire; Shared/Net has checked shape and rate before the port hands a record over)
--   onMove   a person's pose (Contract, "who is trusted", is the rule; this is the order).
--            a. Not seated here, or the session is neither "playing" nor "done": dropped.
--            b. The slot has not been placed yet (place = 0), is out, or rec.place is not the slot's
--               place: dropped (Stats.movesDropped).
--            c. rec.t not later than the last accepted Move's t, later than now + TRUST.clockSlack, or
--               older than now - TRUST.moveAge: dropped (movesDropped).
--            d. Clock.observe(up, rec.t, now); heardAt = now.
--            e. Judge it against the anchor, first failure wins and names the `why`:
--               inside ("wall": outside the volume; arena.sweep of the point at Arena.CHEST above the
--               feet reports a box; inside the other team's spawn room), height ("wall"), walls
--               ("wall": Arena.clearPath(arena.sweep, anchor, this, at Arena.CHEST above the higher
--               feet point)), distance ("speed"), the body ("wall": further than TRUST.bodySlack
--               from engine.positionOf, when that is known).
--            f. Accepted (movesAccepted): it is the anchor, goes into `moves`, its horizontal step
--               leaves the budget; the idle check.
--            g. Refused (movesRefused): nothing changes. The TRUST.refusalsBeforeCorrect-th refusal
--               inside TRUST.refusalWindow is a CORRECTION (Stats.corrections): place =
--               Wire.nextPlace(place), engine.teleport to the anchor, `moves` emptied, the budget
--               full, ctx.send "paintball_correct" { x, y, z, yaw, why (the last refusal's), place }.
--   onFire   a click. Not seated here, or the session neither "playing" nor "done": dropped without a
--            word. Otherwise EVERY Fire gets one "paintball_ack" (ctx.send) carrying the slot's
--            magazine as it then stands, and `shot` becomes rec.shot. In order, the first failure
--            refuses (ok = false, its why; Stats.shotsRefused):
--            a. the slot is silent (step 2): "stale";
--            b. f, late, rewind, clamped, m = Clock.stamp(now, rec.vt, rec.ft, lastM, up.lag, rtt), rtt =
--               engine.ping(player) + TRUST.pingSlack when the engine knows it (clamped counts in
--               Stats.rewindsClamped);
--            c. sprint: a Move in `moves` with BIT.sprint and t > f - Body.SPRINT_FIRE_DELAY +
--               MARGIN.sprint: "sprint";
--            d. the room: the slot's pose at f is inside a spawn room (either): "safe";
--            e. the origin (Contract, "the origin"; Stream.originOk); a direction of no length, or one
--               further from its own Move's look than Stream.aimOk allows, or an origin further than bodySlack +
--               originSlack from where the replicated body really is (when the engine knows it, and not
--               within placeGrace of a placement): "origin";
--            f. Rules.fire(state, id, f, m): its why.
--            Accepted: the ball is born at f at the claimed origin with velocity = the unit direction
--            x feel.ballSpeed, the slot's team and that rewind; it is flown forward by `late` at
--            once (in steps of 1 / TICK_HZ, each against the bodies of its own moment); lastM = m;
--            its idleness restarts; the ack carries ok = true and the ball's id. THE BIRTHS ARE KEPT
--            APART: a ball is born no sooner than the shooter's last ball's birth + fireInterval -
--            BIRTH_MARGIN, a moment ahead of now if need be (Projectiles flies a ball from its birth and
--            not before; everything else is judged at f). Clicks bunched in one packet, by the network
--            or by a liar who back-dates them after a pause, leave one after another and never as a
--            spread (found at the review: three back-dated clicks were two balls born at one instant and
--            a third 0.09 s later).
-- IN AND OUT OF A MATCH, AND THE TOWN. The player keeps possessing the body they walked in with the
-- whole time; the town's own systems go on outside and never reach in (the arena volume is sealed:
-- Arena). Joining moves that body to its team's spawn room; leaving (the framework's Leave, walking
-- into an exit, dropped, idle, the player gone, the body lost: each arrives as "left") moves it to
-- arena.lobby. BODIES IN A MATCH PASS THROUGH EACH OTHER (they pass through bots, which have no body,
-- and a hidden person would otherwise block a corridor a stud to one side of where their puppet is
-- drawn): engine.ghost(body, true) puts every part of a seated body in the collision group
-- Contract.COLLISION_GROUP, which does not collide with itself and collides with everything else as
-- the default group does; engine.ghost(body, false) puts the parts back in the group they were in.
-- First person is the client's own doing (Client/Minigames/Paintball/PaintballClient).
-- THE PASS (PB-12). `pass` is deps.pass, else THE TOWN'S ONE PASS, ctx.town.pass (in the game the
-- wallet's, Server/Economy/Credits wallet.pass: 20c from the player's pocket money for five in-game days,
-- and the same pass opens both lounges, so a pass bought at this desk lets them into a lounge and one
-- bought at a lounge door lets them in here). Only where no town pass is handed in (a spec that runs the
-- service alone), or a spec hands in a day clock of its own (deps.day), is the lane's own desk used: on
-- ctx.town.charge(player, Rules.passCents, "a paintball pass") (honour a false and show its words), a
-- pass running Rules.passDays in-game days from deps.day(), remembered for as long as the server runs,
-- and beyond it in deps.passStore when one is handed over (PassDesk, "a store").
-- THE S18 CORE in Server/Paintball is this lane's to extend, keeping tests/unit/paintball_hitreg.spec green:
--   PoseHistory  gains a crouch channel beside x, y, z (same ring, same interpolation), so a crouched
--                body is judged crouched (PB-3); built with Clock.HISTORY_SECS at Clock.SNAP_HZ here.
--   Projectiles  tests the building through arena.sweep instead of scanning a box list and bodies
--                with Hit.body (the ball is its centre line, the contact is the ENTRY point and counts
--                only if nothing solid stands between it and the body's middle: Hit) instead of
--                Ballistics.segmentCapsule with the ball's radius added; takes the drop and the speed
--                from the match's feel and the ttl from Contract.Rules; keeps each ball's birth time
--                and team; can fly one new ball forward by `late` against the bodies of those past
--                moments; passes over a body by its newest pose before sampling it (step 4); clamps a
--                rewind to Clock.MAX_REWIND; reports the entry point.
--   Splats       two pools with one seq: the walls' ring of Rules.splatPool and a ring of
--                Rules.bodySplats for each slot; a slot's ring is emptied when its occupant changes,
--                both when the match does; the join batch is those rings, oldest first.
--   Layout, Harness  the S18 greybox and its hit-agreement harness: kept as the regression test of
--                the rewind, and given a condition that judges shots the contract's way (Clock.stamp
--                with `up`, history at SNAP_HZ, view time from Clock.viewTime, Hit.body) with the
--                95 % bar at 150 ms.
-- Interface: new(ctx, deps?) -> Service; port(net) -> Port; types Port, Engine, PassDesk, Deps, Stats,
--   Service. Service: hw; feel; join(player, via) -> (ok, why?); joined(player, seat, via);
--   command(player, verb, args) -> (handled, ok?, why?); input(player, seat, verb, args) -> (ok?,
--   why?); step(dt); event(e); state(player, seat) -> Extras?; inPlay(player, body) -> boolean;
--   screen(view); sig(view) -> any; prompt() -> (action?, object?); doneText(view) -> string?;
--   debug(...) -> (ok, why?); onMove(player, rec); onFire(player, rec); watching(player) -> boolean;
--   stats() -> Stats

local Import = require("../../Import")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local ArenaData: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.ArenaData)) =
	Import.shared("Minigames/Paintball/ArenaData")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Body: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Body)) =
	Import.shared("Minigames/Paintball/Body")
local Clock: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Clock)) =
	Import.shared("Minigames/Paintball/Clock")
local Rules: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Rules)) =
	Import.shared("Minigames/Paintball/Rules")
local Wire: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Wire)) =
	Import.shared("Minigames/Paintball/Wire")
local PoseHistory = require("../../Paintball/PoseHistory")
local Projectiles = require("../../Paintball/Projectiles")
local Splats = require("../../Paintball/Splats")
local ServerGame = require("../ServerGame")
local Bots = require("./Bots")
local PassDeskModule = require("./PassDesk")
local RealEngine = require("./RealEngine")
local Stream = require("./Stream")

type Arena = typeof(ArenaModule.T.Arena)
type Place = typeof(ArenaModule.T.Place)
type Spawn = typeof(ArenaModule.T.Spawn)
type Pose = typeof(Contract.T.Pose)
type Extras = typeof(Contract.T.Extras)
type Feel = typeof(Contract.T.Feel)
type Event = typeof(Contract.T.Event)
type State = typeof(Rules.T.State)
type SnapBody = typeof(Wire.T.SnapBody)
type Watched = typeof(Wire.T.Watched)
type Record = { [string]: number }
type Person = Stream.Person

local R = Contract.Rules
local T = Contract.TRUST
local BIT = Wire.BIT
local SIDE_EVERY = 3 -- seconds between two changes of side by one person (the header says why)
-- seconds into live play after which nobody changes sides: Rules.result counts whoever is on the winning side at
-- the end as a winner, so a late change would put a losing player on the end card as a winner
local SIDE_LIVE = 60
-- what debug("rewind", seconds) may set Clock.MAX_REWIND to (the pose history keeps Clock.HISTORY_SECS, a
-- second, and a ball is judged at most MAX_REWIND + MAX_LATE back)
local REWIND_MIN, REWIND_MAX = 0.1, 0.4

-- The service's link to paintball's own remotes (Wire.REMOTES).
--   on    hear a client-to-server remote ("Paintball.Move", "Paintball.Fire"): the record is already
--         decoded from its layout, checked finite and rate-limited by Shared/Net
--   fire  send a server-to-client buffer ("Paintball.Snap", "Paintball.Shot", "Splat") to one player
export type Port = {
	on: (remote: string, fn: (player: any, record: { [string]: number }) -> ()) -> (),
	fire: (player: any, remote: string, payload: buffer) -> (),
}

-- Everything that touches a body in the world, injected so the whole service runs under Lune.
-- World coordinates here; the service converts with Arena.toWorld / toLocal and its place.
export type Engine = {
	positionOf: (body: any) -> (number?, number?, number?), -- the real body's feet point; nil if gone
	teleport: (body: any, x: number, y: number, z: number, yaw: number) -> (), -- feet point and yaw
	-- on: every part of the body into Contract.COLLISION_GROUP (bodies in a match pass through each
	-- other); off: back into the group each part was in. The real engine registers the group once.
	ghost: (body: any, on: boolean) -> (),
	-- the client's round trip in seconds as the engine measures it (Clock, "the round trip"); nil or absent:
	-- not known, and a shot is bounded by the client's own stamps as before
	ping: ((player: any) -> number?)?,
}

-- The access pass (PB-12): 20 spicy cents for five in-game days.
export type PassDesk = {
	has: (player: any) -> boolean,
	-- Sell one: (true, Contract.textFor("bought")) or (false, words such as Contract.passShort(20, 7)
	-- or Contract.textFor("has_pass")). Never sells a second pass to a holder.
	buy: (player: any) -> (boolean, string),
}

-- A spec's stand-ins, handed over as the MinigameService option `paintball` (ctx.opts.paintball).
export type Deps = {
	port: Port?, -- default: port(ctx.net) (nil without a net: the stream goes nowhere)
	engine: Engine?, -- default: the real one, on the bodies ctx.bodyOf returns
	arena: Arena?, -- default ArenaData.build()
	seed: number?,
	feel: Feel?, -- the feel of the first match; default Contract.feel()
	pass: PassDesk?, -- default: the town's one, ctx.town.pass (else the lane's own, on ctx.town.charge)
	fit: ((player: any) -> (boolean, string?))?, -- fit to play? (false, a Contract.WHY code): "infected"
	day: (() -> number)?, -- the in-game day, for the lane's own pass desk (given one, that desk is used)
	-- where passes outlive the server (the profile; PassDesk.Store): nil, remembered while the server runs
	passStore: PassDeskModule.Store?,
	-- may this player tune the feel at a playtest (the "tune" verb)? Default: the place's owner (the user who
	-- owns the place, game.CreatorId), or anybody in Studio's own play test
	owner: ((player: any) -> boolean)?,
}

export type Stats = {
	steps: number,
	snapshots: number,
	balls: number,
	tags: number,
	movesAccepted: number,
	movesRefused: number,
	movesDropped: number, -- a stale placement number, an out slot, a bad or old t
	shotsRefused: number,
	-- the refusals by what refused them: a Move by the rule of Stream.RULES, a click by its Contract.WHY code
	-- (what a real server's check prints, so an honest body's refusals say which rule they meet)
	movesRefusedBy: { [string]: number },
	shotsRefusedBy: { [string]: number },
	corrections: number,
	rewindsClamped: number, -- shots whose claimed rewind was outside the server's bounds
	stepMs: number, -- the last step's cost; its three shares (Contract.COST):
	ballsMs: number,
	botsMs: number,
	restMs: number,
}

export type Service = {
	ctx: ServerGame.Ctx,
	deps: Deps,
	hw: any?, -- the baked arena model (ctx.root[Arena.MODEL]); nil = inert
	arena: Arena,
	place: Place,
	port: Port?,
	bots: Bots.Bots,
	match: number, -- Contract.Extras.match
	feel: Feel, -- the feel of the next match (the one in play keeps its own: state.feel)
	poses: { [number]: Pose }, -- every slot's pose as last put in a snapshot (a bot's: its present one), arena frame
	audience: { [any]: boolean },
	join: (self: Service, player: any, via: ServerGame.StationDef) -> (boolean, string?),
	joined: (self: Service, player: any, seat: number?, via: ServerGame.StationDef) -> (),
	command: (self: Service, player: any, verb: string, args: { any }) -> (boolean, boolean?, string?),
	input: (self: Service, player: any, seat: number, verb: string, args: { any }) -> (boolean?, string?),
	step: (self: Service, dt: number) -> (),
	event: (self: Service, e: ServerGame.Event) -> (),
	state: (self: Service, player: any, seat: number?) -> Extras?,
	inPlay: (self: Service, player: any, body: Model?) -> boolean,
	screen: (self: Service, view: { [string]: any }) -> (),
	sig: (self: Service, view: { [string]: any }) -> any,
	prompt: (self: Service) -> (string?, string?),
	doneText: (self: Service, view: { [string]: any }) -> string?,
	debug: (self: Service, ...any) -> (boolean, string?),
	onMove: (self: Service, player: any, rec: { [string]: number }) -> (),
	onFire: (self: Service, player: any, rec: { [string]: number }) -> (),
	watching: (self: Service, player: any) -> boolean,
	stats: (self: Service) -> Stats,
}

local PaintballService = {}

-- The Port onto a Shared/Net instance (the game's: ServerGame.Ctx.net).
function PaintballService.port(net: any): Port
	return {
		on = function(remote: string, fn: (player: any, record: { [string]: number }) -> ())
			net:on(remote, fn)
		end,
		fire = function(player: any, remote: string, payload: buffer)
			net:fire(player, remote, payload)
		end,
	}
end

local function noEngine(): Engine
	return {
		positionOf = function(_body: any): (number?, number?, number?)
			return nil, nil, nil
		end,
		teleport = function(_body: any, _x: number, _y: number, _z: number, _yaw: number) end,
		ghost = function(_body: any, _on: boolean) end,
	}
end

-- where an animal found inside the station is put (the arena frame: the street in front of the annex's door)
local STREET = table.freeze({ x = 0, y = 0, z = 100 })
local ANIMALS_OUT = "The TV station is for people: animals stay outside."

-- seconds a shooter's ball births are kept apart by, less than a fire interval (onFire, "the births")
local BIRTH_MARGIN = 0.05

-- The place's owner, or Studio's own play test (the default of Deps.owner).
local function placeOwner(player: any): boolean
	local ok, yes = pcall(function(): boolean
		if game:GetService("RunService"):IsStudio() then
			return true
		end
		return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
	end)
	return ok and yes == true
end

-- THE OWNER'S TUNING AT A PLAYTEST (the verb "tune", PaintballService.command): what each name means, in words.
local TUNE_WORDS: { [string]: string } = {
	ballSpeed = "Ball speed",
	ballDrop = "Ball drop",
	fireInterval = "Time between balls",
	reloadSecs = "Reload time",
	sprintMult = "Sprint speed",
	crouchSecs = "Crouch time",
	respawnSecs = "Time out when tagged",
	protectSecs = "Protection after a respawn",
	rewind = "Furthest rewind",
	botSkill = "Bot skill",
}

local function isBot(key: any): boolean
	return type(key) == "table" and key.ai == true
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

function PaintballService.new(ctx: ServerGame.Ctx, deps: Deps?): Service
	local d: Deps = deps or (ctx.opts.paintball :: Deps?) or {}
	local arena = d.arena or ArenaData.build()
	local root = ctx.root
	local hw = if root then root:FindFirstChild(ArenaModule.MODEL) else nil
	local place = ArenaModule.placeOf(ctx.place)
	local stats: Stats = {
		steps = 0,
		snapshots = 0,
		balls = 0,
		tags = 0,
		movesAccepted = 0,
		movesRefused = 0,
		movesDropped = 0,
		shotsRefused = 0,
		movesRefusedBy = {},
		shotsRefusedBy = {},
		corrections = 0,
		rewindsClamped = 0,
		stepMs = 0,
		ballsMs = 0,
		botsMs = 0,
		restMs = 0,
	}
	local service = {
		ctx = ctx,
		deps = d,
		hw = hw,
		arena = arena,
		place = place,
		port = nil,
		bots = Bots.new(arena, { seed = d.seed }),
		match = 0,
		feel = Contract.feel(d.feel :: any),
		poses = {},
		audience = {},
	} :: Service
	local engine: Engine = d.engine or (if hw ~= nil then RealEngine.new() else noEngine())
	-- the town's one pass (the wallet's: the lounges read it too); the lane's own desk only without one
	local pass: PassDesk = d.pass
		or (if d.day == nil and ctx.town ~= nil then ctx.town.pass else nil)
		or PassDeskModule.new(function(player: any, cents: number, why: string): (boolean, string?)
			return ctx.town.charge(player, cents, why)
		end, d.day or function(): number
			return ctx.stamp() / PassDeskModule.daySecs()
		end, d.passStore)

	-- what the service keeps (see the header: by player, not by seat)
	local people: { [any]: Person } = {}
	local bySeat: { [number]: Person } = {} -- kept right at every seat taken, left and dealt again
	local placeMemo: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any -- a player's last placement number, ever
	local placed: { [any]: boolean } = {} -- whom the service has put in the arena (and ghosted)
	local sides: { [any]: number } = {} -- the team each person ended the last match on
	local sideAt: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any -- when each person last changed sides
	local histories: { [number]: PoseHistory.History } = {} -- by slot
	local targets: { Projectiles.Target } = {} -- every slot that is on, in slot order
	local targetOf: { [number]: Projectiles.Target } = {}
	local occupant: { [number]: any } = {} -- who held each slot when the roster was last read
	local botSkill: { [number]: number } = {} -- Bots.sync's `who`: the slots bots hold
	local sim: Projectiles.Sim = Projectiles.forArena(arena, service.feel)
	local pools = Splats.pools(R.splatPool, R.bodySplats)
	local heard: { Bots.Heard } = {}
	local shotBatch: { Record } = {}
	local splatBatch: { Record } = {}
	local rosterDirty = false
	local nextSnap = -math.huge
	local snapSeq = 0
	local nextAudience = -math.huge
	local stepNow = 0
	local lobbyCount = 0
	local monitors: { any }? = nil

	local function matchState(): State?
		local s = ctx.session
		if s ~= nil and (s.phase == "playing" or s.phase == "done") and s.game ~= nil then
			return s.game.state
		end
		return nil
	end

	local function holderOf(seat: number): any
		local s = ctx.session
		local key = s.seats[seat]
		if key ~= nil and not s.gone[seat] then
			return key
		end
		return nil
	end

	local function toAudience(remote: string, payload: buffer)
		local port = service.port
		if port == nil then
			return
		end
		for player in service.audience do
			-- (a player who has left the game is dropped from the audience at its next pass: nothing is
			-- fired at one in the meantime)
			if typeof(player) ~= "Instance" or (player :: Instance).Parent ~= nil then
				port.fire(player, remote, payload)
			end
		end
	end

	-- a body to a point of the arena frame
	local function put(body: any, x: number, y: number, z: number, yaw: number)
		local wx, wy, wz = ArenaModule.toWorld(place, x, y, z)
		engine.teleport(body, wx, wy, wz, ArenaModule.yawToWorld(place, yaw))
	end

	-- Out of the arena: un-ghosted and stood in the lobby (a few studs apart, so a whole match that ends
	-- at once does not land on one spot).
	local function toLobby(player: any)
		placed[player] = nil
		local body = ctx.bodyOf(player)
		if body == nil then
			return
		end
		engine.ghost(body, false)
		local lobby = arena.lobby
		lobbyCount += 1
		local k = lobbyCount % 8
		put(body, lobby.x + (k % 4) * 3 - 4.5, lobby.y, lobby.z + (k // 4) * 3, lobby.yaw)
	end

	local function watchMessage(state: State): { [string]: any }
		local slots: { Watched } = {}
		for id, slot in state.slots do
			local key = if slot.on then holderOf(id) else nil
			if key ~= nil then
				local user = 0
				if not isBot(key) and type(key.UserId) == "number" and key.UserId > 0 then
					user = key.UserId
				end
				table.insert(slots, {
					id = id,
					team = slot.team,
					name = string.sub(ctx.nameOf(id), 1, 60),
					bot = isBot(key),
					user = user,
				})
			end
		end
		return {
			kind = "paintball_watch",
			match = service.match,
			slots = slots,
			now = ctx.stamp(),
			feel = Contract.feel(state.feel :: any),
		}
	end

	-- Somebody comes into the audience: who is where, then all the paint of the match so far.
	local function admit(player: any, state: State)
		service.audience[player] = true
		ctx.send(player, watchMessage(state))
		local port = service.port
		local batch = Splats.batch(pools)
		if port ~= nil and #batch > 0 then
			port.fire(player, "Splat", Wire.pack(Wire.Splat, batch))
		end
	end

	local function sideSizes(state: State): (number, number)
		local one, two = 0, 0
		for _, slot in state.slots do
			if slot.on then
				if slot.team == 1 then
					one += 1
				else
					two += 1
				end
			end
		end
		return one, two
	end

	-- BALANCE: bots are added (never taken off) until the sides are level and at least teamMin each.
	local function balance(state: State)
		for _ = 1, R.slots do
			local one, two = sideSizes(state)
			if (one == two and one >= R.teamMin) or one + two >= R.slots then
				return
			end
			if not ctx.addComputer() then
				return
			end
		end
	end

	local function spawnOf(team: number, index: number?): Spawn
		local list = arena.spawns[team]
		return list[((index or 1) - 1) % #list + 1]
	end

	-- The roster changed (a seat taken or left, a side changed, a match begun): balance, read who holds
	-- which slot, tell the bots and the audience.
	local function refreshRoster(now: number)
		rosterDirty = false
		local state = matchState()
		if state == nil then
			return
		end
		if ctx.session.phase == "playing" then
			balance(state)
		end
		rosterDirty = false -- (the bots balance seated raised it again)
		table.clear(botSkill)
		table.clear(targets)
		table.clear(targetOf)
		for id, slot in state.slots do
			local key = if slot.on then holderOf(id) else nil
			if occupant[id] ~= key then
				-- another occupant: nobody wears the last one's paint or is rewound to where it stood
				occupant[id] = key
				Splats.clearBody(pools, id)
				local history = histories[id]
				if history then
					PoseHistory.clear(history)
				end
				service.poses[id] = nil
			end
			if key == nil then
				continue
			end
			if isBot(key) then
				botSkill[id] = if type(key.skill) == "number" then key.skill else 0.5
				if service.poses[id] == nil then
					-- (its "respawn" event places it in the next step; until then a brain needs somewhere to be)
					local sp = spawnOf(slot.team, slot.spawn)
					service.poses[id] = { x = sp.x, y = sp.y, z = sp.z, yaw = sp.yaw, pitch = 0, crouch = 0, bits = 0 }
				end
			end
			local history = histories[id]
			if history == nil then
				history = PoseHistory.new(Clock.HISTORY_SECS, Clock.SNAP_HZ)
				histories[id] = history
			end
			local target: Projectiles.Target = {
				id = id,
				team = slot.team,
				history = history,
				live = false,
				room = arena.spawnRooms[slot.team],
			}
			table.insert(targets, target)
			targetOf[id] = target
		end
		Bots.sync(service.bots, state, botSkill, service.poses, now)
		local message = watchMessage(state)
		for player in service.audience do
			ctx.send(player, table.clone(message))
		end
		ctx.dirty()
	end

	-- Who may be hit this instant, and where each body last was (the early reject).
	local function refreshTargets(state: State, now: number)
		local poses = service.poses
		for _, target in targets do
			local pose = poses[target.id]
			if pose == nil then
				target.live = false
			else
				target.live = Rules.canBeHit(state, target.id, now)
				target.x, target.y, target.z = pose.x, pose.y, pose.z
			end
		end
	end

	-- Rules said yes: `by` tagged `id` out.
	local function tagged(state: State, by: number, id: number, ball: number, x: number, y: number, z: number)
		stats.tags += 1
		local target = targetOf[id]
		if target then
			target.live = false
		end
		local person = bySeat[id]
		if person then
			person.out = true -- its Moves are dropped and its pose held, until its respawn
		end
		local victim, shooter = state.slots[id], state.slots[by]
		ctx.broadcast({
			kind = "paintball_tag",
			by = by,
			id = id,
			ball = ball,
			scores = { state.scores[1], state.scores[2] },
			tags = if shooter then shooter.tags else 0,
			outs = if victim then victim.outs else 0,
			at = if victim then victim.outUntil else stepNow,
			x = x,
			y = y,
			z = z,
		})
		table.insert(heard, { kind = "tag", id = id, by = by, x = x, y = y, z = z })
	end

	-- A ball ended (Projectiles hands each over the moment it does, before the next ball is stepped).
	local function onEnd(ball: Projectiles.Ball)
		local state = matchState()
		if state == nil then
			return
		end
		local hit = ball.hitBody
		if hit ~= 0 then
			local pose = service.poses[hit]
			local lx, ly, lz =
				Wire.toBody(ball.hx, ball.hy, ball.hz, ball.bx, ball.by, ball.bz, if pose then pose.yaw else 0)
			table.insert(splatBatch, Splats.body(pools, ball.id, ball.shooter, ball.team, hit, lx, ly, lz))
			table.insert(heard, { kind = "ended", id = ball.shooter, x = ball.hx, y = ball.hy, z = ball.hz })
			if Rules.tag(state, ball.shooter, hit, stepNow, ball.born) then
				tagged(state, ball.shooter, hit, ball.id, ball.hx, ball.hy, ball.hz)
			end
		elseif ball.hitWall then
			local face = Wire.faceOf(ball.nx, ball.ny, ball.nz)
			table.insert(
				splatBatch,
				Splats.wall(pools, ball.id, ball.shooter, ball.team, face, ball.hx, ball.hy, ball.hz)
			)
			table.insert(heard, { kind = "ended", id = ball.shooter, x = ball.hx, y = ball.hy, z = ball.hz })
		end
	end

	-- A ball is born (a person's accepted click, a bot's command).
	local function launch(
		id: number,
		team: number,
		ox: number,
		oy: number,
		oz: number,
		vx: number,
		vy: number,
		vz: number,
		rewind: number,
		born: number
	): Projectiles.Ball
		local ball = Projectiles.fire(sim, id, team, ox, oy, oz, vx, vy, vz, rewind, born)
		stats.balls += 1
		table.insert(
			shotBatch,
			{ ball = ball.id, id = id, t = born, ox = ox, oy = oy, oz = oz, vx = vx, vy = vy, vz = vz }
		)
		table.insert(heard, { kind = "born", id = id, x = ox, y = oy, z = oz, vx = vx, vy = vy, vz = vz })
		return ball
	end

	-- The born balls and the splats of this tick go out to the audience.
	local function flushBatches()
		if #shotBatch > 0 then
			local per = Wire.SHOTS_PER_MESSAGE
			for from = 1, #shotBatch, per do
				toAudience(
					"Paintball.Shot",
					Wire.pack(Wire.Shot, table.move(shotBatch, from, math.min(#shotBatch, from + per - 1), 1, {}))
				)
			end
			shotBatch = {}
		end
		if #splatBatch > 0 then
			toAudience("Splat", Wire.pack(Wire.Splat, splatBatch))
			splatBatch = {}
		end
	end

	-- A "respawn" event: the slot stands at its spawn point, with a new placement number if it is a person.
	local function placeSlot(state: State, e: Event, now: number)
		local id = e.id
		local slot = if id then state.slots[id] else nil
		if id == nil or slot == nil or not slot.on then
			return
		end
		local team = e.team or slot.team
		local sp = spawnOf(team, e.spawn)
		local person = bySeat[id]
		local placeNumber = 0
		if person ~= nil then
			Stream.placed(person, sp.x, sp.y, sp.z, sp.yaw, now, state.feel, true)
			placeNumber = person.place
			placeMemo[person.player] = placeNumber
			local body = ctx.bodyOf(person.player)
			if body ~= nil then
				put(body, sp.x, sp.y, sp.z, sp.yaw)
			end
		end
		local pose = service.poses[id]
		if pose == nil then
			pose = { x = 0, y = 0, z = 0, yaw = 0, pitch = 0, crouch = 0, bits = 0 }
			service.poses[id] = pose
		end
		pose.x, pose.y, pose.z, pose.yaw, pose.pitch, pose.crouch, pose.bits = sp.x, sp.y, sp.z, sp.yaw, 0, 0, 0
		if botSkill[id] ~= nil then
			Bots.place(service.bots, id, pose, now)
		end
		local history = histories[id]
		if history then
			PoseHistory.clear(history) -- a new life: nothing of the old one is rewound to
		end
		local target = targetOf[id]
		if target then
			target.team = team
			target.room = arena.spawnRooms[team]
		end
		ctx.broadcast({
			kind = "paintball_respawn",
			id = id,
			x = sp.x,
			y = sp.y,
			z = sp.z,
			yaw = sp.yaw,
			at = e.at or now,
			place = placeNumber,
		})
	end

	-- The third refusal in a second: the real body goes back on the last accepted pose.
	local function correct(person: Person, state: State, why: string?, now: number)
		local a = person.anchor
		-- (an anchor left in mid-air, by a fall that never ended, is no place to be put back to: the body
		-- goes to the walking surface under it)
		local ground = arena.ground(a.x, a.y, a.z)
		if ground ~= nil and a.y > ground + Body.JUMP_HEIGHT + T.jumpSlack then
			local fixed = table.clone(a)
			fixed.y = ground
			a = fixed
		end
		Stream.placed(person, a.x, a.y, a.z, a.yaw, now, state.feel, false)
		placeMemo[person.player] = person.place
		local body = ctx.bodyOf(person.player)
		if body ~= nil then
			put(body, a.x, a.y, a.z, a.yaw)
		end
		stats.corrections += 1
		ctx.send(person.player, {
			kind = "paintball_correct",
			x = a.x,
			y = a.y,
			z = a.z,
			yaw = a.yaw,
			why = if why ~= nil and (Contract.WHY :: { [string]: string })[why] ~= nil then why else "wall",
			place = person.place,
		})
	end

	-- A slot's magazine as it stands at `now`, without touching it: rounds, and when a running reload ends.
	local function magazineOf(state: State, id: number, now: number): (number, number?)
		local slot = state.slots[id]
		if slot == nil then
			return R.magazine, nil
		end
		local mag = slot.mag
		local done = mag.reloadDoneAt
		if done ~= nil and now >= done then
			return mag.capacity, nil
		end
		return math.clamp(mag.rounds, 0, R.magazine), done
	end

	-- The snapshot tick T: every slot's pose, quantised, into its history and out to the audience.
	local CLIENT_BITS = bit32.bor(BIT.crouch, BIT.sprint, BIT.air)
	local function snapshot(state: State, tick: number)
		local bodies: { SnapBody } = {}
		local feel = state.feel
		for id, slot in state.slots do
			if not slot.on then
				continue
			end
			local pose = service.poses[id]
			if pose == nil then
				continue -- (seated this very step: its placement comes with the next)
			end
			local person = bySeat[id]
			if person ~= nil then
				if person.place == 0 then
					continue
				end
				if not person.out then
					local pt = Clock.poseTime(person.up, tick)
					local x, y, z, yaw, pitch, bits = Stream.poseAt(person, pt)
					-- a shot is seen to leave along the puppet's look (Stream, "the aim is the look")
					local shown = person.shotLook
					if
						shown ~= nil
						and pt >= shown.t - 1 / Clock.SEND_HZ
						and pt <= shown.t + Contract.TRUST.aimShown
					then
						yaw, pitch = shown.yaw, shown.pitch
					end
					pose.x, pose.y, pose.z, pose.yaw, pose.pitch = x, y, z, yaw, pitch
					-- (the crouch of that very moment, on the Moves' own line: Stream, "the crouch")
					pose.crouch = Stream.ease(person, pt, feel)
					pose.bits = bits
				end
			end
			local bits = bit32.bor(bit32.band(pose.bits, CLIENT_BITS), Rules.bits(state, id, tick))
			if ArenaModule.inRoom(arena.spawnRooms[slot.team], pose.x, pose.y + 0.1, pose.z) then
				bits = bit32.bor(bits, BIT.safe)
			end
			local qx, qy, qz, qc = Wire.quantPose(pose.x, pose.y, pose.z, pose.crouch)
			local history = histories[id]
			if history ~= nil then
				PoseHistory.push(history, tick, qx, qy, qz, qc)
			end
			if person ~= nil then
				-- (a bot's pose is its brain's own: the service never writes it)
				pose.x, pose.y, pose.z, pose.crouch, pose.bits = qx, qy, qz, qc, bits
			end
			table.insert(bodies, {
				id = id,
				x = qx,
				y = qy,
				z = qz,
				yaw = wrapAngle(pose.yaw),
				pitch = math.clamp(pose.pitch, -math.pi / 2, math.pi / 2),
				crouch = qc,
				bits = bits,
			})
		end
		snapSeq += 1
		stats.snapshots += 1
		toAudience("Paintball.Snap", Wire.encodeSnap(tick, snapSeq, service.match, bodies))
	end

	-- The audience, and the sweep of anybody inside the arena who is not in the match.
	local function audiencePass(state: State)
		local seen: { [any]: boolean } = {}
		for _, key in ctx.seated() do
			if not isBot(key) then
				seen[key] = true
			end
		end
		for _, p in ctx.town.people() do
			local x, y, z = ArenaModule.toLocal(place, p.x, p.y, p.z)
			if ArenaModule.inVolume(x, y, z, ArenaModule.AUDIENCE_MARGIN) then
				seen[p.key] = true
				if ArenaModule.inVolume(x, y, z) and ctx.seatOf(p.key) == nil then
					local body = ctx.bodyOf(p.key)
					if body ~= nil then
						engine.ghost(body, false)
						put(body, arena.lobby.x, arena.lobby.y, arena.lobby.z, arena.lobby.yaw)
					end
				end
			end
		end
		-- RODENT-FREE (PB-11): a squirrel or the Spicy Rodent inside the station, the annex included (its front door
		-- is open), is put back out on the street in front of it and told why (the town's own knock, as a bowling
		-- lane in play does). Found at the review: the annex was open to animals.
		local animals, knock = ctx.opts.animals, ctx.opts.knock
		if animals ~= nil and knock ~= nil then
			for _, a in animals() do
				local x, y, z = ArenaModule.toLocal(place, a.x, a.y, a.z)
				if ArenaModule.inVolume(x, y, z) or Stream.inAnnex(x, y, z) then
					local wx, wy, wz = ArenaModule.toWorld(place, STREET.x, STREET.y, STREET.z)
					knock(a.id, wx, wy, wz, ANIMALS_OUT)
				end
			end
		end
		for player in seen do
			if not service.audience[player] then
				admit(player, state)
			end
		end
		for player in service.audience do
			if not seen[player] then
				service.audience[player] = nil
				ctx.send(player, { kind = "paintball_unwatch" })
			end
		end
	end

	-- ROLLING ON: the end card has had its time; every bot off, the next match with whoever is still seated.
	local function roll()
		for _, key in ctx.seated() do
			if isBot(key) then
				ctx.removeComputer(key)
			end
		end
		ctx.again()
	end

	local function onStart(now: number)
		local state = matchState()
		if state == nil then
			return
		end
		service.match += 1
		Rules.tune(state, service.feel)
		Rules.sync(state, now)
		-- nothing of the last match is left: paint, balls, where anybody stood
		Splats.reset(pools)
		sim = Projectiles.forArena(arena, state.feel)
		table.clear(histories)
		table.clear(service.poses)
		table.clear(occupant)
		table.clear(targets)
		table.clear(targetOf)
		table.clear(botSkill)
		heard, shotBatch, splatBatch = {}, {}, {}
		-- the people still seated were dealt new seats
		table.clear(bySeat)
		for player, person in people do
			local seat = ctx.seatOf(player)
			if seat == nil then
				people[player] = nil
			else
				person.seat = seat
				bySeat[seat] = person
				Stream.restart(person, now)
			end
		end
		-- PEOPLE KEEP THEIR SIDES, in seat order, unless the side is already full of people. "Full" is
		-- counted over the sides people are GOING to, not the ones the new deal happened to hand them: at
		-- sixteen people the deal fills both sides, and counting those would leave two who had crossed
		-- on each other's sides, each waiting for the other to move first.
		local going = { 0, 0 }
		local final: { [number]: number } = {}
		for seat = 1, #state.slots do
			local person = bySeat[seat]
			local want = if person then sides[person.player] else nil
			if want ~= nil and going[want] < R.teamMax then
				final[seat] = want
				going[want] += 1
			end
		end
		-- (anybody with no side to go back to stays where they were dealt, if there is room there)
		for seat = 1, #state.slots do
			if bySeat[seat] ~= nil and final[seat] == nil then
				local dealt = state.slots[seat].team
				local team = if going[dealt] < R.teamMax then dealt else 3 - dealt
				final[seat] = team
				going[team] += 1
			end
		end
		for seat = 1, #state.slots do
			local team = final[seat]
			if team ~= nil and state.slots[seat].team ~= team then
				Rules.assign(state, seat, team)
			end
		end
		for player in placed do
			if ctx.seatOf(player) == nil then
				toLobby(player)
			end
		end
		rosterDirty = true -- (the fill comes right after this event: the next step balances and tells the audience)
		nextSnap = now
		monitors = nil -- (looked for again: the building may have been baked or streamed in since)
	end

	local function onLeft(e: ServerGame.Event, _now: number)
		local key = e.key
		rosterDirty = true
		if isBot(key) then
			return
		end
		local person = people[key]
		if person == nil then
			return
		end
		people[key] = nil
		if bySeat[person.seat] == person then
			bySeat[person.seat] = nil
		end
		placeMemo[key] = person.placeFrom
		sides[key] = nil
		toLobby(key)
		-- a bot takes the seat (and its side) at once, while the match is on and a person remains
		if ctx.session.phase == "playing" then
			for _, other in ctx.seated() do
				if not isBot(other) then
					ctx.addComputer()
					break
				end
			end
		end
	end

	local function onReset()
		for player in placed do
			toLobby(player)
		end
		table.clear(people)
		table.clear(bySeat)
		table.clear(sides)
		table.clear(histories)
		table.clear(service.poses)
		table.clear(occupant)
		table.clear(targets)
		table.clear(targetOf)
		table.clear(botSkill)
		Projectiles.clear(sim)
		Splats.reset(pools)
		heard, shotBatch, splatBatch = {}, {}, {}
		rosterDirty = false
		monitors = nil
		for player in service.audience do
			ctx.send(player, { kind = "paintball_unwatch" })
		end
		table.clear(service.audience)
	end

	function service.join(_self: Service, player: any, via: ServerGame.StationDef): (boolean, string?)
		if hw == nil then
			return false, Contract.textFor("closed")
		end
		if via.id == Contract.DESK then
			-- the pass desk sells and seats nobody: the framework shows the words either way
			local _, words = pass.buy(player)
			return false, words
		end
		if ctx.seatOf(player) ~= nil then
			return true, nil
		end
		local s = ctx.session
		if s.phase == "done" then
			return false, Contract.nextMatch(s.doneEnds - ctx.now() - R.endCardSpare)
		end
		local fit = d.fit
		if fit then
			local ok, why = fit(player)
			if not ok then
				return false, Contract.textFor(why or "infected")
			end
		end
		if not pass.has(player) then
			return false, Contract.textFor("pass")
		end
		local humans = 0
		local seatedBots: { any } = {}
		for _, key in ctx.seated() do
			if isBot(key) then
				table.insert(seatedBots, key)
			else
				humans += 1
			end
		end
		if humans >= R.slots then
			return false, Contract.textFor("full")
		end
		-- THE ROSTER: a person who joins a match takes a bot's seat, on the side with fewer people
		local state = matchState()
		if state ~= nil and s.phase == "playing" and #seatedBots > 0 then
			local count = { 0, 0 }
			for seat, slot in state.slots do
				local key = if slot.on then holderOf(seat) else nil
				if key ~= nil and not isBot(key) then
					count[slot.team] += 1
				end
			end
			local want = if count[1] < count[2] then 1 elseif count[2] < count[1] then 2 else 0
			local pick: any, pickSeat, pickOnSide = nil, math.huge, false
			for _, key in seatedBots do
				local seat = ctx.seatOf(key)
				local slot = if seat then state.slots[seat] else nil
				if seat ~= nil and slot ~= nil then
					local onSide = want == 0 or slot.team == want
					if (onSide and not pickOnSide) or (onSide == pickOnSide and seat < pickSeat) then
						pick, pickSeat, pickOnSide = key, seat, onSide
					end
				end
			end
			if pick ~= nil then
				ctx.removeComputer(pick)
			end
		end
		return true, nil
	end

	function service.joined(_self: Service, player: any, seat: number?, _via: ServerGame.StationDef)
		if hw == nil or seat == nil then
			return
		end
		local state = matchState()
		if state == nil then
			return
		end
		local had = people[player]
		if had ~= nil and had.seat == seat then
			return -- (seated already, and pressed the prompt again)
		end
		local now = ctx.stamp()
		local person = Stream.new(player, now, placeMemo[player])
		person.seat = seat
		people[player] = person
		bySeat[seat] = person
		local body = ctx.bodyOf(player)
		if body ~= nil then
			engine.ghost(body, true)
		end
		placed[player] = true
		if not service.audience[player] then
			admit(player, state)
		end
		refreshRoster(now)
	end

	-- THE OWNER'S TUNING (the verb "tune" { name, value }, from the owner's chat command "/pb": Client/Minigames/
	-- Paintball/PaintballClient). Only Deps.owner may; anyone else is told so. The name is a feel number
	-- (Contract.FEEL_KEYS: debug "tune", from the next match), "rewind" (debug "rewind") or "botSkill" (debug
	-- "botSkill"); with no name, the values as they stand. The owner is told in words what changed
	-- ("paintball_tuned"); a value out of range is refused with its range.
	local isOwner = d.owner or placeOwner
	local function tuneNow(): string
		local f = service.feel :: any
		local parts = {}
		for _, key in Contract.FEEL_KEYS do
			table.insert(parts, `{key} {f[key]}`)
		end
		table.insert(parts, `rewind {Clock.MAX_REWIND}`)
		table.insert(parts, `botSkill {(service.bots :: any).skill or 0}`)
		return table.concat(parts, ", ")
	end
	local function tune(player: any, args: { any }): (boolean, string?)
		if not isOwner(player) then
			return false, "Only the place's owner can tune paintball."
		end
		local key, value = args[1], tonumber(args[2])
		if key == nil or key == "" then
			ctx.send(player, { kind = "paintball_tuned", text = `Paintball now: {tuneNow()}` })
			return true, nil
		end
		if type(key) ~= "string" or TUNE_WORDS[key] == nil then
			return false, `Tune one of: {table.concat(Contract.FEEL_KEYS, ", ")}, rewind, botSkill`
		end
		local was: any
		if key == "rewind" then
			was = Clock.MAX_REWIND
		elseif key == "botSkill" then
			was = (service.bots :: any).skill or 0
		else
			was = (service.feel :: any)[key]
		end
		local ok, why
		if key == "rewind" or key == "botSkill" then
			ok, why = service:debug(key, value)
		else
			ok, why = service:debug("tune", key, value)
		end
		if not ok then
			return false, why
		end
		ctx.send(player, {
			kind = "paintball_tuned",
			text = `{TUNE_WORDS[key]}: {was} -> {value}, from the next match`,
		})
		return true, nil
	end

	function service.command(_self: Service, player: any, verb: string, args: { any }): (boolean, boolean?, string?)
		if verb == "start" or verb == "again" or verb == "addai" or verb == "mode" then
			return true, false, Contract.textFor("phase")
		end
		if verb == "tune" then
			local ok, why = tune(player, args)
			return true, ok, why
		end
		return false, nil, nil
	end

	-- Which bot of `team` trades places on the "side" verb. The trade puts that bot back in a spawn room with
	-- a full magazine and its protection, so the one that pays least for it: a bot that is itself tagged out,
	-- then one standing in its own spawn room, then (only then) one in the fight; the lowest seat of the
	-- first kind there is. nil: that team has no bot.
	local function sideBot(state: State, team: number): number?
		local best: number?, rank = nil, math.huge
		for id, theirs in state.slots do
			if theirs.on and theirs.team == team and botSkill[id] ~= nil then
				local pose = service.poses[id]
				local r = if theirs.out
					then 1
					elseif
						pose ~= nil and ArenaModule.inRoom(arena.spawnRooms[team], pose.x, pose.y + 0.1, pose.z)
					then 2
					else 3
				if r < rank or (r == rank and best ~= nil and id < best) then
					best, rank = id, r
				end
			end
		end
		return best
	end

	function service.input(_self: Service, player: any, seat: number, verb: string, args: { any }): (boolean?, string?)
		local state = matchState()
		local person = people[player]
		if state == nil or person == nil then
			return false, Contract.textFor("phase")
		end
		local now = ctx.stamp()
		if verb == "reload" then
			local t = ServerGame.num(args[1], now)
			local _, _, _, _, m = Clock.stamp(now, now, t, person.lastM, person.up.lag)
			if Rules.reload(state, seat, m) then
				return true, nil
			end
			return false, Contract.textFor("phase")
		elseif verb == "side" then
			if rosterDirty then
				refreshRoster(now)
			end
			local slot = state.slots[seat]
			local flying = false
			for _, ball in sim.balls do
				if ball.shooter == seat then
					flying = true
					break
				end
			end
			local since = now - (sideAt[player] or -math.huge)
			if
				slot ~= nil
				and slot.on
				and not flying
				and since >= SIDE_EVERY
				and (state.phase == "briefing" or (person.out and now < state.liveAt + SIDE_LIVE))
			then
				local mine, other = slot.team, 3 - slot.team
				local id = sideBot(state, other)
				if id ~= nil then
					sideAt[player] = now
					Rules.assign(state, seat, other)
					Rules.assign(state, id, mine)
					if not person.out then
						-- (the room it stands in is the other side's from this moment: the Moves it sends
						-- from there, until the match has placed it in its own, are dropped, not refused)
						person.owedSince = now
					end
					refreshRoster(now)
					return true, nil
				end
			end
			return false, Contract.textFor("side")
		end
		return false, Contract.textFor("phase")
	end

	-- A CLICK THAT OVERTOOK ITS OWN MOVES WAITS FOR THEM (settled at the review, 2026-11-13). The click is
	-- reliable and the Moves are not: on a slow, lossy link a click can arrive while the Moves that tell how the
	-- body stood up, hopped or stepped before it are still on their way (found: a client at 300 ms with one packet
	-- in twenty lost, crouched in its newest heard Move a quarter of a second old, fired standing from a hop and
	-- was refused "origin"). Such a click (its stamp more than WAIT_PAST past the newest Move heard) is held
	-- until a Move stamped at or after it comes, or WAIT_MOST has passed, and is then judged as any other: late,
	-- so at its own stamp for where it left from (Stream, "a click that came late"). A shooter's later clicks
	-- queue behind it, in order. Nothing is gained by withholding Moves: the click is judged no earlier.
	local WAIT_PAST = 1.5 / Clock.SEND_HZ
	local WAIT_MOST = 0.25
	local waiting: { { player: any, rec: { [string]: number }, at: number } } = {}
	local judgeFire: (player: any, rec: { [string]: number }) -> ()

	local function newestMoveT(person: Person): number
		local moves = person.moves
		return if #moves > 0 then moves[#moves].t else person.anchor.t
	end

	-- the waiting clicks whose Moves have come, or whose wait is over, are judged (oldest first, each shooter's
	-- in order)
	local function judgeWaiting(now: number)
		local blocked: { [any]: boolean } = {}
		local i = 1
		while i <= #waiting do
			local w = waiting[i]
			local person = people[w.player]
			if person == nil then
				table.remove(waiting, i)
			elseif
				not blocked[w.player]
				and (newestMoveT(person) >= w.rec.ft - 1 / 120 or now - w.at >= WAIT_MOST or person.out)
			then
				table.remove(waiting, i)
				judgeFire(w.player, w.rec)
			else
				blocked[w.player] = true
				i += 1
			end
		end
	end

	function service.step(_self: Service, dt: number)
		if hw == nil then
			return
		end
		local state = matchState()
		if state == nil then
			table.clear(waiting)
			return
		end
		if #waiting > 0 then
			judgeWaiting(ctx.stamp())
		end
		local started = os.clock()
		stats.steps += 1
		local now = ctx.stamp()
		stepNow = now
		local s = ctx.session
		local playing = s.phase == "playing"
		-- 0. the model is slaved to the shared clock
		Rules.sync(state, now)
		if not playing and s.doneEnds - ctx.now() <= R.endCardSpare then
			roll()
			return
		end
		if rosterDirty then
			refreshRoster(now)
		end
		-- 1. what the match did
		for _, e in Rules.drain(state) do
			if e.kind == "respawn" then
				placeSlot(state, e, now)
			elseif e.kind == "phase" then
				ctx.dirty()
				if e.phase == "live" then
					for _, person in people do
						person.idleAt = now -- idleness is counted over live play only
					end
				end
			elseif e.kind == "reload" then
				local person = if e.id then bySeat[e.id] else nil
				if person ~= nil then
					ctx.send(person.player, { kind = "paintball_reload", id = e.id, at = e.at or now })
				end
			end
		end
		-- 2. people: silence, idleness, the way out
		local leaving: { { any } }? = nil
		for player, person in people do
			local _, drop = Stream.silent(person, now)
			local why: string? = nil
			if drop then
				why = "dropped"
			elseif playing and person.place ~= 0 then
				if state.phase == "live" and now - person.idleAt > R.idleSecs then
					why = "idle"
				else
					local a = person.anchor
					for _, room in arena.exits do
						if ArenaModule.inRoom(room, a.x, a.y + 0.1, a.z) then
							why = "exit"
							break
						end
					end
				end
			end
			if why ~= nil then
				leaving = leaving or {}
				table.insert(leaving :: { { any } }, { player, why })
			end
		end
		if leaving then
			for _, pair in leaving do
				ctx.leave(pair[1], pair[2], Contract.textFor(pair[2]))
			end
			if matchState() ~= state then
				return -- (the last person went: the table was reset under us)
			end
		end
		local botsMs, ballsMs = 0, 0
		if playing then
			-- 3. the bots
			local t3 = os.clock()
			local commands = Bots.step(service.bots, state, service.poses, heard, now, dt)
			heard = {}
			for _, c in commands do
				local id = c.id
				local slot, pose = state.slots[id], service.poses[id]
				if slot == nil or pose == nil or botSkill[id] == nil then
					continue
				end
				if c.kind == "fire" then
					-- judged by the one judge the bots' own checks use (Bots.judge): along its own look, from its
					-- eye, never from a spawn room, never inside the sprint delay, and only when the match agrees
					if Bots.judge(service.bots, state, id, pose, c, now) then
						local vx, vy, vz = c.vx or 0, c.vy or 0, c.vz or 0
						local len = math.sqrt(vx * vx + vy * vy + vz * vz)
						local ex, ey, ez = Body.eyePoint(pose.x, pose.y, pose.z, pose.crouch)
						local k = state.feel.ballSpeed / len
						launch(id, slot.team, ex, ey, ez, vx * k, vy * k, vz * k, 0, now)
					end
				elseif c.kind == "reload" then
					Rules.reload(state, id, now)
				elseif c.kind == "say" then
					local line = c.line
					if line ~= nil and (Contract.LINES :: { [string]: string })[line] ~= nil then
						ctx.broadcast({ kind = "paintball_say", id = id, line = line, n = c.n })
					end
				end
			end
			botsMs = (os.clock() - t3) * 1000
			-- 4. the balls
			local t4 = os.clock()
			refreshTargets(state, now)
			Projectiles.step(sim, now, dt, targets, onEnd)
			ballsMs = (os.clock() - t4) * 1000
		end
		flushBatches()
		-- 5. the snapshot tick
		if now + 1e-6 >= nextSnap then
			local interval = 1 / Clock.SNAP_HZ
			nextSnap = if now - nextSnap > 2 * interval then now + interval else nextSnap + interval
			snapshot(state, now)
		end
		-- 6. the audience and the sweep
		if now >= nextAudience then
			nextAudience = now + Clock.AUDIENCE_SECS
			audiencePass(state)
		end
		local stepMs = (os.clock() - started) * 1000
		stats.stepMs = stepMs
		stats.botsMs = botsMs
		stats.ballsMs = ballsMs
		stats.restMs = math.max(0, stepMs - botsMs - ballsMs)
	end

	function service.event(_self: Service, e: ServerGame.Event)
		if hw == nil then
			return
		end
		local kind = e.kind
		if kind == "start" then
			onStart(ctx.stamp())
		elseif kind == "left" then
			onLeft(e, ctx.stamp())
		elseif kind == "done" then
			local state = matchState()
			if state ~= nil then
				for player, person in people do
					local slot = state.slots[person.seat]
					if slot ~= nil then
						sides[player] = slot.team
					end
				end
			end
		elseif kind == "reset" then
			onReset()
		end
	end

	function service.state(self: Service, player: any, seat: number?): Extras?
		local state = matchState()
		local extras: Extras = {
			match = self.match,
			bots = {},
			rounds = R.magazine,
			reloadAt = 0,
			shot = 0,
			feel = if state then state.feel else self.feel,
		}
		if state ~= nil then
			for id, slot in state.slots do
				extras.bots[id] = slot.on and isBot(holderOf(id))
			end
			if seat ~= nil then
				local rounds, reloadAt = magazineOf(state, seat, ctx.stamp())
				extras.rounds = rounds
				extras.reloadAt = reloadAt or 0
			end
			local person = people[player]
			if person ~= nil then
				extras.shot = person.shot
			end
		end
		return extras
	end

	function service.inPlay(_self: Service, player: any, body: Model?): boolean
		local person = people[player]
		if person == nil or person.place == 0 then
			return true -- not placed yet: still at the arena door
		end
		if ctx.stamp() - person.placedAt <= T.placeGrace then
			return true
		end
		if body == nil then
			return false
		end
		local wx, wy, wz = engine.positionOf(body)
		if wx == nil or wy == nil or wz == nil then
			return true
		end
		local x, y, z = ArenaModule.toLocal(place, wx, wy, wz)
		return ArenaModule.inVolume(x, y, z, 4)
	end

	-- the monitors: the lobby's and the old sets on each floor
	local function clockText(seconds: number): string
		local left = math.max(0, math.ceil(seconds))
		return string.format("%d:%02d", left // 60, left % 60)
	end

	local function screenText(view: { [string]: any }): string
		local g = view.game
		if (view.phase ~= "playing" and view.phase ~= "done") or type(g) ~= "table" then
			return ctx.station.label
		end
		local teams = Contract.TEAMS
		local scores = if type(g.scores) == "table" then g.scores else { 0, 0 }
		local line = `{string.upper(teams[1].name)} {scores[1] or 0}  -  {scores[2] or 0} {string.upper(teams[2].name)}`
		if view.phase == "done" or g.phase == "ended" then
			local result = view.result
			return `{line}\n{if type(result) == "table" and type(result.text) == "string"
				then result.text
				else "FULL TIME"}`
		end
		local left = clockText((tonumber(g.endsAt) or 0) - ctx.stamp())
		return `{line}\n{if g.phase == "briefing" then "STARTS IN " else ""}{left}`
	end

	function service.screen(_self: Service, view: { [string]: any })
		if hw == nil then
			return
		end
		local list: { any } = monitors or {}
		if monitors == nil then
			for _, part in hw:GetDescendants() do
				if part.Name == ArenaModule.MONITOR and part:IsA("BasePart") then
					table.insert(list, part)
				end
			end
			monitors = list
		end
		local text = screenText(view)
		for _, part in list do
			local gui = part:FindFirstChild("PaintballScreen")
			if gui == nil then
				gui = Instance.new("SurfaceGui")
				gui.Name = "PaintballScreen"
				gui.Parent = part
				local label = Instance.new("TextLabel")
				label.Name = "Text"
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
				label.TextColor3 = Color3.fromRGB(235, 235, 225)
				label.TextScaled = true
				label.Parent = gui
			end
			local label = gui:FindFirstChild("Text")
			if label ~= nil then
				label.Text = text
			end
		end
	end

	function service.sig(_self: Service, view: { [string]: any }): any
		if hw == nil then
			return false
		end
		-- (the clock on the monitors moves once a second: that is how often the framework asks)
		return screenText(view)
	end

	function service.prompt(_self: Service): (string?, string?)
		return "Paintball", nil
	end

	function service.doneText(_self: Service, view: { [string]: any }): string?
		local result = view.result
		return if type(result) == "table" and type(result.text) == "string" then result.text else nil
	end

	function service.debug(self: Service, ...: any): (boolean, string?)
		local what, key, value = ...
		if what == "tune" then
			-- one number of the next match's feel (the owner's playtest: a faster ball, a shorter reload)
			local feel, why = Contract.tuned(self.feel, tostring(key), value)
			if feel == nil then
				return false, why
			end
			self.feel = feel
			return true, nil
		elseif what == "rewind" then
			-- the furthest back a ball is judged (Clock.MAX_REWIND, 0.25 s in the contract), for the owner's
			-- playtest at a slow connection: at 300 ms a quarter of a second agrees with the shooter's screen on
			-- about 90 % of shots, 0.3 s on 95 % (tests/isolated/paintball_server_fire). The server's own reading
			-- only, in force from the next match (the match in play keeps its sim's bound); the clients' drawing of
			-- other people's balls still clamps at the contract's number (cosmetic: their own hits are theirs)
			local secs = tonumber(key)
			if secs == nil or secs ~= secs or secs < REWIND_MIN or secs > REWIND_MAX then
				return false, `debug rewind: seconds from {REWIND_MIN} to {REWIND_MAX}`
			end
			(Clock :: any).MAX_REWIND = secs
			return true, nil
		elseif what == "botSkill" then
			-- how hard the bots are, for the owner's playtest (the bots' Opts.skill: added to every bot's
			-- Contract.BOTS skill), for every bot seated from now on: the next match's
			local skill = tonumber(key)
			if skill == nil or skill ~= skill or skill < -0.5 or skill > 0.5 then
				return false, "debug botSkill: -0.5 to 0.5"
			end
			(self.bots :: any).skill = skill
			return true, nil
		end
		local state = matchState()
		if hw == nil or state == nil then
			return false, Contract.textFor("closed")
		end
		local now = ctx.stamp()
		stepNow = now
		if what == "tag" then
			-- slot `key` tags slot `value` out, through the match's own verdict
			local by, id = tonumber(key), tonumber(value)
			local pose = if id then self.poses[id] else nil
			if by == nil or id == nil or state.slots[by] == nil or state.slots[id] == nil or pose == nil then
				return false, "debug tag: by and id are slots of the match"
			end
			if not Rules.tag(state, by, id, now, now) then
				return false, Contract.textFor("phase")
			end
			tagged(state, by, id, 0, pose.x, pose.y + ArenaModule.CHEST, pose.z)
			return true, nil
		elseif what == "end" then
			-- the clock of the phase the match is in runs out now (in the briefing: play begins; live: it ends)
			state.endsAt = now
			return true, nil
		end
		return false, "debug: tag, end, tune, rewind or botSkill"
	end

	function service.onMove(_self: Service, player: any, rec: { [string]: number })
		local person = people[player]
		if person == nil then
			return
		end
		local state = matchState()
		local slot = if state then state.slots[person.seat] else nil
		if state == nil or slot == nil then
			return
		end
		local now = ctx.stamp()
		local bx: number?, by: number?, bz: number? = nil, nil, nil
		local body = ctx.bodyOf(player)
		if body ~= nil then
			local wx, wy, wz = engine.positionOf(body)
			if wx ~= nil and wy ~= nil and wz ~= nil then
				bx, by, bz = ArenaModule.toLocal(place, wx, wy, wz)
			end
		end
		local verdict, why, rule =
			Stream.judge(person, rec, now, arena, state.feel, arena.spawnRooms[3 - slot.team], bx, by, bz)
		if verdict == "accepted" then
			stats.movesAccepted += 1
		elseif verdict == "dropped" then
			stats.movesDropped += 1
		else
			stats.movesRefused += 1
			local key = rule or "?"
			stats.movesRefusedBy[key] = (stats.movesRefusedBy[key] or 0) + 1
			if Stream.refused(person, now) then
				correct(person, state, why, now)
			end
		end
	end

	function service.onFire(_self: Service, player: any, rec: { [string]: number })
		local person = people[player]
		if person == nil then
			return
		end
		local now = ctx.stamp()
		local queued = false
		for _, w in waiting do
			if w.player == player then
				queued = true
			end
		end
		local behind = rec.ft - newestMoveT(person) > WAIT_PAST and rec.ft <= now
		if queued or (behind and not person.out and not (Stream.silent(person, now))) then
			table.insert(waiting, { player = player, rec = rec, at = now })
			return
		end
		judgeFire(player, rec)
	end

	judgeFire = function(player: any, rec: { [string]: number })
		local person = people[player]
		if person == nil then
			return
		end
		local state = matchState()
		local id = person.seat
		local slot = if state then state.slots[id] else nil
		if state == nil or slot == nil then
			return
		end
		local now = ctx.stamp()
		stepNow = now
		person.shot = rec.shot
		local why: string? = nil
		local ballId: number? = nil
		if Stream.silent(person, now) then
			why = "stale" -- a
		else
			-- b
			local rtt: number? = nil
			if engine.ping ~= nil then
				local ping = engine.ping(player)
				if ping ~= nil then
					rtt = ping + Contract.TRUST.pingSlack
				end
			end
			local f, late, rewind, clamped, m = Clock.stamp(now, rec.vt, rec.ft, person.lastM, person.up.lag, rtt)
			if clamped then
				stats.rewindsClamped += 1
			end
			local dx, dy, dz = rec.dx, rec.dy, rec.dz
			local len = math.sqrt(dx * dx + dy * dy + dz * dz)
			-- c, d, e: the sprint window, the spawn rooms and the origin, at f
			local at = f
			why = Stream.clickOk(person, f, rec.ox, rec.oy, rec.oz, arena, state.feel)
			if why ~= nil then
				-- a click that came later than its own delay explains (a lost packet sent again) is also
				-- judged where its body was when it was clicked, no further back than the shooter's own
				-- window, and whether it could fire is held to f as well (Stream, "a click that came late")
				local click = math.max(rec.ft, now - Stream.lateWindow(person, rtt))
				if
					click < f - 1e-6
					and Stream.lateClickOk(person, click, f, rec.ox, rec.oy, rec.oz, arena, state.feel, now) == nil
				then
					why = nil
					at = click
				end
			end
			if why ~= nil and person.out then
				-- (tagged out already: its Moves since the tag were dropped, so where it fired from cannot be
				-- read; the truth to tell its client, which has not heard of the tag yet, is that it is out)
				why = "out"
			end
			if why == nil and (len < 1e-6 or not Stream.aimOk(person, at, dx, dy, dz)) then
				why = "origin" -- (a direction of no length, or not the way it was looking)
			end
			if why == nil and now - person.placedAt > Contract.TRUST.placeGrace then
				-- the origin is held to the real body too, where the engine knows it
				local body = ctx.bodyOf(player)
				if body ~= nil then
					local wx, wy, wz = engine.positionOf(body)
					if wx ~= nil and wy ~= nil and wz ~= nil then
						local bx, _, bz = ArenaModule.toLocal(place, wx, wy, wz)
						local ex, ez = rec.ox - bx, rec.oz - bz
						local far = Contract.TRUST.bodySlack + Contract.TRUST.originSlack
						if ex * ex + ez * ez > far * far then
							why = "origin"
						end
					end
				end
			end
			if why == nil then
				-- f
				local ok, no = Rules.fire(state, id, f, m)
				if not ok then
					why = if no ~= nil and (Contract.WHY :: { [string]: string })[no] ~= nil then no else "phase"
				else
					local k = state.feel.ballSpeed / len
					-- (the births kept apart: step b)
					local birth = f
					local lastF = person.lastF
					if lastF ~= nil and birth < lastF + state.feel.fireInterval - BIRTH_MARGIN then
						birth = lastF + state.feel.fireInterval - BIRTH_MARGIN
						late = now - birth
					end
					local ball = launch(id, slot.team, rec.ox, rec.oy, rec.oz, dx * k, dy * k, dz * k, rewind, birth)
					ballId = ball.id
					person.lastM = m
					person.lastF = birth
					local shotYaw, shotPitch = Body.yawPitch(dx, dy, dz)
					person.shotLook = { t = at, yaw = shotYaw, pitch = shotPitch }
					person.idleAt = now
					if late > 0 then
						-- the part of its flight the shooter has already seen, against the bodies of those moments
						refreshTargets(state, now)
						Projectiles.advance(sim, ball, now, targets, onEnd)
					end
				end
			end
		end
		if why ~= nil then
			stats.shotsRefused += 1
			stats.shotsRefusedBy[why] = (stats.shotsRefusedBy[why] or 0) + 1
		end
		local rounds, reloadAt = magazineOf(state, id, now)
		ctx.send(player, {
			kind = "paintball_ack",
			shot = rec.shot,
			ok = why == nil,
			ball = ballId,
			why = why,
			rounds = rounds,
			reloadAt = reloadAt,
		})
	end

	function service.watching(self: Service, player: any): boolean
		return self.audience[player] == true
	end

	function service.stats(_self: Service): Stats
		return stats
	end

	-- the remotes, only where the arena stands
	if hw ~= nil then
		local port = d.port or (if ctx.net then PaintballService.port(ctx.net) else nil)
		service.port = port
		if port then
			port.on("Paintball.Move", function(player: any, rec: { [string]: number })
				service:onMove(player, rec)
			end)
			port.on("Paintball.Fire", function(player: any, rec: { [string]: number })
				service:onFire(player, rec)
			end)
		end
	end

	return service
end

return PaintballService
