--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.OwnerTune
-- The owner's tuning at a playtest (docs/owner/PAINTBALL_CHECK.md): a chat command, "/pb", that only the
-- place's owner is given (the server checks again: PaintballService, "the owner's tuning"; anyone else who
-- sends the verb is told "Only the place's owner can tune paintball.").
--   /pb                      what the feel is now, in words
--   /pb ballSpeed 150        one number of the feel, from the next match (Contract.FEEL_KEYS, with their ranges)
--   /pb rewind 0.3           the furthest a ball is judged back (0.25 in the contract)
--   /pb botSkill -0.2        how hard the bots are (-0.5 to 0.5)
-- The server answers in words ("Ball speed: 150 -> 120, from the next match"), shown in the feed and as a note;
-- a refusal's words are shown by the framework. The command is a TextChatCommand the client makes for itself
-- (the stock chat's own commands are made the same way), so nobody else's chat sees it and nobody else has it.
-- Interface: parse(text) -> (name, value?); isOwner(player) -> boolean; start(ctx) -> stop

local OwnerTune = {}

-- "/pb ballSpeed 150" -> "ballSpeed", 150; "/pb" -> "", nil; a value that is not a number -> name, nil.
function OwnerTune.parse(text: string): (string, number?)
	local words = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(words, word)
	end
	-- (the first word is the command itself)
	local name = words[2] or ""
	local value = if words[3] ~= nil then tonumber(words[3]) else nil
	return name, value
end

-- The place's owner, or Studio's own play test.
function OwnerTune.isOwner(player: any): boolean
	local ok, yes = pcall(function(): boolean
		if game:GetService("RunService"):IsStudio() then
			return true
		end
		return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
	end)
	return ok and yes == true
end

-- Give the owner the command (nothing for anyone else). Returns what takes it away again.
function OwnerTune.start(ctx: {
	send: (verb: string, args: { any }?) -> (),
	toast: (text: string, seconds: number?) -> (),
}): () -> ()
	local ok, command = pcall(function(): any
		local player = game:GetService("Players").LocalPlayer
		if not OwnerTune.isOwner(player) then
			return nil
		end
		local chat = game:GetService("TextChatService")
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "PaintballTune"
		cmd.PrimaryAlias = "/pb"
		cmd.Triggered:Connect(function(_source: any, text: string)
			local name, value = OwnerTune.parse(text)
			ctx.send("tune", { name, value :: any })
		end)
		cmd.Parent = chat
		return cmd
	end)
	if not ok or command == nil then
		return function() end
	end
	ctx.toast("Owner: type /pb in chat to see the feel, /pb ballSpeed 150 to change it", 8)
	return function()
		pcall(function()
			command:Destroy()
		end)
	end
end

return OwnerTune
