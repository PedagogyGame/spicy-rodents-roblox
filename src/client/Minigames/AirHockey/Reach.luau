--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.AirHockey.Reach
-- The person at an end of the air hockey table REACHES FOR THEIR MALLET: without it a bystander sees a mallet
-- sliding about in front of somebody standing with their arms at their sides. The right arm of a person's body
-- is aimed at a point (the cap of the mallet they play) and the upper body leans toward it, on every screen,
-- from the mallet that screen is drawing: nothing is sent for it.
-- The bed is long for an avatar's arm (the table is at the pool tables' scale), so the hand is on the mallet
-- only when the mallet is close to that end; further out the arm is held out toward it (not quite straight:
-- STRETCH of its length, the elbow a little bent) and the body leans.
-- HOW: three of the body's own R15 joints are written, after the Animator has written them (the caller does
-- this in RunService.Stepped, as Animation/AnimationDriver does for a patient's legs): Waist (the lean),
-- RightShoulder and RightElbow (the arm, by two-bone reach). Everything is worked out from the joints' own C0
-- and C1 and the lower torso's CFrame, so it does not depend on how a rig's parts are turned, nor on the engine
-- having solved the joints since the last write. A body without those joints (an animal, a rig still streaming
-- in) has no arm here and nothing is written.
--   solve: the lean Q turns the upper torso about the waist toward the target, by LEAN_PER radians for every
--     stud the target is further than LEAN_FROM (LEAN_MAX at the most). The arm: with the elbow bent by the
--     angle that puts the hand as far from the shoulder as the target is (the law of cosines, exact for a
--     rig whose shoulder joint is not over its elbow; STRETCH of the arm's length for a target further than
--     that), the whole arm is turned so that the hand lies on the line from the shoulder to the target, and
--     rolled about that line until the elbow hangs down and a little outward.
-- Interface: arm(body) -> Arm? (the joints of a body, found by name; nil if it has no right arm);
--   solve(arm, target: Vector3) -> Pose { waist: CFrame?, shoulder: CFrame, elbow: CFrame } (the Transforms);
--   pose(arm, target) (solve, and write them); rest(arm) (the three joints back to no Transform: the Animator
--   has them again); ON (false: nothing is ever posed); LEAN_FROM; LEAN_PER; LEAN_MAX; STRETCH

local Reach = {}

Reach.ON = true
Reach.LEAN_FROM = 2 -- studs between the waist and the target (on the floor's plane) before the body leans
Reach.LEAN_PER = 0.12 -- radians of lean a stud beyond that
Reach.LEAN_MAX = 0.5 -- radians: as far as a body leans over the table
Reach.STRETCH = 0.9 -- of the arm's full length: as far as the hand is held out toward a mallet out of reach

export type Arm = {
	body: any,
	waist: any?, -- Motor6D LowerTorso -> UpperTorso
	shoulder: any, -- Motor6D UpperTorso -> RightUpperArm
	elbow: any, -- Motor6D RightUpperArm -> RightLowerArm
	hand: Vector3, -- the middle of the hand, in the lower arm's own space
}

export type Pose = { waist: CFrame?, shoulder: CFrame, elbow: CFrame }

local function joint(body: any, name: string): any
	for _, d in body:GetDescendants() do
		if d.Name == name and d:IsA("Motor6D") and d.Part0 ~= nil and d.Part1 ~= nil then
			return d
		end
	end
	return nil
end

function Reach.arm(body: any): Arm?
	local shoulder, elbow = joint(body, "RightShoulder"), joint(body, "RightElbow")
	if shoulder == nil or elbow == nil then
		return nil
	end
	-- the middle of the hand: through the wrist where there is one, else the far end of the lower arm
	local wrist = joint(body, "RightWrist")
	local hand: Vector3
	if wrist ~= nil then
		hand = (wrist.C0 * wrist.C1:Inverse()).Position
	else
		local from = elbow.C1.Position
		hand = -from
	end
	local waist = joint(body, "Waist")
	if waist ~= nil and waist.Part1 ~= shoulder.Part0 then
		waist = nil -- (not the joint under this shoulder: the body is not leant)
	end
	return { body = body, waist = waist, shoulder = shoulder, elbow = elbow, hand = hand }
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

function Reach.solve(arm: Arm, target: Vector3): Pose
	local shoulder, elbow, waist = arm.shoulder, arm.elbow, arm.waist
	-- the upper torso, leant toward the target about the waist
	local torso: CFrame = shoulder.Part0.CFrame
	local lean: CFrame? = nil
	if waist ~= nil then
		local at: CFrame = waist.Part0.CFrame * waist.C0
		local flat = Vector3.new(target.X - at.Position.X, 0, target.Z - at.Position.Z)
		local far = flat.Magnitude
		local angle = math.clamp((far - Reach.LEAN_FROM) * Reach.LEAN_PER, 0, Reach.LEAN_MAX)
		local turn = CFrame.new()
		if far > 1e-3 and angle > 0 then
			-- (about the level axis square to the way to the target: straight up is tipped toward it)
			local world = CFrame.fromAxisAngle(Vector3.new(0, 1, 0):Cross(flat / far), angle)
			turn = at.Rotation:Inverse() * world * at.Rotation
		end
		lean = turn
		torso = at * turn * waist.C1:Inverse()
	end
	-- the arm, in the shoulder joint's own frame: the elbow, and from the elbow the hand, as the rig rests
	local socket: CFrame = torso * shoulder.C0
	local toElbow: CFrame = shoulder.C1:Inverse() * elbow.C0
	local upper: Vector3 = toElbow.Position
	local lower: Vector3 = toElbow:VectorToWorldSpace(elbow.C1:Inverse() * arm.hand)
	local l1, l2 = upper.Magnitude, lower.Magnitude
	local goal: Vector3 = socket:PointToObjectSpace(target)
	-- The elbow bends about its own axis: the rig's X, squared to the lower arm (an R15 arm folds forward about
	-- it). With the lower arm turned by `bend` about that hinge the hand is |upper + R(bend) lower| from the
	-- shoulder, and |..|^2 = l1^2 + l2^2 + 2 (a + b cos(bend) + c sin(bend)): the bend that makes it the
	-- target's distance, or STRETCH of the arm's full length if the target is further than that.
	local fore = lower / l2
	local hinge = Vector3.xAxis - fore * fore.X
	if hinge.Magnitude < 1e-3 then
		hinge = Vector3.zAxis - fore * fore.Z
	end
	hinge = hinge.Unit
	local across = lower - hinge * lower:Dot(hinge)
	local a = upper:Dot(lower - across)
	local b = upper:Dot(across)
	local c = upper:Dot(hinge:Cross(across))
	local swing = math.sqrt(b * b + c * c)
	local bend = 0
	if swing > 1e-9 then
		local most = math.sqrt(math.max(l1 * l1 + l2 * l2 + 2 * (a + swing), 0)) * Reach.STRETCH
		local far = math.min(goal.Magnitude, most)
		local want = (far * far - l1 * l1 - l2 * l2) / 2 - a
		local phase = math.atan2(c, b)
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
	local pole = socket:VectorToObjectSpace(Vector3.new(0, -1, 0) + torso.RightVector * 0.6)
	local elbowAt = aim * upper
	local p1 = elbowAt - to * elbowAt:Dot(to)
	local p2 = pole - to * pole:Dot(to)
	local roll = CFrame.new()
	if p1.Magnitude > 1e-4 and p2.Magnitude > 1e-4 then
		roll = CFrame.fromAxisAngle(to, math.atan2(to:Dot(p1:Cross(p2)), p1:Dot(p2)))
	end
	return {
		waist = lean,
		shoulder = roll * aim,
		elbow = toElbow.Rotation:Inverse() * fold * toElbow.Rotation,
	}
end

function Reach.pose(arm: Arm, target: Vector3)
	if not Reach.ON then
		return
	end
	local pose = Reach.solve(arm, target)
	if arm.waist ~= nil and pose.waist ~= nil then
		arm.waist.Transform = pose.waist
	end
	arm.shoulder.Transform = pose.shoulder
	arm.elbow.Transform = pose.elbow
end

function Reach.rest(arm: Arm)
	if arm.waist ~= nil then
		arm.waist.Transform = CFrame.new()
	end
	arm.shoulder.Transform = CFrame.new()
	arm.elbow.Transform = CFrame.new()
end

return Reach
