-- Server authority for the AK-47: welds, mesh swap, fire rate, magazine, raycast, tracers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local GunConfig = require(ReplicatedStorage:WaitForChild("GunConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fireRemote = remotes:WaitForChild("Fire") :: RemoteEvent
local reloadRemote = remotes:WaitForChild("Reload") :: RemoteEvent

-- How early a shot may arrive and still count. The cadence stays at FireInterval,
-- so this absorbs network jitter without raising the rounds-per-minute cap.
local FIRE_EARLY_TOLERANCE = 0.05

local nextShotAt: { [Player]: number } = {}
local reloadToken: { [Player]: number } = {}

local tracerFolder = Instance.new("Folder")
tracerFolder.Name = "BulletTracers"
tracerFolder.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = false

local function ensureWeld(tool: Tool, handle: BasePart, part: BasePart)
	-- Welds live in Tool.Welds as siblings so Rojo can link Part0/Part1.
	-- Rojo only keeps `id` on the root instance of a model file.
	local existing = tool:FindFirstChild(part.Name .. "Weld", true)
	if not (existing and existing:IsA("Weld")) then
		local childWeld = part:FindFirstChild("AssemblyWeld")
		if childWeld and childWeld:IsA("Weld") then
			existing = childWeld
		end
	end

	local weld: Weld
	if existing and existing:IsA("Weld") then
		weld = existing
	else
		local created = Instance.new("Weld")
		created.Name = "AssemblyWeld"
		created.Parent = part
		weld = created
	end

	-- Rojo sometimes drops Ref properties on the first live sync. While the handle
	-- is still at the authored origin, rebuild a missing offset from the part CFrame.
	local authoredOffset = weld.C0.Position.Magnitude
	if handle.Position.Magnitude < 0.5 and authoredOffset < 0.05 then
		local offset = handle.CFrame:ToObjectSpace(part.CFrame)
		if offset.Position.Magnitude > 0.2 then
			weld.C0 = offset
			weld.C1 = CFrame.new()
		end
	end

	weld.Part0 = handle
	weld.Part1 = part
end

local function applyMesh(tool: Tool, handle: BasePart)
	local meshId = GunConfig.MeshId
	if typeof(meshId) ~= "string" or meshId == "" then
		return
	end
	if tool:GetAttribute("MeshApplied") == true or tool:FindFirstChild("ImportedMesh", true) then
		tool:SetAttribute("MeshApplied", true)
		return
	end

	local meshPart = Instance.new("Part")
	meshPart.Name = "ImportedMesh"
	meshPart.Size = Vector3.new(1, 1, 1)
	meshPart.CFrame = handle.CFrame
	meshPart.Color = Color3.new(1, 1, 1)
	meshPart.Material = Enum.Material.SmoothPlastic
	meshPart.Anchored = false
	meshPart.CanCollide = false
	meshPart.CanQuery = false
	meshPart.CanTouch = false
	meshPart.Massless = true
	meshPart.TopSurface = Enum.SurfaceType.Smooth
	meshPart.BottomSurface = Enum.SurfaceType.Smooth
	meshPart.Parent = tool

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = meshId
	mesh.TextureId = if typeof(GunConfig.MeshTextureId) == "string" then GunConfig.MeshTextureId else ""
	mesh.Scale = GunConfig.MeshScale
	mesh.Parent = meshPart

	local weld = Instance.new("Weld")
	weld.Name = "AssemblyWeld"
	weld.C0 = GunConfig.MeshOffset
	weld.C1 = CFrame.new()
	weld.Part0 = handle
	weld.Part1 = meshPart
	weld.Parent = meshPart

	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= meshPart then
			descendant.Transparency = 1
		end
	end

	tool:SetAttribute("MeshApplied", true)
end

local function prepareTool(tool: Tool)
	if not GunConfig.isGun(tool) then
		return
	end
	if typeof(tool:GetAttribute("Ammo")) ~= "number" then
		tool:SetAttribute("Ammo", GunConfig.MagazineSize)
	end
	if typeof(tool:GetAttribute("Reloading")) ~= "boolean" then
		tool:SetAttribute("Reloading", false)
	end

	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end

	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= handle and descendant.Name ~= "ImportedMesh" then
			ensureWeld(tool, handle, descendant)
		end
	end

	applyMesh(tool, handle)
end

local function dedupeGuns(player: Player)
	local found: { Tool } = {}
	local function collect(container: Instance?)
		if container == nil then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and GunConfig.isGun(child) then
				table.insert(found, child)
			end
		end
	end

	collect(player.Character)
	collect(player:FindFirstChild("Backpack"))
	if #found <= 1 then
		return
	end

	local keep = found[1]
	for _, gun in found do
		if gun.Parent == player.Character then
			keep = gun
			break
		end
	end
	for _, gun in found do
		if gun ~= keep then
			gun:Destroy()
		end
	end
end

local function watchPlayer(player: Player)
	local backpack = player:WaitForChild("Backpack")

	local function onChild(child: Instance)
		if child:IsA("Tool") and GunConfig.isGun(child) then
			prepareTool(child)
			dedupeGuns(player)
		end
	end

	backpack.ChildAdded:Connect(onChild)
	for _, child in backpack:GetChildren() do
		onChild(child)
	end

	local function watchCharacter(character: Model)
		character.ChildAdded:Connect(onChild)
		for _, child in character:GetChildren() do
			onChild(child)
		end
		task.defer(function()
			dedupeGuns(player)
		end)
	end

	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

local function getEquippedTool(player: Player): Tool?
	local character = player.Character
	if character == nil then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and GunConfig.isGun(child) then
			return child
		end
	end
	return nil
end

local function isFiniteVector(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local x, y, z = value.X, value.Y, value.Z
	if x ~= x or y ~= y or z ~= z then
		return false
	end
	return math.abs(x) < 1e5 and math.abs(y) < 1e5 and math.abs(z) < 1e5
end

local function consumeShot(player: Player, now: number): boolean
	local interval = GunConfig.FireInterval
	local scheduled = nextShotAt[player]
	if scheduled == nil or now >= scheduled then
		nextShotAt[player] = now + interval
		return true
	end
	if scheduled - now > FIRE_EARLY_TOLERANCE then
		return false
	end
	nextShotAt[player] = scheduled + interval
	return true
end

local function damageHumanoid(hit: Instance, attacker: Model)
	local model = hit:FindFirstAncestorOfClass("Model")
	if model == nil or model == attacker then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end
	humanoid:TakeDamage(GunConfig.Damage)
end

local function lookAtSafe(fromPosition: Vector3, toPosition: Vector3): CFrame
	local direction = toPosition - fromPosition
	if math.abs(direction.Unit:Dot(Vector3.yAxis)) > 0.999 then
		return CFrame.lookAt(fromPosition, toPosition, Vector3.xAxis)
	end
	return CFrame.lookAt(fromPosition, toPosition)
end

local function spawnTracer(fromPosition: Vector3, toPosition: Vector3)
	local delta = toPosition - fromPosition
	local distance = delta.Magnitude
	if distance < 0.2 then
		return
	end

	local tracer = Instance.new("Part")
	tracer.Name = "Tracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = GunConfig.TracerColor
	tracer.Size = Vector3.new(GunConfig.TracerThickness, GunConfig.TracerThickness, distance)
	tracer.CFrame = lookAtSafe(fromPosition, toPosition) * CFrame.new(0, 0, -distance / 2)
	tracer.Parent = tracerFolder

	task.delay(GunConfig.TracerLifetime, function()
		tracer:Destroy()
	end)
end

local function getMuzzlePosition(tool: Tool, fallback: Vector3): Vector3
	local muzzle = tool:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return (handle.CFrame * CFrame.new(0, 0.7, -2.6)).Position
	end
	return fallback
end

local function onFire(player: Player, aimPoint: unknown)
	if not isFiniteVector(aimPoint) then
		return
	end

	local tool = getEquippedTool(player)
	if tool == nil or tool:GetAttribute("Reloading") == true then
		return
	end

	local character = player.Character
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end

	local ammo = tool:GetAttribute("Ammo")
	if typeof(ammo) ~= "number" or ammo <= 0 then
		return
	end

	local originPart: BasePart? = nil
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		originPart = head
	else
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			originPart = root
		end
	end
	if originPart == nil then
		return
	end

	local origin = originPart.Position
	local offset = (aimPoint :: Vector3) - origin
	local distance = offset.Magnitude
	if distance < 1e-3 then
		return
	end

	if not consumeShot(player, os.clock()) then
		return
	end

	tool:SetAttribute("Ammo", ammo - 1)

	local travel = math.min(distance, GunConfig.Range)
	local direction = offset.Unit
	rayParams.FilterDescendantsInstances = { character, tracerFolder }

	local result = workspace:Raycast(origin, direction * travel, rayParams)
	local endPosition = origin + direction * travel
	if result then
		endPosition = result.Position
		damageHumanoid(result.Instance, character)
	end

	spawnTracer(getMuzzlePosition(tool, origin), endPosition)
end

local function onReload(player: Player)
	local tool = getEquippedTool(player)
	if tool == nil or tool:GetAttribute("Reloading") == true then
		return
	end

	local ammo = tool:GetAttribute("Ammo")
	if typeof(ammo) ~= "number" then
		ammo = 0
	end
	if ammo >= GunConfig.MagazineSize then
		return
	end

	local reloadTime = GunConfig.ReloadTime
	if typeof(reloadTime) ~= "number" or reloadTime < 0 then
		reloadTime = 0
	end

	tool:SetAttribute("Reloading", true)
	reloadToken[player] = (reloadToken[player] or 0) + 1
	local token = reloadToken[player]

	task.delay(reloadTime, function()
		if reloadToken[player] ~= token or tool.Parent == nil then
			return
		end
		tool:SetAttribute("Ammo", GunConfig.MagazineSize)
		tool:SetAttribute("Reloading", false)
	end)
end

local template = StarterPack:FindFirstChild(GunConfig.ToolName)
if template and template:IsA("Tool") then
	prepareTool(template)
end

fireRemote.OnServerEvent:Connect(onFire)
reloadRemote.OnServerEvent:Connect(onReload)

Players.PlayerAdded:Connect(function(player)
	task.spawn(watchPlayer, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(watchPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	nextShotAt[player] = nil
	reloadToken[player] = nil
end)
