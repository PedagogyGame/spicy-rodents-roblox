--!strict
-- ReplicatedStorage.Shared.Paintball.Magazine
-- The marker's five-shot magazine (D29; brief v2 §13a; spike S18): a fire interval, an automatic
-- reload when the last ball leaves, and a manual reload (R) that refills after the same delay.
-- Shared so the client predicts exactly what the server will accept.
-- Interface: new(capacity, fireInterval, reloadSecs) -> Mag; canFire(mag, now); fire(mag, now) -> ok;
--            reload(mag, now) -> ok; update(mag, now)

export type Mag = {
	capacity: number,
	rounds: number,
	fireInterval: number,
	reloadSecs: number,
	nextFireAt: number,
	reloadDoneAt: number?, -- set while reloading
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
		fired = 0,
		reloads = 0,
	}
end

function Magazine.update(mag: Mag, now: number)
	local done = mag.reloadDoneAt
	if done ~= nil and now >= done then
		mag.rounds = mag.capacity
		mag.reloadDoneAt = nil
	end
end

function Magazine.canFire(mag: Mag, now: number): boolean
	Magazine.update(mag, now)
	return mag.reloadDoneAt == nil and mag.rounds > 0 and now >= mag.nextFireAt
end

function Magazine.reload(mag: Mag, now: number): boolean
	Magazine.update(mag, now)
	if mag.reloadDoneAt ~= nil or mag.rounds == mag.capacity then
		return false
	end
	mag.reloadDoneAt = now + mag.reloadSecs
	mag.reloads += 1
	return true
end

function Magazine.fire(mag: Mag, now: number): boolean
	if not Magazine.canFire(mag, now) then
		return false
	end
	mag.rounds -= 1
	mag.fired += 1
	mag.nextFireAt = now + mag.fireInterval
	if mag.rounds == 0 then
		Magazine.reload(mag, now) -- automatic reload on the last ball
	end
	return true
end

return Magazine
