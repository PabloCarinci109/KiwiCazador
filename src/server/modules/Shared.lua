--[[
	Shared.lua  (servidor)
	Devuelve la carpeta ReplicatedStorage.KiwiShared con un error claro
	si el juego no se instalo como corresponde.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:FindFirstChild("KiwiShared")
if not folder then
	folder = ReplicatedStorage:WaitForChild("KiwiShared", 20)
end

if not folder then
	error(
		"[Kiwi Cazador] Falta la carpeta ReplicatedStorage.KiwiShared. "
		.. "Crea una Folder con ese nombre dentro de ReplicatedStorage y "
		.. "mete ahi Config, Util y Net (mira el README).",
		0
	)
end

return folder
