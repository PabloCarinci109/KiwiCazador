--[[
	Net.lua
	Un solo lugar para crear y obtener los RemoteEvents del juego.
	El servidor llama a Net.init() al arrancar; el cliente llama a
	Net.init() tambien (encuentra lo que ya replico el servidor).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "KiwiRemotes"

-- Remotes con direccion. Si agregas uno, anotalo aqui.
local REMOTE_NAMES = {
	-- Cliente -> Servidor
	"RequestJoin",     -- (modeId)
	"RequestLeave",    -- ()
	"RequestState",    -- ()
	"ToolAction",      -- (toolId, data)
	"VoteMap",         -- (mapId)
	-- Servidor -> Cliente
	"SessionUpdate",   -- (state)
	"SessionEnd",      -- (result)
	"Notify",          -- (text, colorTable, duration)
	"WorldEvent",      -- (kind, data)
	"TrackerPing",     -- (data)
}

local Net = {}
Net.remotes = {}

local function ensureFolder()
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	return folder
end

-- Espera la carpeta (el cliente puede llegar antes que el servidor)
local function waitFolder()
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder and not RunService:IsServer() then
		folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 15)
	end
	return folder or ensureFolder()
end

function Net.init()
	local folder = waitFolder()

	for _, name in ipairs(REMOTE_NAMES) do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		Net.remotes[name] = remote
	end

	return Net.remotes
end

function Net.get(name)
	local remote = Net.remotes[name]
	if remote then
		return remote
	end

	local folder = waitFolder()
	remote = folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	Net.remotes[name] = remote
	return remote
end

-- Envia a todos los clientes
function Net.broadcast(name, ...)
	Net.get(name):FireAllClients(...)
end

return Net
