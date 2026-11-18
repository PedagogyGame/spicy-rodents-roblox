--!strict
-- ReplicatedStorage.Shared.Paintball.Magazine
-- The marker's five-shot magazine (D29; brief v2 §13a; spike S18): a fire interval, an automatic
-- reload when the last ball leaves, and a manual reload (R) that refills after the same delay.
-- Shared so the client predicts exactly what the server will accept.
-- A RELOAD ON R WITH BALLS LEFT IS CANCELLED BY A FIRE PRESS (settled at the review, 2026-11-13): the press
-- fires the next ball and the magazine keeps what it had. Children press R after every shot or two, and in a
-- one-hit game four balls locked away for 1.6 s is the "that's not fair" moment. The automatic reload on the
-- last ball cannot be cancelled (there is nothing to fire).
-- Interface: new(capacity, fireInterval, reloadSecs) -> Mag; canFire(mag, now); fire(mag, now) -> ok;
--            reload(mag, now) -> ok; update(mag, now)

export type Mag = {
	capacity: number,
	rounds: number,
	fireInterval: number,
	reloadSecs: number,
	nextFireAt: number,
	reloadDoneAt: number?, -- set while reloading
	manual: boolean, -- the running reload was asked for with balls left (a fire press cancels it)
	fired: number,
	reloads: number,
}

local Magazine = {}

function Magazine.new(capacity: number, fireInterval: number, reloadSecs: number): Mag
	return {
		capacity = capacity,
		rounds = capacity,
		fireInterval = fireInterval,
		reloadSecs = reloadSecs,
		nextFireAt = 0,
		reloadDoneAt = nil,
		manual = false,
		fired = 0,
		reloads = 0,
	}
end

function Magazine.update(mag: Mag, now: number)
	local done = mag.reloadDoneAt
	if done ~= nil and now >= done then
		mag.rounds = mag.capacity
		mag.reloadDoneAt = nil
		mag.manual = false
	end
end

function Magazine.canFire(mag: Mag, now: number): boolean
	Magazine.update(mag, now)
	local loading = mag.reloadDoneAt ~= nil and not mag.manual
	return not loading and mag.rounds > 0 and now >= mag.nextFireAt
end

function Magazine.reload(mag: Mag, now: number): boolean
	Magazine.update(mag, now)
	if mag.reloadDoneAt ~= nil or mag.rounds == mag.capacity then
		return false
	end
	mag.reloadDoneAt = now + mag.reloadSecs
	mag.manual = mag.rounds > 0
	mag.reloads += 1
	return true
end

function Magazine.fire(mag: Mag, now: number): boolean
	if not Magazine.canFire(mag, now) then
		return false
	end
	-- (a fire press cancels a reload asked for with balls left)
	mag.reloadDoneAt = nil
	mag.manual = false
	mag.rounds -= 1
	mag.fired += 1
	mag.nextFireAt = now + mag.fireInterval
	if mag.rounds == 0 then
		Magazine.reload(mag, now) -- automatic reload on the last ball
	end
	return true
end

return Magazine
