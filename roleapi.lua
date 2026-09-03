local Players = game:GetService("Players")

local Roles = {}

local ROLE = table.freeze({
	Murderer = "Murderer",
	Sheriff = "Sheriff",
	Innocent = "Innocent",
	Unknown = "Unknown"
})

local Config = {
	Knife = "Knife",
	Gun = "Gun",
	Interval = 0.1
}

local State = {
	Running = false,
	Roles = {},
	Connections = {},
	Listeners = {},
	NextListenerId = 0
}

local function isPlayer(player)
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

local function findTool(player, name)
	if not player then
		return nil
	end

	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")

	if character then
		local tool = character:FindFirstChild(name)

		if tool then
			return tool
		end
	end

	if backpack then
		local tool = backpack:FindFirstChild(name)

		if tool then
			return tool
		end
	end

	return nil
end

local function hasTool(player, name)
	return findTool(player, name) ~= nil
end

local function detect(player)
	if not isPlayer(player) then
		return ROLE.Unknown
	end

	if hasTool(player, Config.Knife) then
		return ROLE.Murderer
	end

	if hasTool(player, Config.Gun) then
		return ROLE.Sheriff
	end

	return ROLE.Innocent
end

local function fireChanged(player, newRole, oldRole)
	if newRole == oldRole then
		return
	end

	for _, listener in pairs(State.Listeners) do
		if listener.Connected then
			task.spawn(listener.Callback, player, newRole, oldRole)
		end
	end
end

local function update(player)
	if not isPlayer(player) then
		return ROLE.Unknown
	end

	local oldRole = State.Roles[player]
	local newRole = detect(player)

	State.Roles[player] = newRole

	fireChanged(player, newRole, oldRole)

	return newRole
end

local function disconnectPlayer(player)
	local connections = State.Connections[player]

	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end

	State.Connections[player] = nil
	State.Roles[player] = nil
end

local function refreshPlayer(player)
	if isPlayer(player) then
		task.defer(update, player)
	end
end

local function connectPlayer(player)
	if State.Connections[player] then
		return
	end

	local connections = {}

	local function refresh()
		refreshPlayer(player)
	end

	connections[#connections + 1] = player.CharacterAdded:Connect(refresh)
	connections[#connections + 1] = player.CharacterRemoving:Connect(refresh)

	local backpack = player:FindFirstChildOfClass("Backpack")

	if backpack then
		connections[#connections + 1] = backpack.ChildAdded:Connect(refresh)
		connections[#connections + 1] = backpack.ChildRemoved:Connect(refresh)
	end

	State.Connections[player] = connections

	update(player)
end

local function refreshAll()
	for _, player in ipairs(Players:GetPlayers()) do
		update(player)
	end
end

function Roles.Get(player)
	if player == nil then
		local result = {}

		for currentPlayer, role in pairs(State.Roles) do
			if isPlayer(currentPlayer) then
				result[currentPlayer] = role
			end
		end

		return result
	end

	if not isPlayer(player) then
		return ROLE.Unknown
	end

	return State.Roles[player] or detect(player)
end

function Roles.Is(player, role)
	return Roles.Get(player) == role
end

function Roles.GetPlayers(role)
	local result = {}

	if role == nil then
		return result
	end

	for player, currentRole in pairs(State.Roles) do
		if isPlayer(player) and currentRole == role then
			result[#result + 1] = player
		end
	end

	return result
end

function Roles.GetMurderer()
	for player, role in pairs(State.Roles) do
		if isPlayer(player) and role == ROLE.Murderer then
			return player
		end
	end

	return nil
end

function Roles.GetSheriff()
	for player, role in pairs(State.Roles) do
		if isPlayer(player) and role == ROLE.Sheriff then
			return player
		end
	end

	return nil
end

function Roles.Count(role)
	local count = 0

	for player, currentRole in pairs(State.Roles) do
		if isPlayer(player) and currentRole == role then
			count += 1
		end
	end

	return count
end

function Roles.Refresh(player)
	if player then
		return update(player)
	end

	refreshAll()

	return Roles
end

function Roles.OnChanged(callback)
	assert(
		type(callback) == "function",
		"Roles.OnChanged(callback): callback must be a function"
	)

	State.NextListenerId += 1

	local id = State.NextListenerId

	local connection = {
		Id = id,
		Connected = true,
		Callback = callback
	}

	State.Listeners[id] = connection

	function connection:Disconnect()
		if not self.Connected then
			return
		end

		self.Connected = false
		State.Listeners[self.Id] = nil
	end

	return connection
end

function Roles.Configure(options)
	if type(options) ~= "table" then
		return Roles
	end

	for key, value in pairs(options) do
		if Config[key] ~= nil then
			Config[key] = value
		end
	end

	refreshAll()

	return Roles
end

function Roles.GetConfig()
	return table.clone(Config)
end

function Roles.Start()
	if State.Running then
		return Roles
	end

	State.Running = true

	for _, player in ipairs(Players:GetPlayers()) do
		connectPlayer(player)
	end

	State.PlayerAdded = Players.PlayerAdded:Connect(connectPlayer)

	State.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
		disconnectPlayer(player)
	end)

	State.Scanner = task.spawn(function()
		while State.Running do
			refreshAll()
			task.wait(Config.Interval)
		end
	end)

	return Roles
end

function Roles.Stop()
	if not State.Running then
		return Roles
	end

	State.Running = false

	if State.PlayerAdded then
		State.PlayerAdded:Disconnect()
		State.PlayerAdded = nil
	end

	if State.PlayerRemoving then
		State.PlayerRemoving:Disconnect()
		State.PlayerRemoving = nil
	end

	for player in pairs(State.Connections) do
		disconnectPlayer(player)
	end

	State.Scanner = nil

	return Roles
end

function Roles.Destroy()
	Roles.Stop()

	for id in pairs(State.Listeners) do
		State.Listeners[id] = nil
	end

	table.clear(State.Roles)
	table.clear(State.Connections)

	return nil
end

function Roles.SetDetector(detector)
	assert(
		type(detector) == "function",
		"Roles.SetDetector(detector): detector must be a function"
	)

	Roles._Detector = detector
	refreshAll()

	return Roles
end

function Roles.Detect(player)
	if Roles._Detector then
		local success, result = pcall(Roles._Detector, player)

		if success and result then
			return result
		end
	end

	return detect(player)
end

function Roles.GetRole(player)
	return Roles.Get(player)
end

function Roles.GetAll()
	return Roles.Get()
end

function Roles.GetAllByRole(role)
	return Roles.GetPlayers(role)
end

Roles.Role = ROLE
Roles.Roles = ROLE

Roles.Start()

return Roles

