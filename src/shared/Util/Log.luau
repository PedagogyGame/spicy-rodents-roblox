--!strict
-- ReplicatedStorage.Shared.Util.Log
-- Levelled, tagged logging with a pluggable sink and per-key rate limiting, so a rejected packet or a
-- validator flag can be logged every time without flooding the output (BUILD_PLAN §1.4 Util, §1.6:
-- "a rejected packet is logged and dropped"). Pure apart from the default sink (print/warn).
-- Interface: new(tag, opts?) -> Logger; Logger:debug/info/warn/error(msg, ...); Logger:every(key,
--            seconds, level, msg) (rate-limited); Log.setSink(fn); Log.setLevel(level); Log.setClock(fn);
--            Log.capture() -> records (tests)

export type Level = "debug" | "info" | "warn" | "error"
export type Record = { level: Level, tag: string, msg: string, t: number }
export type Sink = (record: Record) -> ()

local Log = {}

local RANK: { [Level]: number } = { debug = 1, info = 2, warn = 3, error = 4 }

local function defaultSink(r: Record)
	local line = `[{r.tag}] {r.msg}`
	if r.level == "warn" or r.level == "error" then
		warn(line)
	else
		print(line)
	end
end

local state = {
	sink = defaultSink :: Sink,
	level = "info" :: Level,
	clock = os.clock :: () -> number,
}

function Log.setSink(fn: Sink?)
	state.sink = fn or defaultSink
end

function Log.setLevel(level: Level)
	state.level = level
end

function Log.setClock(fn: (() -> number)?)
	state.clock = fn or os.clock
end

-- Swap the sink for a recorder; returns the list it appends to. Call Log.setSink() to restore.
function Log.capture(): { Record }
	local records: { Record } = {}
	state.sink = function(r: Record)
		table.insert(records, r)
	end
	return records
end

export type Logger = {
	tag: string,
	debug: (self: Logger, msg: string) -> (),
	info: (self: Logger, msg: string) -> (),
	warn: (self: Logger, msg: string) -> (),
	error: (self: Logger, msg: string) -> (),
	every: (self: Logger, key: string, seconds: number, level: Level, msg: string) -> boolean,
	suppressed: number,
	_last: { [string]: number },
}

local function emit(tag: string, level: Level, msg: string)
	if RANK[level] < RANK[state.level] then
		return
	end
	state.sink({ level = level, tag = tag, msg = msg, t = state.clock() })
end

function Log.new(tag: string): Logger
	local logger = { tag = tag, suppressed = 0, _last = {} } :: Logger
	function logger.debug(self: Logger, msg: string)
		emit(self.tag, "debug", msg)
	end
	function logger.info(self: Logger, msg: string)
		emit(self.tag, "info", msg)
	end
	function logger.warn(self: Logger, msg: string)
		emit(self.tag, "warn", msg)
	end
	function logger.error(self: Logger, msg: string)
		emit(self.tag, "error", msg)
	end
	-- Emits at most once per `seconds` per key; returns whether it emitted.
	function logger.every(self: Logger, key: string, seconds: number, level: Level, msg: string): boolean
		local now = state.clock()
		local last = self._last[key]
		if last and now - last < seconds then
			self.suppressed += 1
			return false
		end
		self._last[key] = now
		emit(self.tag, level, msg)
		return true
	end
	return logger
end

return Log
