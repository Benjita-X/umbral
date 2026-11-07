-- ClientBootstrap: arranca los controladores del jugador local en orden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MovementConfig"))
local controllers = script.Parent:WaitForChild("Controllers")

local InputController = require(controllers:WaitForChild("InputController"))
local MovementController = require(controllers:WaitForChild("MovementController"))
local CombatController = require(controllers:WaitForChild("CombatController"))
local CameraController = require(controllers:WaitForChild("CameraController"))
local EnemyController = require(controllers:WaitForChild("EnemyController"))
local CombatHUD = require(controllers:WaitForChild("CombatHUD"))
local VitalsHUD = require(controllers:WaitForChild("VitalsHUD"))
local DebugHUD = require(controllers:WaitForChild("DebugHUD"))
local PositionReporter = require(controllers:WaitForChild("PositionReporter"))
local EcoController = require(controllers:WaitForChild("EcoController"))

MovementController.Start(InputController)
CombatController.Start(InputController, MovementController)
CameraController.Start(MovementController)
EnemyController.Start()
CombatHUD.Start(CombatController)
VitalsHUD.Start(CombatController)
if Config.DebugHUD then
	DebugHUD.Start(MovementController, CombatController)
end
PositionReporter.Start()
EcoController.Start(InputController, MovementController, CombatController, CameraController)
InputController.Start()

print("[UMBRAL] Cliente listo")
