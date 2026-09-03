local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraLock = {}

local LocalPlayer = Players.LocalPlayer

local Config = {
	Enabled = false,
	Target = nil,

	TargetPart = "Head",
	TargetParts = {
		"Head",
		"HumanoidRootPart",
		"UpperTorso",
		"LowerTorso"
	},

	Smoothing = 0.15,
	FOV = 150,

	TeamCheck = false,
	WallCheck = true,
	AliveCheck = true,

	PredictMovement = false,
	Prediction = 0.12,

	UseFOV = true,
	AutoTarget = false,

	TargetFilter = nil,

	Offset = Vector3.zero
}

local State = {
	Running = false,
	Connection = nil,
	Target = nil
}

local function getCharacter(player)
	return player and player.Character
end

local function getHumanoid(player)
	local character = getCharacter(player)
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function isAlive(player)
	local humanoid = getHumanoid(player)
	return humanoid and humanoid.Health > 0
end

local function getPart(player, partName)
	local character = getCharacter(player)

	if not character then
		return nil
	end

	return character:FindFirstChild(partName)
end

local function getTargetPart(player)
	for _, partName in ipairs(Config.TargetParts) do
		local part = getPart(player, partName)

		if part then
			return part
		end
	end

	return getPart(player, Config.TargetPart)
end

local function isVisible(part)
	if not Config.WallCheck then
		return true
	end

	local camera = Workspace.CurrentCamera

	if not camera then
		return false
	end

	local origin = camera.CFrame.Position
	local direction = part.Position - origin

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		LocalPlayer.Character
	}

	local result = Workspace:Raycast(origin, direction, params)

	return not result or result.Instance:IsDescendantOf(part.Parent)
end

local function inFOV(part)
	if not Config.UseFOV then
		return true
	end

	local camera = Workspace.CurrentCamera

	if not camera then
		return false
	end

	local screenPosition, visible = camera:WorldToViewportPoint(part.Position)

	if not visible then
		return false
	end

	local center = camera.ViewportSize / 2
	local distance = (
		Vector2.new(screenPosition.X, screenPosition.Y) - center
	).Magnitude

	return distance <= Config.FOV
end

local function validTarget(player)
	if not player or player == LocalPlayer then
		return false
	end

	if player.Parent ~= Players then
		return false
	end

	if Config.AliveCheck and not isAlive(player) then
		return false
	end

	if Config.TeamCheck and LocalPlayer.Team == player.Team then
		return false
	end

	if Config.TargetFilter and not Config.TargetFilter(player) then
		return false
	end

	local part = getTargetPart(player)

	if not part then
		return false
	end

	if not inFOV(part) then
		return false
	end

	if not isVisible(part) then
		return false
	end

	return true
end

local function getClosestTarget()
	local camera = Workspace.CurrentCamera

	if not camera then
		return nil
	end

	local closest
	local closestDistance = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		if validTarget(player) then
			local part = getTargetPart(player)
			local screenPosition = camera:WorldToViewportPoint(part.Position)
			local center = camera.ViewportSize / 2

			local distance = (
				Vector2.new(screenPosition.X, screenPosition.Y) - center
			).Magnitude

			if distance < closestDistance then
				closestDistance = distance
				closest = player
			end
		end
	end

	return closest
end

local function getPosition(player)
	local part = getTargetPart(player)

	if not part then
		return nil
	end

	local position = part.Position + Config.Offset

	if Config.PredictMovement then
		position += part.AssemblyLinearVelocity * Config.Prediction
	end

	return position
end

local function update()
	if not Config.Enabled then
		return
	end

	local camera = Workspace.CurrentCamera

	if not camera then
		return
	end

	if Config.AutoTarget then
		State.Target = getClosestTarget()
	else
		State.Target = Config.Target
	end

	if not validTarget(State.Target) then
		return
	end

	local position = getPosition(State.Target)

	if not position then
		return
	end

	local goal = CFrame.lookAt(camera.CFrame.Position, position)

	camera.CFrame = camera.CFrame:Lerp(
		goal,
		math.clamp(Config.Smoothing, 0, 1)
	)
end

function CameraLock.Start()
	if State.Running then
		return CameraLock
	end

	State.Running = true
	Config.Enabled = true

	State.Connection = RunService.RenderStepped:Connect(update)

	return CameraLock
end

function CameraLock.Stop()
	Config.Enabled = false
	State.Target = nil

	if State.Connection then
		State.Connection:Disconnect()
		State.Connection = nil
	end

	State.Running = false

	return CameraLock
end

function CameraLock.Toggle()
	if State.Running then
		return CameraLock.Stop()
	end

	return CameraLock.Start()
end

function CameraLock.SetTarget(player)
	if player == nil or validTarget(player) then
		Config.Target = player
		State.Target = player
	end

	return CameraLock
end

function CameraLock.GetTarget()
	return State.Target
end

function CameraLock.FindTarget()
	local target = getClosestTarget()

	State.Target = target

	return target
end

function CameraLock.Set(part, value)
	if Config[part] ~= nil then
		Config[part] = value
	end

	return CameraLock
end

function CameraLock.Configure(options)
	if type(options) ~= "table" then
		return CameraLock
	end

	for key, value in pairs(options) do
		if Config[key] ~= nil then
			Config[key] = value
		end
	end

	return CameraLock
end

function CameraLock.GetConfig()
	return table.clone(Config)
end

function CameraLock.IsRunning()
	return State.Running
end

function CameraLock.IsValid(player)
	return validTarget(player)
end

function CameraLock.GetClosest()
	return getClosestTarget()
end

function CameraLock.Destroy()
	CameraLock.Stop()

	table.clear(State)

	return nil
end

CameraLock.Config = Config

return CameraLock
