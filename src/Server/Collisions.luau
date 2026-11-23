--!strict
-- Collision groups. Guests pass through each other and through players, so a
-- head-on meeting in a doorway or on the bridge can never fling anyone into
-- the air. Everyone still collides with the map.
-- Players still collide with each other for now (OPEN: decide with CY).
--
-- Foliage: any part tagged "GuestPassThrough" (bamboo stalks, reeds, hanging
-- branches) is solid for players but not for guests, and the pathfinder ignores
-- it, so a guest never snags on a stalk or gets routed up on top of one.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local Collisions = {}

Collisions.PLAYER = "Player"
Collisions.GUEST = "Guest"
Collisions.FOLIAGE = "Foliage"

Collisions.PASS_THROUGH_TAG = "GuestPassThrough"

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

-- A tagged part, or every part under a tagged model/folder, becomes foliage.
-- Parts that already don't collide (leaves) are left alone: they never block
-- anyone and the navmesh ignores them already. Returns how many parts changed.
local function makePassThrough(instance: Instance): number
	local parts = instance:IsA("BasePart") and { instance } or {}
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	local changed = 0
	for _, part in parts do
		if not part.CanCollide then
			continue
		end
		part.CollisionGroup = Collisions.FOLIAGE
		-- PassThrough tells the navmesh to treat the part as empty space
		if not part:FindFirstChildOfClass("PathfindingModifier") then
			local modifier = Instance.new("PathfindingModifier")
			modifier.PassThrough = true
			modifier.Parent = part
		end
		changed += 1
	end
	return changed
end

function Collisions.init()
	ensureGroup(Collisions.PLAYER)
	ensureGroup(Collisions.GUEST)
	ensureGroup(Collisions.FOLIAGE)
	PhysicsService:CollisionGroupSetCollidable(Collisions.GUEST, Collisions.GUEST, false)
	PhysicsService:CollisionGroupSetCollidable(Collisions.GUEST, Collisions.PLAYER, false)
	PhysicsService:CollisionGroupSetCollidable(Collisions.GUEST, Collisions.FOLIAGE, false)

	local started = os.clock()
	local total = 0
	for _, instance in CollectionService:GetTagged(Collisions.PASS_THROUGH_TAG) do
		total += makePassThrough(instance)
	end
	print(("[Collisions] %d foliage parts set to pass through guests in %.0f ms"):format(total, (os.clock() - started) * 1000))
	CollectionService:GetInstanceAddedSignal(Collisions.PASS_THROUGH_TAG):Connect(makePassThrough)

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
