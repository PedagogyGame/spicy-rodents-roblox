--!strict
-- ReplicatedStorage.Shared.Traffic.PoseStream
-- Both ends of the VehiclePoses stream as plain, steppable logic, so the game and the headless replay
-- (tools/sim/traffic_replay.luau) run the very same code and can never drift apart:
--   * the server's send decision: an accumulator that lets a send go every 1 / HZ seconds and appends
--     the server's clock as a stamp record (Traffic/Ghost.stamp). Server/Traffic/TrafficService.frame
--     calls it once per server frame (Server/Boot/Game's step).
--   * the client's receive: the packet is decoded, the stamp taken out and placed on the local timeline
--     by the stamp clock, and the records pushed into the snapshot buffer that Ghost.render samples.
--     Client/Render/VehicleView calls it on every packet.
-- Interface: HZ; MAX_FRAME_DT; REMOTE; newSender(hz?) -> Sender; Sender:frame(dt, now, source) -> records?;
--            newReceiver(opts?) -> Receiver; Receiver:receive(records, arrival);
--            Receiver:packet(payload, arrival) -> boolean
-- Pure: no engine calls, no state outside the objects it returns, no side effects on require.

local Ghost = require("./Ghost")
local Net = require("../Net/Net")
local Schemas = require("../Net/Schemas")

local PoseStream = {}

PoseStream.HZ = 15 -- sends a second
PoseStream.REMOTE = "VehiclePoses" -- the Net/Schemas remote the stream goes out on
-- The longest frame the server's clock advances by: Server/Boot/Game clamps every Heartbeat dt to this
-- before it steps, so the clock that stamps the sends falls behind real time across a longer hitch.
PoseStream.MAX_FRAME_DT = 0.1

type Records = { { [string]: number } }

export type Source = { poseRecords: (self: any) -> Records }

export type Sender = {
	period: number,
	acc: number,
	sends: number,
	frame: (self: Sender, dt: number, now: number, source: Source) -> Records?,
}

-- newSender(hz?): the server side. `frame(dt, now, source)` is called once per server frame with that
-- frame's dt and the server clock AFTER the frame's simulation; when a send is due it returns
-- `source:poseRecords()` with the stamp record appended (the caller hands it to Net:stream), else nil.
-- The remainder is carried, capped at one period, so the sends stay an even HZ a second.
function PoseStream.newSender(hz: number?): Sender
	return {
		period = 1 / (hz or PoseStream.HZ),
		acc = 0,
		sends = 0,
		frame = function(self: Sender, dt: number, now: number, source: Source): Records?
			self.acc += dt
			if self.acc >= self.period then
				self.acc = math.min(self.acc - self.period, self.period)
				self.sends += 1
				local records = source:poseRecords()
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
	packet: (self: Receiver, payload: any, arrival: number) -> boolean,
}

-- newReceiver(opts?): the client side. `packet(payload, arrival)` takes what the remote delivered and the
-- local time it arrived at; anything that is not a decodable buffer is dropped (false). `receive(records,
-- arrival)` takes one decoded send (the records of Net.decodeStream, stamp included): the server's own
-- clock spaces the snapshots, the arrival time only anchors them (a send without a stamp is timed by its
-- arrival). `buffer` is what Ghost.render samples every frame.
function PoseStream.newReceiver(opts: { delay: number?, keep: number? }?): Receiver
	return {
		buffer = Ghost.new(opts),
		clock = Ghost.newClock(),
		receive = function(self: Receiver, records: Records, arrival: number)
			local stamp = Ghost.takeStamp(records)
			self.buffer:push(if stamp then self.clock:localTime(stamp, arrival) else arrival, records)
		end,
		packet = function(self: Receiver, payload: any, arrival: number): boolean
			if typeof(payload) ~= "buffer" then
				return false
			end
			local good, records = pcall(Net.decodeStream, Schemas.VehiclePose, payload)
			if good then
				self:receive(records, arrival)
			end
			return good
		end,
	}
end

return PoseStream
