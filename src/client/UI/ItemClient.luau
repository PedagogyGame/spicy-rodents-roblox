--!strict
-- StarterPlayerScripts.Client.UI.ItemClient
-- The client's part of the corner store's items (Server/Items/ItemWorld sends { kind = "item", action, ... } on the
-- play Event remote; Main.client hands it here):
--   askText     the chalk: a small box for up to `max` letters; Write (Enter, the button, a tap) sends the words to
--               the server (ReplicatedStorage.CornerStoreItemText), which filters them before anyone sees them;
--               Cancel or Escape closes it
--   screenshot  the disposable camera: a white flash, then the engine's own screenshot (CaptureService) and its
--               offer to save it to the player's captures; `left` shots remain
-- Interface: handle(msg, toast) -> handled?; REMOTE
-- Engine only inside the functions; no side effects on require.

local ItemClient = {}

ItemClient.REMOTE = "CornerStoreItemText" -- (Server/Items/CornerStore.REMOTE)

local open: ScreenGui? = nil

local function close()
	if open then
		open:Destroy()
		open = nil
	end
end

local function askText(item: string, max: number)
	close()
	local Players = game:GetService("Players")
	local gui = Instance.new("ScreenGui")
	gui.Name = "ItemText"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -120)
	frame.Size = UDim2.fromOffset(340, 96)
	frame.BackgroundColor3 = Color3.fromRGB(40, 34, 30)
	frame.BackgroundTransparency = 0.1
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -24, 0, 22)
	title.Text = `Write on the ground (up to {max} letters)`
	title.TextColor3 = Color3.fromRGB(250, 240, 220)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	title.TextSize = 15
	title.Parent = frame
	local box = Instance.new("TextBox")
	box.Position = UDim2.fromOffset(12, 34)
	box.Size = UDim2.new(1, -110, 0, 44)
	box.BackgroundColor3 = Color3.fromRGB(250, 246, 236)
	box.Text = ""
	box.PlaceholderText = "hello"
	box.ClearTextOnFocus = false
	box.TextSize = 20
	box.FontFace = Font.fromEnum(Enum.Font.PatrickHand)
	box.Parent = frame
	local write = Instance.new("TextButton")
	write.Position = UDim2.new(1, -90, 0, 34)
	write.Size = UDim2.fromOffset(78, 44)
	write.BackgroundColor3 = Color3.fromRGB(214, 170, 76)
	write.Text = "Write"
	write.TextSize = 18
	write.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	write.Parent = frame
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	open = gui
	-- keep it to `max` letters as it is typed
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local n = utf8.len(box.Text)
		if n and n > max then
			box.Text = string.sub(box.Text, 1, (utf8.offset(box.Text, max + 1) or (#box.Text + 1)) - 1)
		end
	end)
	local function send()
		local text = box.Text
		close()
		local remote = game:GetService("ReplicatedStorage"):FindFirstChild(ItemClient.REMOTE)
		if remote and remote:IsA("RemoteEvent") and text ~= "" then
			remote:FireServer(item, text)
		end
	end
	write.Activated:Connect(send)
	box.FocusLost:Connect(function(enter: boolean)
		if enter then
			send()
		end
	end)
	box:CaptureFocus()
end

local function screenshot(left: number?, toast: (string, number) -> ())
	local Players = game:GetService("Players")
	-- the flash
	local gui = Instance.new("ScreenGui")
	gui.Name = "CameraFlash"
	gui.IgnoreGuiInset = true
	local white = Instance.new("Frame")
	white.Size = UDim2.fromScale(1, 1)
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BackgroundTransparency = 0.2
	white.Parent = gui
	-- the picture first, then the flash (so the flash is not in it)
	local ok = pcall(function()
		local capture = game:GetService("CaptureService") :: any
		capture:CaptureScreenshot(function(contentId: any)
			pcall(function()
				capture:PromptSaveCapturesToGallery({ contentId }, function() end)
			end)
		end)
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	game:GetService("TweenService"):Create(white, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(gui, 0.5)
	if not ok then
		toast("Click! (screenshots are not available here)", 2.5)
	elseif left and left > 0 then
		toast(`Click! {left} shots left`, 2)
	elseif left then
		toast("Click! That was the last shot on the camera", 2.5)
	end
end

function ItemClient.handle(msg: { [string]: any }, toast: (string, number) -> ()): boolean
	if msg.action == "askText" then
		askText(tostring(msg.item), if type(msg.max) == "number" then msg.max else 20)
		return true
	elseif msg.action == "screenshot" then
		screenshot(if type(msg.left) == "number" then msg.left else nil, toast)
		return true
	end
	return false
end

return ItemClient
