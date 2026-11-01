-- Shared tuning for the AK-47. The server and the client both read this module.
-- FireInterval is derived from RoundsPerMinute; edit the rate, not the interval.

local GunConfig = {
	ToolName = "AK-47",
	-- Stamped on the Tool in init.meta.json. Scripts accept this or ToolName.
	GunId = "AK47",

	Damage = 20,
	RoundsPerMinute = 600,
	MagazineSize = 30,
	ReloadTime = 2,
	-- Longest server ray, in studs, measured from the shooter's head.
	Range = 400,

	TracerThickness = 0.07,
	TracerLifetime = 0.06,
	TracerColor = Color3.fromRGB(255, 170, 50),

	-- Leave MeshId empty to keep the welded block model in Handle.model.json.
	-- Set an rbxassetid:// id (Toolbox mesh) to hide those parts and show a SpecialMesh.
	MeshId = "",
	MeshTextureId = "",
	MeshScale = Vector3.new(1, 1, 1),
	-- Imported mesh pivot relative to Handle. With the default grip, -Z is forward and +Y is up.
	MeshOffset = CFrame.new(0, 0.45, -0.4),
}

local rpm = GunConfig.RoundsPerMinute
if typeof(rpm) ~= "number" or rpm <= 0 then
	rpm = 600
	GunConfig.RoundsPerMinute = rpm
end
GunConfig.FireInterval = 60 / rpm

function GunConfig.isGun(instance: Instance?): boolean
	if instance == nil or not instance:IsA("Tool") then
		return false
	end
	if instance:GetAttribute("GunId") == GunConfig.GunId then
		return true
	end
	return instance.Name == GunConfig.ToolName
end

return GunConfig
