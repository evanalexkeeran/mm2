local Players = game:GetService("Players")

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
	Roles = {},
	Connections = {},
	Listeners = {},
	Running = false,
	ListenerId = 0,
	Scanner = nil,
	PlayerAdded = nil,
	PlayerRemoving = nil
}

local API = {}

local function isPlayer(player)
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

local function findTool(player, name)
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
end

local function hasTool(player, name)
	return findTool(player, name) ~= nil
end

local function defaultDetector(player)
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

local function detect(player)
	local detector = API.Detector

	if detector then
		local success, role = pcall(detector, player)

		if success and role ~= nil then
			return role
		end
	end

	return defaultDetector(player)
end

local function emit(player, newRole, oldRole)
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

	emit(player, newRole, oldRole)

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

local function refresh(player)
	if isPlayer(player) then
		task.defer(update, player)
	end
end

local function connectPlayer(player)
	if State.Connections[player] then
		return
	end

	local connections = {}

	connections[#connections + 1] = player.CharacterAdded:Connect(function()
		refresh(player)
	end)

	connections[#connections + 1] = player.CharacterRemoving:Connect(function()
		refresh(player)
	end)

	local backpack = player:FindFirstChildOfClass("Backpack")

	if backpack then
		connections[#connections + 1] = backpack.ChildAdded:Connect(function()
			refresh(player)
		end)

		connections[#connections + 1] = backpack.ChildRemoved:Connect(function()
			refresh(player)
		end)
	end

	State.Connections[player] = connections

	update(player)
end

local function refreshAll()
	for _, player in ipairs(Players:GetPlayers()) do
		update(player)
	end
end

function API.Get(player)
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

function API.Is(player, role)
	return API.Get(player) == role
end

function API.GetPlayers(role)
	local result = {}

	if not role then
		return result
	end

	for player, currentRole in pairs(State.Roles) do
		if isPlayer(player) and currentRole == role then
			result[#result + 1] = player
		end
	end

	return result
end

function API.GetMurderer()
	return API.GetPlayers(ROLE.Murderer)[1]
end

function API.GetSheriff()
	return API.GetPlayers(ROLE.Sheriff)[1]
end

function API.Count(role)
	local count = 0

	for player, currentRole in pairs(State.Roles) do
		if isPlayer(player) and currentRole == role then
			count += 1
		end
	end

	return count
end

function API.OnChanged(callback)
	assert(
		type(callback) == "function",
		"RoleAPI: callback must be a function"
	)

	State.ListenerId += 1

	local id = State.ListenerId

	local connection = {
		Id = id,
		Callback = callback,
		Connected = true
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

function API.Refresh(player)
	if player then
		return update(player)
	end

	refreshAll()

	return API
end

function API.Configure(options)
	if type(options) ~= "table" then
		return API
	end

	for key, value in pairs(options) do
		if Config[key] ~= nil then
			Config[key] = value
		end
	end

	refreshAll()

	return API
end

function API.GetConfig()
	return table.clone(Config)
end

function API.SetDetector(detector)
	assert(
		type(detector) == "function",
		"RoleAPI: detector must be a function"
	)

	API.Detector = detector

	refreshAll()

	return API
end

function API.Detect(player)
	return detect(player)
end

function API.Start()
	if State.Running then
		return API
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

	return API
end

function API.Stop()
	if not State.Running then
		return API
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

	return API
end

function API.Destroy()
	API.Stop()

	for id in pairs(State.Listeners) do
		State.Listeners[id] = nil
	end

	table.clear(State.Roles)
	table.clear(State.Connections)

	API.Detector = nil
end

API.Role = ROLE
API.Roles = ROLE

API.GetRole = API.Get
API.GetAll = API.Get
API.GetAllByRole = API.GetPlayers

setmetatable(API, {
	__call = function(_, value)
		if type(value) == "function" then
			return API.OnChanged(value)
		end

		if typeof(value) == "Instance" and value:IsA("Player") then
			return API.Get(value)
		end

		if type(value) == "string" then
			return API.GetPlayers(value)
		end

		return API.Get()
	end
})

API.Start()

return API
