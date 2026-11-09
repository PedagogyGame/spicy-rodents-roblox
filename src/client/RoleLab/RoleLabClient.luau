--!strict
-- StarterPlayer.StarterPlayerScripts.Client.RoleLab.RoleLabClient
-- The dev-only Role Lab panel (BUILD_PLAN §4.4 #4 "Become X"; the full Lab is W2 #6b): one button per
-- rung and side exit, each sending `Lab.Command` { cmd = "become", args = { rung } }, plus Export
-- tuning and Reset session. The server refuses non-devs (Server/Roles/RoleLab); the panel is only
-- mounted for devs. model() is pure (Lune-tested); mount() builds the ScreenGui and is called by the
-- client's init, never on require.
-- Interface: model() -> { Button }; mount(parent, send) -> ScreenGui

export type Button = { label: string, cmd: string, args: { any } }

local RoleLabClient = {}

-- Mirrors Server/Roles/RoleLab.RUNGS (the Lab never edits the ladder; labels only).
local RUNGS = {
	{ "human", "Townsperson" },
	{ "hospital", "Hospital staff" },
	{ "police", "Police" },
	{ "squirrel", "Squirrel" },
	{ "rodent", "Spicy rodent" },
	{ "deer", "Deer" },
	{ "fox", "Fox" },
}

function RoleLabClient.model(): { Button }
	local out: { Button } = {}
	for _, r in RUNGS do
		table.insert(out, { label = `Become {r[2]}`, cmd = "become", args = { r[1] } })
	end
	table.insert(out, { label = "Export tuning", cmd = "export", args = {} })
	table.insert(out, { label = "Reset session", cmd = "reset", args = {} })
	return out
end

function RoleLabClient.mount(parent: Instance, send: (cmd: string, args: { any }) -> ()): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoleLab"
	gui.ResetOnSpawn = false
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(180, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Position = UDim2.new(1, -190, 0, 80)
	frame.BackgroundTransparency = 0.3
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = frame
	for i, b in RoleLabClient.model() do
		local button = Instance.new("TextButton")
		button.Name = `Lab{i}`
		button.LayoutOrder = i
		button.Size = UDim2.new(1, 0, 0, 26)
		button.Text = b.label
		button.Parent = frame
		button.Activated:Connect(function()
			send(b.cmd, b.args)
		end)
	end
	gui.Parent = parent
	return gui
end

return RoleLabClient
