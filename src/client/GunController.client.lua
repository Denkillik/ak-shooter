-- Local AK-47 input, crosshair, and ammo readout. Hits are decided on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GunConfig = require(ReplicatedStorage:WaitForChild("GunConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fireRemote = remotes:WaitForChild("Fire") :: RemoteEvent
local reloadRemote = remotes:WaitForChild("Reload") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local LOW_AMMO = 10
local equippedTool: Tool? = nil
local pumpRunning = false

local gui = Instance.new("ScreenGui")
gui.Name = "GunHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "AmmoPanel"
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -20, 1, -20)
panel.Size = UDim2.fromOffset(200, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
panel.BackgroundTransparency = 0.2
panel.BorderSizePixel = 0
panel.Active = false
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(255, 255, 255)
panelStroke.Transparency = 0.75
panelStroke.Thickness = 1
panelStroke.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 2)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local function makeLabel(name: string, order: number, textSize: number, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, textSize + 4)
	label.Font = font
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.Text = ""
	label.Active = false
	label.Parent = panel
	return label
end

local titleLabel = makeLabel("Title", 1, 14, Enum.Font.BuilderSansBold)
titleLabel.Text = "AK-47"
titleLabel.TextColor3 = Color3.fromRGB(255, 214, 140)

local ammoLabel = makeLabel("Ammo", 2, 28, Enum.Font.BuilderSansBold)
ammoLabel.Text = "30 / 30"

local statusLabel = makeLabel("Status", 3, 14, Enum.Font.BuilderSans)
statusLabel.Text = "R to reload"
statusLabel.TextColor3 = Color3.fromRGB(190, 190, 190)

local crosshair = Instance.new("Frame")
crosshair.Name = "Crosshair"
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(0, 0)
crosshair.BackgroundTransparency = 1
crosshair.BorderSizePixel = 0
crosshair.Active = false
crosshair.Parent = gui

local function addTick(size: UDim2, position: UDim2)
	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Size = size
	mark.Position = position
	mark.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	mark.BorderSizePixel = 0
	mark.Active = false
	mark.Parent = crosshair

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = mark
end

addTick(UDim2.fromOffset(8, 2), UDim2.fromOffset(-10, 0))
addTick(UDim2.fromOffset(8, 2), UDim2.fromOffset(10, 0))
addTick(UDim2.fromOffset(2, 8), UDim2.fromOffset(0, -10))
addTick(UDim2.fromOffset(2, 8), UDim2.fromOffset(0, 10))
addTick(UDim2.fromOffset(2, 2), UDim2.fromOffset(0, 0))

local function refreshHud()
	local tool = equippedTool
	if tool == nil then
		return
	end

	local ammo = tool:GetAttribute("Ammo")
	local amount = if typeof(ammo) == "number" then ammo else 0
	local reloading = tool:GetAttribute("Reloading") == true
	ammoLabel.Text = string.format("%d / %d", amount, GunConfig.MagazineSize)

	if reloading then
		ammoLabel.TextColor3 = Color3.fromRGB(255, 196, 64)
		statusLabel.Text = "Reloading..."
		statusLabel.TextColor3 = Color3.fromRGB(255, 176, 64)
	elseif amount <= 0 then
		ammoLabel.TextColor3 = Color3.fromRGB(255, 84, 64)
		statusLabel.Text = "R to reload"
		statusLabel.TextColor3 = Color3.fromRGB(255, 84, 64)
	elseif amount <= LOW_AMMO then
		ammoLabel.TextColor3 = Color3.fromRGB(255, 196, 64)
		statusLabel.Text = "R to reload"
		statusLabel.TextColor3 = Color3.fromRGB(190, 190, 190)
	else
		ammoLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
		statusLabel.Text = "R to reload"
		statusLabel.TextColor3 = Color3.fromRGB(190, 190, 190)
	end
end

local function pointerOverActiveGui(): boolean
	local mouse = player:GetMouse()
	local objects = playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
	for _, object in objects do
		if object:IsA("GuiObject") and object.Active then
			return true
		end
	end
	return false
end

local function getAimPoint(): Vector3
	local camera = workspace.CurrentCamera
	local mouse = player:GetMouse()
	if camera == nil then
		return mouse.Hit.Position
	end

	local viewportRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local direction = viewportRay.Direction
	if direction.Magnitude < 1e-4 then
		return mouse.Hit.Position
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = player.Character
	params.FilterDescendantsInstances = if character then { character } else {}

	local unit = direction.Unit
	local result = workspace:Raycast(viewportRay.Origin, unit * GunConfig.Range, params)
	if result then
		return result.Position
	end
	return viewportRay.Origin + unit * GunConfig.Range
end

local function fireOnce(tool: Tool)
	if tool:GetAttribute("Reloading") == true then
		return
	end
	local ammo = tool:GetAttribute("Ammo")
	if typeof(ammo) == "number" and ammo <= 0 then
		return
	end
	fireRemote:FireServer(getAimPoint())
end

local function ensurePump()
	if pumpRunning then
		return
	end
	pumpRunning = true
	task.spawn(function()
		while equippedTool do
			local tool = equippedTool
			local triggerDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
			if tool and triggerDown and not pointerOverActiveGui() then
				fireOnce(tool)
				task.wait(GunConfig.FireInterval)
			else
				task.wait(0.03)
			end
		end
		pumpRunning = false
		if equippedTool then
			ensurePump()
		end
	end)
end

local function setEquipped(tool: Tool?)
	equippedTool = tool
	gui.Enabled = tool ~= nil
	if tool then
		refreshHud()
		ensurePump()
	end
end

local hooked: { [Tool]: boolean } = {}

local function hookTool(tool: Tool)
	if hooked[tool] or not GunConfig.isGun(tool) then
		return
	end
	hooked[tool] = true

	tool.Equipped:Connect(function()
		setEquipped(tool)
	end)
	tool.Unequipped:Connect(function()
		if equippedTool == tool then
			setEquipped(nil)
		end
	end)
	tool:GetAttributeChangedSignal("Ammo"):Connect(function()
		if equippedTool == tool then
			refreshHud()
		end
	end)
	tool:GetAttributeChangedSignal("Reloading"):Connect(function()
		if equippedTool == tool then
			refreshHud()
		end
	end)
	tool.Destroying:Connect(function()
		hooked[tool] = nil
		if equippedTool == tool then
			setEquipped(nil)
		end
	end)

	if tool.Parent and tool.Parent:IsA("Model") then
		setEquipped(tool)
	end
end

local function watchContainer(container: Instance)
	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			hookTool(child)
		end
	end)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			hookTool(child)
		end
	end
end

local backpack = player:WaitForChild("Backpack")
watchContainer(backpack)

player.CharacterAdded:Connect(function(character)
	watchContainer(character)
end)
if player.Character then
	watchContainer(player.Character)
end

player.CharacterRemoving:Connect(function()
	setEquipped(nil)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or equippedTool == nil then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		reloadRemote:FireServer()
	end
end)

RunService.RenderStepped:Connect(function()
	if not gui.Enabled then
		return
	end
	local mouse = player:GetMouse()
	crosshair.Position = UDim2.fromOffset(mouse.X, mouse.Y)
end)
