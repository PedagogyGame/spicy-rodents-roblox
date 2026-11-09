--!strict
-- ServerScriptService.Server.Telemetry
-- Per-system ms, actor counts by LOD tier, remote bytes, arena ms (BUILD_PLAN §1.4; F-14: "AI under
-- 4 ms per frame on average" is a regression signal read from here). A scope measures one system per
-- frame; frame() closes the frame and folds it into rolling stats (mean, max, last); report() returns a
-- plain table (engine tasks print it as JSON). Pure with an injected clock; no side effects on require.
-- Interface: new(clock?) -> Telemetry; T:scope(name) -> stop(); T:add(name, ms); T:count(name, n);
--            T:bytes(remote, n); T:frame(); T:report() -> Report; T:over(name, budgetMs) -> boolean

export type Series = { n: number, total: number, max: number, last: number, frame: number }
export type Report = {
	frames: number,
	systems: { [string]: { mean: number, max: number, last: number } },
	counts: { [string]: number },
	bytes: { [string]: number },
}
export type Telemetry = {
	clock: () -> number,
	frames: number,
	series: { [string]: Series },
	counts: { [string]: number },
	remoteBytes: { [string]: number },
	scope: (self: Telemetry, name: string) -> () -> number,
	add: (self: Telemetry, name: string, ms: number) -> (),
	count: (self: Telemetry, name: string, n: number) -> (),
	bytes: (self: Telemetry, remote: string, n: number) -> (),
	frame: (self: Telemetry) -> (),
	report: (self: Telemetry) -> Report,
	over: (self: Telemetry, name: string, budgetMs: number) -> boolean,
}

local Telemetry = {}

function Telemetry.new(clock: (() -> number)?): Telemetry
	local t = {
		clock = clock or os.clock,
		frames = 0,
		series = {},
		counts = {},
		remoteBytes = {},
	} :: Telemetry

	local function seriesOf(self: Telemetry, name: string): Series
		local s = self.series[name]
		if not s then
			s = { n = 0, total = 0, max = 0, last = 0, frame = 0 }
			self.series[name] = s
		end
		return s
	end

	-- Accumulates into the current frame; returns a stop function that yields the elapsed ms.
	function t.scope(self: Telemetry, name: string): () -> number
		local t0 = self.clock()
		return function(): number
			local ms = (self.clock() - t0) * 1000
			self:add(name, ms)
			return ms
		end
	end

	function t.add(self: Telemetry, name: string, ms: number)
		local s = seriesOf(self, name)
		s.frame += ms
	end

	-- Gauges (actor counts by LOD tier: "actors.near", "actors.mid", "actors.far", ...).
	function t.count(self: Telemetry, name: string, n: number)
		self.counts[name] = n
	end

	function t.bytes(self: Telemetry, remote: string, n: number)
		self.remoteBytes[remote] = (self.remoteBytes[remote] or 0) + n
	end

	function t.frame(self: Telemetry)
		self.frames += 1
		for _, s in self.series do
			s.n += 1
			s.total += s.frame
			s.last = s.frame
			if s.frame > s.max then
				s.max = s.frame
			end
			s.frame = 0
		end
	end

	function t.report(self: Telemetry): Report
		local systems = {}
		for name, s in self.series do
			systems[name] = { mean = if s.n > 0 then s.total / s.n else 0, max = s.max, last = s.last }
		end
		return {
			frames = self.frames,
			systems = systems,
			counts = table.clone(self.counts),
			bytes = table.clone(self.remoteBytes),
		}
	end

	function t.over(self: Telemetry, name: string, budgetMs: number): boolean
		local s = self.series[name]
		return s ~= nil and s.n > 0 and s.total / s.n > budgetMs
	end

	return t
end

return Telemetry
