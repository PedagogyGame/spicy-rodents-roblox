--!strict
-- ReplicatedStorage.Shared.Util.Signal
-- A tiny synchronous signal (no BindableEvent, no threads): handlers run in connection order on fire;
-- a handler that errors is reported through `onError` and never stops the others (BUILD_PLAN §1.4 Util).
-- Interface: new() -> Signal; connect(fn) -> Connection; once(fn); fire(...); count(); destroy()
--            Connection:disconnect(); Connection.connected

export type Connection = { connected: boolean, disconnect: (self: Connection) -> () }
export type Signal = {
	connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	once: (self: Signal, fn: (...any) -> ()) -> Connection,
	fire: (self: Signal, ...any) -> (),
	count: (self: Signal) -> number,
	destroy: (self: Signal) -> (),
	onError: ((err: any) -> ())?,
	_slots: { { fn: (...any) -> (), conn: Connection } },
}

local Signal = {}

function Signal.new(): Signal
	local sig = { _slots = {} } :: Signal

	function sig.connect(self: Signal, fn: (...any) -> ()): Connection
		local conn = { connected = true } :: Connection
		local slot = { fn = fn, conn = conn }
		function conn.disconnect(c: Connection)
			if not c.connected then
				return
			end
			c.connected = false
			local i = table.find(self._slots, slot)
			if i then
				table.remove(self._slots, i)
			end
		end
		table.insert(self._slots, slot)
		return conn
	end

	function sig.once(self: Signal, fn: (...any) -> ()): Connection
		local conn: Connection
		conn = self:connect(function(...)
			conn:disconnect()
			fn(...)
		end)
		return conn
	end

	function sig.fire(self: Signal, ...: any)
		-- snapshot so connects/disconnects inside a handler do not disturb this fire
		local snapshot = table.clone(self._slots)
		for _, slot in snapshot do
			if slot.conn.connected then
				local ok, err = pcall(slot.fn, ...)
				if not ok then
					if self.onError then
						self.onError(err)
					else
						warn(`Signal handler error: {err}`)
					end
				end
			end
		end
	end

	function sig.count(self: Signal): number
		return #self._slots
	end

	function sig.destroy(self: Signal)
		for _, slot in self._slots do
			slot.conn.connected = false
		end
		table.clear(self._slots)
	end

	return sig
end

return Signal
