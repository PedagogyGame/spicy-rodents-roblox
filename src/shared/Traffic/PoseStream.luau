--!strict
-- ReplicatedStorage.Shared.Traffic.PoseStream
-- Both ends of the VehiclePoses stream as plain, steppable logic, so the game and the headless replay
-- (tools/sim/traffic_replay.luau) run the very same code and can never drift apart:
--   * the server's send decision: an accumulator that lets a send go every 1 / HZ seconds and appends
--     the server's clock as a stamp record (Traffic/Ghost.stamp). Server/Boot/Game calls it every frame.
--   * the client's receive: the stamp is taken out, placed on the local timeline by the stamp clock and
--     the records pushed into the snapshot buffer. Client/Render/VehicleView calls it on every packet.
-- Interface: HZ; MAX_FRAME_DT; newSender(hz?) -> Sender; Sender:frame(dt, now, poseRecords) -> records?;
--            newReceiver(opts?) -> Receiver; Receiver:receive(records, arrival)
-- Pure: no engine calls, no state outside the objects it returns, no side effects on require.

local Ghost = require("./Ghost")

local PoseStream = {}

PoseStream.HZ = 15 -- sends a second
-- The longest frame the server's clock advances by: Server/Boot/Game clamps every Heartbeat dt to this
-- before it steps, so the clock that stamps the sends falls behind real time across a longer hitch.
PoseStream.MAX_FRAME_DT = 0.1

type Records = { { [string]: number } }

export type Sender = {
	period: number,
	acc: number,
	sends: number,
	frame: (self: Sender, dt: number, now: number, poseRecords: () -> Records) -> Records?,
}

-- newSender(hz?): the server side. `frame(dt, now, poseRecords)` is called once per server frame with
-- that frame's dt and the server clock AFTER the frame's simulation; when a send is due it returns
-- `poseRecords()` with the stamp record appended (the caller hands it to Net:stream), else nil.
-- The remainder is carried, capped at one period, so the sends stay an even HZ a second.
function PoseStream.newSender(hz: number?): Sender
	return {
		period = 1 / (hz or PoseStream.HZ),
		acc = 0,
		sends = 0,
		frame = function(self: Sender, dt: number, now: number, poseRecords: () -> Records): Records?
			self.acc += dt
			if self.acc >= self.period then
				self.acc = math.min(self.acc - self.period, self.period)
				self.sends += 1
				local records = poseRecords()
				table.insert(records, Ghost.stamp(now)) -- the server's clock (Traffic/Ghost)
				return records
			end
			return nil
		end,
	}
end

export type Receiver = {
	buffer: Ghost.Buffer,
	clock: Ghost.StampClock,
	receive: (self: Receiver, records: Records, arrival: number) -> (),
}

-- newReceiver(opts?): the client side. `receive(records, arrival)` takes one decoded send (the records
-- of Net.decodeStream, stamp included) and the local time it arrived at: the server's own clock spaces
-- the snapshots, the arrival time only anchors them (a send without a stamp is timed by its arrival).
-- `buffer` is what Ghost.render samples every frame.
function PoseStream.newReceiver(opts: { delay: number?, keep: number? }?): Receiver
	return {
		buffer = Ghost.new(opts),
		clock = Ghost.newClock(),
		receive = function(self: Receiver, records: Records, arrival: number)
			local stamp = Ghost.takeStamp(records)
			self.buffer:push(if stamp then self.clock:localTime(stamp, arrival) else arrival, records)
		end,
	}
end

return PoseStream
