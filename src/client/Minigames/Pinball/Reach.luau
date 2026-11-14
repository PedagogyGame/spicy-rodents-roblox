--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Pinball.Reach
-- The person playing a pinball machine HAS BOTH HANDS ON THE FLIPPER BUTTONS (brief v2 §13 PIN-S2), leaning in
-- over the lockdown bar a little as pinball players do, and a hand presses in when its flipper goes up. Without
-- it a bystander sees the flippers fire under somebody standing with their arms at their sides.
-- HOW: five of the body's own R15 joints are written after the Animator has written them (the caller does this
-- in RunService.Stepped, as Client/Minigames/AirHockey/Reach does for one arm): Waist (the lean toward the
-- buttons), and for each side Shoulder and Elbow (the arm, by two-bone reach). Everything is worked out from
-- the joints' own C0 and C1 and the lower torso's CFrame, so it does not depend on how a rig's parts are turned,
-- nor on the engine having solved the joints since the last write. A body without both arms (an animal, a rig
-- still streaming in) has nothing posed here and nothing is written.
--   lean: the upper torso turns about the waist toward the middle of the two targets, by LEAN_PER radians a stud
--     that middle lies further than LEAN_FROM (on the floor's plane), LEAN_MAX at the most.
--   each arm: the elbow bent by the angle that puts the hand as far from the shoulder as its target (the law of
--     cosines; STRETCH of the arm's length for a target further than that), the whole arm turned so that the
--     hand lies on the line from the shoulder to the target, and rolled about that line until the elbow hangs
--     down and a little outward (to the body's left for the left arm, its right for the right).
-- (The same two-bone solution as air hockey's one-armed Reach, for two arms and a shared lean: that module is
-- air hockey's and is read, not changed: Shared/Minigames/Games rule 6.)
-- Interface: hands(body) -> Hands? (the joints, found by name; nil without both arms); solve(hands, left, right)
--   -> Pose { waist: CFrame?, left: { shoulder, elbow }, right: { shoulder, elbow } } (the Transforms);
--   pose(hands, left, right) (solve, and write them); rest(hands) (the joints back to no Transform: the
--   Animator has them again); ON; LEAN_FROM; LEAN_PER; LEAN_MAX; STRETCH

local Reach = {}

Reach.ON = true
Reach.LEAN_FROM = 0.6 -- studs between the waist and the buttons' middle (on the floor's plane) before the body leans
Reach.LEAN_PER = 0.25 -- radians of lean a stud beyond that
Reach.LEAN_MAX = 0.35 -- radians: as far as a body leans over the lockdown bar
Reach.STRETCH = 0.95 -- of the arm's full length: as far as a hand is held out toward a button out of reach

export type Arm = {
	shoulder: any, -- Motor6D UpperTorso -> <Side>UpperArm
	elbow: any, -- Motor6D <Side>UpperArm -> <Side>LowerArm
	hand: Vector3, -- the middle of the hand, in the lower arm's own space
	side: number, -- -1 the left arm, 1 the right
}

export type Hands = {
	body: any,
	waist: any?, -- Motor6D LowerTorso -> UpperTorso
	left: Arm,
	right: Arm,
}

export type ArmPose = { shoulder: CFrame, elbow: CFrame }
export type Pose = { waist: CFrame?, left: ArmPose, right: ArmPose }

local function joint(body: any, name: string): any
	for _, d in body:GetDescendants() do
		if d.Name == name and d:IsA("Motor6D") and d.Part0 ~= nil and d.Part1 ~= nil then
			return d
		end
	end
	return nil
end

local function arm(body: any, side: string, sign: number): Arm?
	local shoulder, elbow = joint(body, `{side}Shoulder`), joint(body, `{side}Elbow`)
	if shoulder == nil or elbow == nil then
		return nil
	end
	-- the middle of the hand: through the wrist where there is one, else the far end of the lower arm
	local wrist = joint(body, `{side}Wrist`)
	local hand: Vector3
	if wrist ~= nil then
		hand = (wrist.C0 * wrist.C1:Inverse()).Position
	else
		hand = -elbow.C1.Position
	end
	return { shoulder = shoulder, elbow = elbow, hand = hand, side = sign }
end

function Reach.hands(body: any): Hands?
	local left, right = arm(body, "Left", -1), arm(body, "Right", 1)
	if left == nil or right == nil or left.shoulder.Part0 ~= right.shoulder.Part0 then
		return nil
	end
	local waist = joint(body, "Waist")
	if waist ~= nil and waist.Part1 ~= right.shoulder.Part0 then
		waist = nil -- (not the joint under these shoulders: the body is not leant)
	end
	return { body = body, waist = waist, left = left, right = right }
end

-- the turn that takes one direction onto another by the shortest way (both unit vectors); `side` is the axis
-- to turn about when they are opposite
local function between(a: Vector3, b: Vector3, side: Vector3): CFrame
	local axis = a:Cross(b)
	local sin, cos = axis.Magnitude, a:Dot(b)
	if sin < 1e-7 then
		return if cos > 0 then CFrame.new() else CFrame.fromAxisAngle(side, math.pi)
	end
	return CFrame.fromAxisAngle(axis / sin, math.atan2(sin, cos))
end

-- one arm toward its target, from the upper torso as it stands (leant)
local function solveArm(a: Arm, torso: CFrame, target: Vector3): ArmPose
	local shoulder, elbow = a.shoulder, a.elbow
	local socket: CFrame = torso * shoulder.C0
	local toElbow: CFrame = shoulder.C1:Inverse() * elbow.C0
	local upper: Vector3 = toElbow.Position
	local lower: Vector3 = toElbow:VectorToWorldSpace(elbow.C1:Inverse() * a.hand)
	local l1, l2 = upper.Magnitude, lower.Magnitude
	local goal: Vector3 = socket:PointToObjectSpace(target)
	-- The elbow bends about its own axis: the rig's X, squared to the lower arm (an R15 arm folds forward about
	-- it, either arm). With the lower arm turned by `bend` about that hinge the hand is |upper + R(bend) lower|
	-- from the shoulder, and |..|^2 = l1^2 + l2^2 + 2 (a + b cos(bend) + c sin(bend)).
	local fore = lower / l2
	local hinge = Vector3.xAxis - fore * fore.X
	if hinge.Magnitude < 1e-3 then
		hinge = Vector3.zAxis - fore * fore.Z
	end
	hinge = hinge.Unit
	local across = lower - hinge * lower:Dot(hinge)
	local pa = upper:Dot(lower - across)
	local pb = upper:Dot(across)
	local pc = upper:Dot(hinge:Cross(across))
	local swing = math.sqrt(pb * pb + pc * pc)
	local bend = 0
	if swing > 1e-9 then
		local most = math.sqrt(math.max(l1 * l1 + l2 * l2 + 2 * (pa + swing), 0)) * Reach.STRETCH
		local far = math.min(goal.Magnitude, most)
		local want = (far * far - l1 * l1 - l2 * l2) / 2 - pa
		local phase = math.atan2(pc, pb)
		local open = math.acos(math.clamp(want / swing, -1, 1))
		-- (of the two bends that give that distance, the one that folds the arm forward)
		bend = phase + open
		if bend > math.pi or bend < 0 then
			local other = phase - open
			if math.abs(other) < math.abs(bend) then
				bend = other
			end
		end
	end
	local fold = CFrame.fromAxisAngle(hinge, bend)
	local hand: Vector3 = upper + fold * lower
	-- the whole arm turned so that the hand is on the line to the target...
	local to = if goal.Magnitude > 1e-6 then goal.Unit else -Vector3.yAxis
	local aim = between(hand.Unit, to, hinge)
	-- ...and rolled about that line until the elbow hangs down and a little outward
	local pole = socket:VectorToObjectSpace(Vector3.new(0, -1, 0) + torso.RightVector * (0.6 * a.side))
	local elbowAt = aim * upper
	local p1 = elbowAt - to * elbowAt:Dot(to)
	local p2 = pole - to * pole:Dot(to)
	local roll = CFrame.new()
	if p1.Magnitude > 1e-4 and p2.Magnitude > 1e-4 then
		roll = CFrame.fromAxisAngle(to, math.atan2(to:Dot(p1:Cross(p2)), p1:Dot(p2)))
	end
	return { shoulder = roll * aim, elbow = toElbow.Rotation:Inverse() * fold * toElbow.Rotation }
end

function Reach.solve(h: Hands, left: Vector3, right: Vector3): Pose
	local torso: CFrame = h.right.shoulder.Part0.CFrame
	local lean: CFrame? = nil
	local waist = h.waist
	if waist ~= nil then
		local at: CFrame = waist.Part0.CFrame * waist.C0
		local mid = (left + right) / 2
		local flat = Vector3.new(mid.X - at.Position.X, 0, mid.Z - at.Position.Z)
		local far = flat.Magnitude
		local angle = math.clamp((far - Reach.LEAN_FROM) * Reach.LEAN_PER, 0, Reach.LEAN_MAX)
		local turn = CFrame.new()
		if far > 1e-3 and angle > 0 then
			-- (about the level axis square to the way to the buttons: straight up is tipped toward them)
			local world = CFrame.fromAxisAngle(Vector3.new(0, 1, 0):Cross(flat / far), angle)
			turn = at.Rotation:Inverse() * world * at.Rotation
		end
		lean = turn
		torso = at * turn * waist.C1:Inverse()
	end
	return { waist = lean, left = solveArm(h.left, torso, left), right = solveArm(h.right, torso, right) }
end

function Reach.pose(h: Hands, left: Vector3, right: Vector3)
	if not Reach.ON then
		return
	end
	local pose = Reach.solve(h, left, right)
	if h.waist ~= nil and pose.waist ~= nil then
		h.waist.Transform = pose.waist
	end
	h.left.shoulder.Transform = pose.left.shoulder
	h.left.elbow.Transform = pose.left.elbow
	h.right.shoulder.Transform = pose.right.shoulder
	h.right.elbow.Transform = pose.right.elbow
end

function Reach.rest(h: Hands)
	if h.waist ~= nil then
		h.waist.Transform = CFrame.new()
	end
	for _, a in { h.left, h.right } do
		a.shoulder.Transform = CFrame.new()
		a.elbow.Transform = CFrame.new()
	end
end

return Reach
