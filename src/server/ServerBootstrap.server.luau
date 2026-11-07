-- ServerBootstrap: arranque del servidor.
-- Fija la gravedad compartida y arranca los servicios en orden (DamageService crea la carpeta Remotes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MovementConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MovementConfig"))
local services = script.Parent:WaitForChild("Services")
local PositionService = require(services:WaitForChild("PositionService"))
local DamageService = require(services:WaitForChild("DamageService"))
local DefenseService = require(services:WaitForChild("DefenseService"))
local ResonanceService = require(services:WaitForChild("ResonanceService"))
local DummyService = require(services:WaitForChild("DummyService"))
local SparringService = require(services:WaitForChild("SparringService"))
local GrietaService = require(services:WaitForChild("GrietaService"))
local EcoService = require(services:WaitForChild("EcoService"))

Workspace.Gravity = MovementConfig.Gravity

DamageService.Start() -- crea la carpeta Remotes
PositionService.Start() -- historial de posiciones (usa Remotes)
DefenseService.SetPositionService(PositionService)
DefenseService.Start()
ResonanceService.Start()
EcoService.Start() -- Ecos del jugador (EXPERIMENTAL)
DummyService.Start()
SparringService.Start()
GrietaService.Start() -- solo actúa si el mapa tiene la Grieta (lugar de desarrollo)

print("[UMBRAL] Servidor listo · Fase 3: defensa y Contrapaso")
