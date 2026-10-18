--[[
	Main.server.lua  (servidor)
	Arranca el juego: construye el mapa, crea las herramientas y
	levanta el GameManager que maneja las partidas.
--]]

local GameManager = require(script.Parent.modules.GameManager)
local Shared = require(script.Parent.modules.Shared)

GameManager.init()

print("[Kiwi Cazador] v" .. require(Shared.Config).Version .. " listo para cazar")
