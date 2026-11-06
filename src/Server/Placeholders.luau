--!strict
-- Grey-box stand-ins so the game is playable before the real models exist.
-- Runs at server start and only builds what the map does not already provide:
--   no part tagged "Door"        -> a door trigger in the exterior doorway, a plain
--                                   interior room far from the map, and a door back out
--   no part tagged "Station"     -> two placeholder tubs (inside the room if we built one)
--   no part tagged "GuestSpawn"  -> a pad at the foot of the bridge
--   no part tagged "GuestQueue"  -> a pad just outside the front door
-- Tag the real parts in Studio and the matching placeholder stops appearing.
-- Everything goes in Workspace.Placeholders and exists only while the game runs.
--
-- Exterior positions are measured from the map at runtime (the Tatami floor,
-- the door Curtains, the bridge) so the map can be moved without touching code.

local CollectionService = game:GetService("CollectionService")

local Placeholders = {}

type Layout = {
	floorY: number,
	door: Vector3, -- doorway at floor level
	outward: Vector3, -- unit vector from inside the building out through the door
	lateral: Vector3, -- unit vector across the doorway
	doorWidth: number, -- opening measured from the curtains
	doorHeight: number, -- floor to the top of the curtains
	tatamiCenter: Vector3,
	bridgeFoot: Vector3?, -- far end of the bridge, if there is one
}

-- Where the placeholder interior goes: far enough that it is never seen from the map.
local ROOM_ORIGIN = Vector3.new(0, 60, 2500)
local ROOM_SIZE = Vector3.new(60, 14, 40)

local COLOR_TUB = Color3.fromRGB(70, 150, 160)
local COLOR_SPAWN = Color3.fromRGB(120, 220, 140)
local COLOR_QUEUE = Color3.fromRGB(255, 196, 92)
local COLOR_DOOR = Color3.fromRGB(170, 110, 255)
local COLOR_TARGET = Color3.fromRGB(110, 170, 255)

local function findPart(name: string): BasePart?
	for _, d in workspace:GetDescendants() do
		if d.Name == name and d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function measureMap(): Layout?
	local tatami = findPart("Tatami")
	if not tatami then
		return nil
	end
	local curtains = {}
	for _, d in workspace:GetDescendants() do
		if d.Name == "Curtain" and d:IsA("BasePart") then
			table.insert(curtains, d)
		end
	end
	if #curtains == 0 then
		return nil
	end

	local floorY = tatami.Position.Y + tatami.Size.Y / 2
	local doorSum = Vector3.zero
	for _, c in curtains do
		doorSum += c.Position
	end
	local door = doorSum / #curtains
	door = Vector3.new(door.X, floorY, door.Z)

	local center = Vector3.new(tatami.Position.X, floorY, tatami.Position.Z)
	local outward = (door - center) * Vector3.new(1, 0, 1)
	if outward.Magnitude < 1 then
		return nil
	end
	outward = outward.Unit
	local lateral = outward:Cross(Vector3.yAxis).Unit

	-- Opening size: how far the curtains spread sideways, and how high they hang
	local minAcross, maxAcross, top = math.huge, -math.huge, floorY
	for _, c in curtains do
		local across = (c.Position - door):Dot(lateral)
		local halfWidth = math.max(c.Size.X, c.Size.Z) / 2
		minAcross = math.min(minAcross, across - halfWidth)
		maxAcross = math.max(maxAcross, across + halfWidth)
		top = math.max(top, c.Position.Y + c.Size.Y / 2)
	end
	local doorWidth = math.max(4, maxAcross - minAcross)
	local doorHeight = math.max(6, top - floorY)

	local bridgeFoot: Vector3? = nil
	local rampOut = findPart("BridgeRampOut")
	if rampOut then
		local far = rampOut.Position + outward * (math.max(rampOut.Size.X, rampOut.Size.Z) / 2 + 6)
		bridgeFoot = Vector3.new(far.X, 0.5, far.Z)
	end

	return {
		floorY = floorY,
		door = door,
		outward = outward,
		lateral = lateral,
		doorWidth = doorWidth,
		doorHeight = doorHeight,
		tatamiCenter = center,
		bridgeFoot = bridgeFoot,
	}
end

----------------------------------------------------------------
-- Builders
----------------------------------------------------------------

local function block(folder: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = folder
	return part
end

-- Flat marker pad; front (LookVector) points along `facing`
local function pad(folder: Instance, name: string, position: Vector3, facing: Vector3, tag: string, color: Color3): Part
	local part = block(folder, name, CFrame.lookAt(position, position + facing), Vector3.new(6, 1, 6), color)
	part.CanCollide = false
	part.Transparency = 1 -- invisible marker; only its position and tag matter
	CollectionService:AddTag(part, tag)
	return part
end

-- Upright trigger volume filling a doorway; non-colliding so anyone can walk into it
local function doorTrigger(folder: Instance, name: string, floorPoint: Vector3, facing: Vector3, width: number, height: number, targetId: string): Part
	local center = floorPoint + Vector3.new(0, height / 2, 0)
	local part = block(folder, name, CFrame.lookAt(center, center + facing), Vector3.new(width, height, 0.5), COLOR_DOOR)
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.75
	part:SetAttribute("Target", targetId)
	CollectionService:AddTag(part, "Door")
	return part
end

local function tub(folder: Instance, name: string, position: Vector3, facing: Vector3)
	local part = block(folder, name, CFrame.lookAt(position, position + facing), Vector3.new(6, 3, 4), COLOR_TUB)
	part:SetAttribute("ServiceType", "Bath")
	CollectionService:AddTag(part, "Station")
end

-- A closed grey room with lights. Returns the floor-level point just inside its door
-- and the direction pointing into the room.
local function room(folder: Instance): (Vector3, Vector3)
	local o = ROOM_ORIGIN
	local w, h, d = ROOM_SIZE.X, ROOM_SIZE.Y, ROOM_SIZE.Z
	local wallColor = Color3.fromRGB(90, 88, 96)
	block(folder, "RoomFloor", CFrame.new(o), Vector3.new(w, 1, d), Color3.fromRGB(120, 118, 110))
	block(folder, "RoomCeiling", CFrame.new(o + Vector3.new(0, h, 0)), Vector3.new(w, 1, d), wallColor)
	block(folder, "RoomWallBack", CFrame.new(o + Vector3.new(0, h / 2, -d / 2)), Vector3.new(w, h, 1), wallColor)
	block(folder, "RoomWallLeft", CFrame.new(o + Vector3.new(-w / 2, h / 2, 0)), Vector3.new(1, h, d), wallColor)
	block(folder, "RoomWallRight", CFrame.new(o + Vector3.new(w / 2, h / 2, 0)), Vector3.new(1, h, d), wallColor)
	-- front wall with a doorway gap in the middle
	local gap = 8
	local side = (w - gap) / 2
	block(folder, "RoomWallFrontL", CFrame.new(o + Vector3.new(-(gap / 2 + side / 2), h / 2, d / 2)), Vector3.new(side, h, 1), wallColor)
	block(folder, "RoomWallFrontR", CFrame.new(o + Vector3.new(gap / 2 + side / 2, h / 2, d / 2)), Vector3.new(side, h, 1), wallColor)
	block(folder, "RoomWallFrontTop", CFrame.new(o + Vector3.new(0, h - 2, d / 2)), Vector3.new(gap, 4, 1), wallColor)
	for _, offset in { Vector3.new(-18, h - 2, -10), Vector3.new(18, h - 2, -10), Vector3.new(-18, h - 2, 10), Vector3.new(18, h - 2, 10) } do
		local lamp = block(folder, "RoomLamp", CFrame.new(o + offset), Vector3.new(2, 1, 2), Color3.fromRGB(255, 230, 180))
		lamp.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Range = 40
		light.Brightness = 1.5
		light.Parent = lamp
	end
	local floorTop = o.Y + 0.5
	local doorway = Vector3.new(o.X, floorTop, o.Z + d / 2)
	return doorway, Vector3.new(0, 0, -1)
end

----------------------------------------------------------------
-- Entry point
----------------------------------------------------------------

function Placeholders.ensure()
	local needDoors = #CollectionService:GetTagged("Door") == 0
	local needStations = #CollectionService:GetTagged("Station") == 0
	local needSpawn = #CollectionService:GetTagged("GuestSpawn") == 0
	local needQueue = #CollectionService:GetTagged("GuestQueue") == 0
	if not (needDoors or needStations or needSpawn or needQueue) then
		print("[Placeholders] map provides doors, stations, spawn and queue; nothing to build")
		return
	end

	local layout = measureMap()
	if not layout then
		warn("[Placeholders] could not find Tatami + Curtain parts; using fixed positions")
		layout = {
			floorY = 4,
			door = Vector3.new(0, 4, -70),
			outward = Vector3.new(0, 0, 1),
			lateral = Vector3.new(1, 0, 0),
			doorWidth = 9,
			doorHeight = 10,
			tatamiCenter = Vector3.new(0, 4, -90),
			bridgeFoot = Vector3.new(0, 0.5, -16),
		}
	end
	local L = layout :: Layout

	local folder = Instance.new("Folder")
	folder.Name = "Placeholders"
	folder.Parent = workspace

	-- Where tubs go: the placeholder room if we build one, else the tatami
	local tubRow = L.tatamiCenter - L.outward * 8 + Vector3.new(0, 1.5, 0)
	local tubLateral = L.lateral
	local tubFacing = L.outward

	if needDoors then
		local roomDoorway, intoRoom = room(folder)
		local outOfRoom = -intoRoom
		-- exterior doorway -> inside; land 6 studs into the room, facing in
		doorTrigger(folder, "PlaceholderDoorIn", L.door, L.outward, L.doorWidth, L.doorHeight, "Inside")
		pad(folder, "PlaceholderTargetInside", roomDoorway + intoRoom * 6, intoRoom, "DoorTarget", COLOR_TARGET):SetAttribute("Id", "Inside")
		-- room doorway -> outside; land 6 studs out the front door, facing away from the building
		doorTrigger(folder, "PlaceholderDoorOut", roomDoorway, outOfRoom, 8, ROOM_SIZE.Y - 4, "Outside")
		-- offset sideways so exiting characters never land on guests waiting at the queue pad
		pad(folder, "PlaceholderTargetOutside", L.door + L.outward * 6 + L.lateral * 4, L.outward, "DoorTarget", COLOR_TARGET):SetAttribute("Id", "Outside")

		tubRow = ROOM_ORIGIN + Vector3.new(0, 0.5 + 1.5, -6)
		tubLateral = Vector3.new(1, 0, 0)
		tubFacing = Vector3.new(0, 0, 1) -- face the room's door
	end
	if needStations then
		tub(folder, "PlaceholderTub1", tubRow - tubLateral * 14, tubFacing)
		tub(folder, "PlaceholderTub2", tubRow + tubLateral * 14, tubFacing)
	end
	if needQueue then
		pad(folder, "PlaceholderGuestQueue", L.door + L.outward * 5 - L.lateral * 3 + Vector3.new(0, 0.5, 0), L.outward, "GuestQueue", COLOR_QUEUE)
	end
	if needSpawn then
		local spawnAt = L.bridgeFoot or (L.door + L.outward * 45)
		pad(folder, "PlaceholderGuestSpawn", Vector3.new(spawnAt.X, 0.5, spawnAt.Z), L.outward, "GuestSpawn", COLOR_SPAWN)
	end
	print(("[Placeholders] built stand-ins: door at (%.0f, %.0f, %.0f), room=%s"):format(L.door.X, L.door.Y, L.door.Z, tostring(needDoors)))
end

return Placeholders
