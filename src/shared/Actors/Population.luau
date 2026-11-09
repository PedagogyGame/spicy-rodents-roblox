--!strict
-- ReplicatedStorage.Shared.Actors.Population
-- Posts, standing counts, AI floors, hard-cap floors, reserve and hard cap (BUILD_PLAN §1.5, D23;
-- brief v2 §5: at least 6 NPC police and 10 NPC hospital staff, ambulance crews on top, never cut).
-- Interface (BUILD_PLAN §1.4): pickBody(post, state, config) -> Decision, floorsOk(state, config),
-- apply(state, decision), release(state, post), validate(config), newState(config), plan(), spikeS5()
-- Pure data and arithmetic: W1 loads the config from data/cast/population.json (§3.12) and the
-- compiler enforces invariant 11 with the same validate().

export type Post = {
	id: string,
	standing: number, -- bodies built at boot for this post
	floor: number, -- AI bodies the post keeps at normal occupancy
	floorAtCap: number, -- AI bodies the post keeps once the hard cap is reached
	protected: boolean?, -- the brief's floors: police and hospital (and crews); never cut, never re-posted
	silent: boolean?, -- posts that may become non-Humanoid rigs under the D4 fallback
}

export type Config = {
	posts: { Post },
	reserve: number,
	hardCap: number,
	squirrelFloat: { min: number, max: number },
	deerBodies: number,
	playerSlots: number, -- 49 (brief v2 §5); the ladder's arithmetic lives in Roles/Ladder
}

export type PostState = { ai: number, player: number }

export type State = {
	bodies: { [string]: PostState },
	reserveLeft: number,
	deployed: number, -- reserve bodies brought out so far
	atCap: boolean,
}

export type Decision = {
	kind: "body" | "repost" | "reserve" | "capFloors" | "wait",
	post: string, -- the post the body will serve
	fromPost: string?, -- repost: where the body comes from
}

local Population = {}

local function postById(config: Config, id: string): Post
	for _, post in config.posts do
		if post.id == id then
			return post
		end
	end
	error(`Population: unknown post {id}`)
end

local function floorOf(post: Post, atCap: boolean): number
	return if atCap then post.floorAtCap else post.floor
end

local function totalBodies(state: State): number
	local n = 0
	for _, ps in state.bodies do
		n += ps.ai + ps.player
	end
	return n
end

function Population.newState(config: Config): State
	local bodies: { [string]: PostState } = {}
	for _, post in config.posts do
		bodies[post.id] = { ai = post.standing, player = 0 }
	end
	return { bodies = bodies, reserveLeft = config.reserve, deployed = 0, atCap = false }
end

function Population.totalBodies(state: State): number
	return totalBodies(state)
end

function Population.humanPlayers(state: State): number
	local n = 0
	for _, ps in state.bodies do
		n += ps.player
	end
	return n
end

-- Floors hold when every post keeps at least its floor in AI hands (hard-cap floors once atCap).
function Population.floorsOk(state: State, config: Config): (boolean, { string })
	local violations = {}
	for _, post in config.posts do
		local ps = state.bodies[post.id]
		local floor = floorOf(post, state.atCap)
		if ps.ai < floor then
			table.insert(violations, `{post.id}: {ps.ai} AI below floor {floor}`)
		end
	end
	return #violations == 0, violations
end

-- Supply order (§1.5): (1) an AI body of that post above its floor; (2) re-post an AI body above
-- floor from another, unprotected post (most slack first); (3) deploy a reserve body; (4) at the
-- hard cap, drop to the hard-cap floors and retry (1)-(2); else wait.
function Population.pickBody(postId: string, state: State, config: Config): Decision
	local target = postById(config, postId)
	local function above(post: Post, atCap: boolean): number
		return state.bodies[post.id].ai - floorOf(post, atCap)
	end
	local function tryPosts(atCap: boolean): Decision?
		if above(target, atCap) > 0 then
			return { kind = "body", post = postId }
		end
		local bestPost: Post? = nil
		local bestSlack = 0
		for _, post in config.posts do
			if post.id ~= postId and not post.protected then
				local slack = above(post, atCap)
				if slack > bestSlack then
					bestSlack = slack
					bestPost = post
				end
			end
		end
		if bestPost then
			return { kind = "repost", post = postId, fromPost = bestPost.id }
		end
		return nil
	end
	local d = tryPosts(state.atCap)
	if d then
		return d
	end
	if state.reserveLeft > 0 and totalBodies(state) < config.hardCap then
		return { kind = "reserve", post = postId }
	end
	if not state.atCap then
		local dCap = tryPosts(true)
		if dCap then
			return { kind = "capFloors", post = postId, fromPost = dCap.fromPost }
		end
	end
	return { kind = "wait", post = postId }
end

-- Mutate the state for a decision: the body becomes player-held at `post`.
function Population.apply(state: State, decision: Decision)
	local post = state.bodies[decision.post]
	if decision.kind == "body" then
		post.ai -= 1
		post.player += 1
	elseif decision.kind == "repost" then
		local from = state.bodies[decision.fromPost :: string]
		from.ai -= 1
		post.player += 1
	elseif decision.kind == "reserve" then
		state.reserveLeft -= 1
		state.deployed += 1
		post.player += 1
	elseif decision.kind == "capFloors" then
		state.atCap = true
		if decision.fromPost then
			state.bodies[decision.fromPost :: string].ai -= 1
		else
			post.ai -= 1
		end
		post.player += 1
	elseif decision.kind == "wait" then
		-- nothing changes; the join waits on the flyover camera
	end
end

-- A player leaves (or is promoted away): the body returns to the AI at its post.
function Population.release(state: State, postId: string)
	local post = state.bodies[postId]
	if post.player <= 0 then
		error(`Population.release: no player body at {postId}`)
	end
	post.player -= 1
	post.ai += 1
end

-- Compiler invariant 11 (BUILD_PLAN §3.13) and the D23 arithmetic.
function Population.validate(config: Config): (boolean, { string })
	local errors = {}
	local standing, floors, capFloors = 0, 0, 0
	local police, hospital, ambulance = 0, 0, 0
	for _, post in config.posts do
		standing += post.standing
		floors += post.floor
		capFloors += post.floorAtCap
		if post.floor > post.standing then
			table.insert(errors, `{post.id}: floor {post.floor} above standing {post.standing}`)
		end
		if post.floorAtCap > post.floor then
			table.insert(errors, `{post.id}: hard-cap floor above the normal floor`)
		end
		if post.id == "police" then
			police = post.floorAtCap
		elseif post.id == "hospitalStaff" then
			hospital = post.floorAtCap
		elseif post.id == "ambulanceCrew" then
			ambulance = post.floorAtCap
		end
	end
	if police < 6 then
		table.insert(errors, `police floor {police} < 6 (brief v2 §5)`)
	end
	if hospital < 10 then
		table.insert(errors, `hospital floor {hospital} < 10 (brief v2 §5)`)
	end
	if ambulance < 1 then
		table.insert(errors, "ambulance crews must be their own post (brief v2 §5)")
	end
	if standing + config.reserve > config.hardCap then
		table.insert(errors, `standing {standing} + reserve {config.reserve} > hard cap {config.hardCap}`)
	end
	if config.hardCap - capFloors < config.playerSlots then
		table.insert(
			errors,
			`hard cap {config.hardCap} - hard-cap floors {capFloors} < {config.playerSlots} player slots`
		)
	end
	if
		config.squirrelFloat.min < 10
		or config.squirrelFloat.max > 14
		or config.squirrelFloat.min > config.squirrelFloat.max
	then
		table.insert(errors, "squirrel float must sit inside 10-14 (brief v2 §5)")
	end
	if config.deerBodies < 5 then
		table.insert(errors, `deer bodies {config.deerBodies} < 5`)
	end
	return #errors == 0, errors
end

-- Standing/floor columns of BUILD_PLAN §1.5 (FRB column), hard cap 90 (S19 target).
function Population.plan(): Config
	return {
		posts = {
			{ id = "townsperson", standing = 32, floor = 8, floorAtCap = 4 },
			{ id = "shopWorker", standing = 6, floor = 6, floorAtCap = 4 },
			{ id = "hospitalStaff", standing = 14, floor = 10, floorAtCap = 10, protected = true },
			{ id = "ambulanceCrew", standing = 3, floor = 2, floorAtCap = 2, protected = true },
			-- 6 officers plus the precinct guard and the 2-officer AI patrol-car crew
			{ id = "police", standing = 14, floor = 9, floorAtCap = 9, protected = true },
			{ id = "attractionStaff", standing = 0, floor = 0, floorAtCap = 0, silent = true },
		},
		reserve = 8,
		hardCap = 90,
		squirrelFloat = { min = 10, max = 14 },
		deerBodies = 6,
		playerSlots = 49,
	}
end

-- The S5 synthetic worst case as this spike measured it: 72 human bodies (66 standing + 6 reserve)
-- all AI-driven while 49 moving focus points stand in for the players. The hard cap here is the
-- measured body count, not the production number (plan(): 90), so validate() is expected to flag
-- the 49-slot arithmetic for this config; S5.md records it.
function Population.spikeS5(): Config
	return {
		posts = {
			{ id = "townsperson", standing = 24, floor = 8, floorAtCap = 4 },
			{ id = "shopWorker", standing = 6, floor = 6, floorAtCap = 4 },
			{ id = "hospitalStaff", standing = 14, floor = 10, floorAtCap = 10, protected = true },
			{ id = "ambulanceCrew", standing = 3, floor = 2, floorAtCap = 2, protected = true },
			{ id = "police", standing = 14, floor = 9, floorAtCap = 9, protected = true },
			{ id = "attractionStaff", standing = 5, floor = 3, floorAtCap = 3, silent = true },
		},
		reserve = 6,
		hardCap = 72,
		squirrelFloat = { min = 10, max = 14 },
		deerBodies = 6,
		playerSlots = 49,
	}
end

return Population
