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
local WeaponService = require(services:WaitForChild("WeaponService"))
local RecoveryService = require(services:WaitForChild("RecoveryService"))
local PersonajeService = require(services:WaitForChild("PersonajeService"))
local BalanceService = require(services:WaitForChild("BalanceService"))
local ExpedicionService = require(services:WaitForChild("ExpedicionService"))
local PerfilService = require(services:WaitForChild("PerfilService"))

Workspace.Gravity = MovementConfig.Gravity

DamageService.Start() -- crea la carpeta Remotes
PositionService.Start() -- historial de posiciones (usa Remotes)
DefenseService.SetPositionService(PositionService)
DefenseService.Start()
ResonanceService.Start()
EcoService.Start() -- Ecos del jugador (EXPERIMENTAL)
WeaponService.Start() -- armas: Puños y Espada (EXPERIMENTAL)
RecoveryService.Start() -- recuperación de vida: Respiro fuera de combate y punto seguro (EXPERIMENTAL)
PersonajeService.Start() -- red de seguridad (nadie muere por caer al vacío) y respaldo de la apariencia
DummyService.Start()
SparringService.Start()
PerfilService.Start() -- progreso permanente mínimo: NivelGlobal y ExpedicionesCompletadas (DataStore)
GrietaService.Start() -- solo actúa si el mapa tiene la Grieta (lugar de desarrollo)
BalanceService.Start() -- poder, defensa, experiencia y niveles (una sola fórmula con límites)
ExpedicionService.Start() -- la Grieta como partida completa: encuentros, mejoras, Guardián (y el encuentro de prueba)

print("[UMBRAL] Servidor listo")
