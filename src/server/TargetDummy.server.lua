-- Keeps the block target dummies damageable and puts a fresh one back after they drop.

local ServerStorage = game:GetService("ServerStorage")

local RESPAWN_SECONDS = 2

local watched: { [Model]: boolean } = {}
local template: Model? = nil

local function capturePose(model: Model): { [string]: CFrame }
	local pose: { [string]: CFrame } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			pose[child.Name] = child.CFrame
		end
	end
	return pose
end

local function applyPose(model: Model, pose: { [string]: CFrame })
	for name, cf in pose do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.CFrame = cf
		end
	end
end

local function calm(humanoid: Humanoid)
	-- Anchored parts plus a quiet state machine: health still changes, but the rig
	-- does not ragdoll itself off the baseplate.
	humanoid.EvaluateStateMachine = false
	humanoid.BreakJointsOnDeath = false
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
end

local function watch(dummy: Model)
	if watched[dummy] then
		return
	end
	watched[dummy] = true

	if template == nil then
		local stored = dummy:Clone()
		stored.Name = "TargetDummyTemplate"
		stored.Parent = ServerStorage
		template = stored
	end

	local root = dummy:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		dummy.PrimaryPart = root
	end

	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		warn("Target dummy is missing a Humanoid: " .. dummy:GetFullName())
		return
	end
	calm(humanoid)

	local pending = false
	local function scheduleRespawn()
		if pending or template == nil or dummy.Parent == nil then
			return
		end
		pending = true
		task.delay(RESPAWN_SECONDS, function()
			pending = false
			if template == nil or dummy.Parent == nil then
				return
			end
			local pose = capturePose(dummy)
			local replacement = template:Clone()
			replacement.Name = dummy.Name
			applyPose(replacement, pose)
			replacement.Parent = workspace
			dummy:Destroy()
		end)
	end

	humanoid.Died:Connect(scheduleRespawn)
	humanoid.HealthChanged:Connect(function(health)
		if health <= 0 then
			scheduleRespawn()
		end
	end)

	dummy.Destroying:Connect(function()
		watched[dummy] = nil
	end)
end

local function consider(child: Instance)
	if child:IsA("Model") and child:GetAttribute("IsTargetDummy") == true then
		watch(child)
	end
end

workspace.ChildAdded:Connect(consider)
for _, child in workspace:GetChildren() do
	consider(child)
end
