--!strict
-- Doors move a character to another spot in the same place (the bathhouse
-- exterior is set dressing; the real interior lives elsewhere on the map).
--
-- Tag a part "Door" and give it a string attribute Target, e.g. "Inside".
-- Tag a part "DoorTarget" and give it a string attribute Id with that name.
-- The door should be a non-colliding trigger volume in the doorway. Players
-- go through by touching it; guests go through by code (Doors.use), so a
-- guest walking into a door is never teleported twice.
--
-- This is a position change, not TeleportService. Nothing resets.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

export type Door = {
	part: BasePart,
	targetId: string,
}

local Doors = {}

local COOLDOWN_SECONDS = 2 -- stops a character bouncing between two facing doors

local doors: { Door } = {}
local targets: { [string]: BasePart } = {}
local lastUse: { [Model]: number } = {}

-- Move a character model to the door's target pad, facing the pad's front.
function Doors.use(door: Door, model: Model): boolean
	local pad = targets[door.targetId]
	if not pad then
		warn(("[Doors] %s targets '%s' but no DoorTarget has that Id"):format(door.part:GetFullName(), door.targetId))
		return false
	end
	local now = os.clock()
	local last = lastUse[model]
	if last and now - last < COOLDOWN_SECONDS then
		return false
	end
	if not last then
		model.Destroying:Once(function()
			lastUse[model] = nil
		end)
	end
	lastUse[model] = now
	model:PivotTo(pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + 3, 0))
	return true
end

-- Nearest door to a position, or nil if none is within maxDistance.
function Doors.nearest(position: Vector3, maxDistance: number): Door?
	local best: Door? = nil
	local bestDistance = maxDistance
	for _, door in doors do
		local d = (door.part.Position - position).Magnitude
		if d < bestDistance then
			best, bestDistance = door, d
		end
	end
	return best
end

-- Where a door drops you, or nil if its target pad is missing.
function Doors.destination(door: Door): Vector3?
	local pad = targets[door.targetId]
	return pad and pad.Position or nil
end

-- Among doors within maxDistance, the one whose far side is closest to `goal`,
-- but only if going through actually gets closer than staying put.
function Doors.towards(position: Vector3, goal: Vector3, maxDistance: number): Door?
	local best: Door? = nil
	local bestRemaining = (goal - position).Magnitude
	for _, door in doors do
		if (door.part.Position - position).Magnitude <= maxDistance then
			local landing = Doors.destination(door)
			if landing then
				local remaining = (goal - landing).Magnitude
				if remaining < bestRemaining then
					best, bestRemaining = door, remaining
				end
			end
		end
	end
	return best
end

function Doors.count(): number
	return #doors
end

local function registerTarget(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local id = instance:GetAttribute("Id")
	if typeof(id) ~= "string" then
		warn(("[Doors] DoorTarget %s has no Id attribute"):format(instance:GetFullName()))
		return
	end
	targets[id] = instance
end

local function registerDoor(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local targetId = instance:GetAttribute("Target")
	if typeof(targetId) ~= "string" then
		warn(("[Doors] Door %s has no Target attribute"):format(instance:GetFullName()))
		return
	end
	local door: Door = { part = instance, targetId = targetId }
	table.insert(doors, door)

	instance.Touched:Connect(function(hit: BasePart)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character or not Players:GetPlayerFromCharacter(character) then
			return -- guests use doors through code
		end
		Doors.use(door, character)
	end)
	print(("[Doors] %s -> %s"):format(instance:GetFullName(), targetId))
end

function Doors.init()
	for _, part in CollectionService:GetTagged("DoorTarget") do
		registerTarget(part)
	end
	for _, part in CollectionService:GetTagged("Door") do
		registerDoor(part)
	end
	CollectionService:GetInstanceAddedSignal("DoorTarget"):Connect(registerTarget)
	CollectionService:GetInstanceAddedSignal("Door"):Connect(registerDoor)
end

return Doors
