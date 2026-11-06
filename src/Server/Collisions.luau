--!strict
-- Collision groups. Guests pass through each other and through players, so a
-- teleport landing on someone or a head-on meeting on the bridge can never
-- fling anyone into the air. Everyone still collides with the map.
-- Players still collide with each other for now (OPEN: decide with CY).

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local Collisions = {}

Collisions.PLAYER = "Player"
Collisions.GUEST = "Guest"

local function ensureGroup(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

-- Put every current and future part of a model in a group
function Collisions.assign(model: Model, group: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
	model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end)
end

function Collisions.init()
	ensureGroup(Collisions.PLAYER)
	ensureGroup(Collisions.GUEST)
	PhysicsService:CollisionGroupSetCollidable(Collisions.GUEST, Collisions.GUEST, false)
	PhysicsService:CollisionGroupSetCollidable(Collisions.GUEST, Collisions.PLAYER, false)

	local function watch(player: Player)
		if player.Character then
			Collisions.assign(player.Character, Collisions.PLAYER)
		end
		player.CharacterAdded:Connect(function(character)
			Collisions.assign(character, Collisions.PLAYER)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return Collisions
