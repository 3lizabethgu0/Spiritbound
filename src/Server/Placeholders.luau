--!strict
-- Grey-box stand-ins so the game is playable before the real map is tagged.
-- Runs at server start and only builds what the map does not already provide:
--   no part tagged "Station"     -> three placeholder check-in spots in a row
--   no part tagged "GuestQueue"  -> a pad in front of the stations
--   no part tagged "GuestSpawn"  -> a pad some distance away for guests to walk in from
-- Tag the real parts in Studio and the matching placeholder stops appearing.
-- Everything goes in Workspace.Placeholders and exists only while the game runs.
--
-- Gameplay happens inside the real bathhouse, so there is nothing to teleport to.
-- Missing pieces are placed relative to whatever tagged parts do exist, so a
-- half-tagged map still lines up; with nothing tagged at all, a fixed layout
-- near the world origin is used.

local CollectionService = game:GetService("CollectionService")

local Placeholders = {}

local COLOR_STATION = Color3.fromRGB(70, 150, 160)
local COLOR_SPAWN = Color3.fromRGB(120, 220, 140)
local COLOR_QUEUE = Color3.fromRGB(255, 196, 92)

local STATION_COUNT = 3
local STATION_GAP = 5 -- studs between neighbouring stations
local QUEUE_DISTANCE = 8 -- from the station row to the queue pad
local SPAWN_DISTANCE = 60 -- from the queue pad to where guests appear

-- With nothing tagged, build here
local FALLBACK_ORIGIN = CFrame.new(0, 4, 0)

----------------------------------------------------------------
-- Builders
----------------------------------------------------------------

local function block(folder: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = folder
	return part
end

-- Invisible marker pad; only its position, facing and tag matter
local function pad(folder: Instance, name: string, cframe: CFrame, tag: string, color: Color3): Part
	local part = block(folder, name, cframe, Vector3.new(6, 1, 6), color)
	part.Transparency = 1
	CollectionService:AddTag(part, tag)
	return part
end

-- Visible stand-in for a check-in spot; guests stand in front of its LookVector
local function station(folder: Instance, name: string, cframe: CFrame)
	local part = block(folder, name, cframe, Vector3.new(3, 1, 1), COLOR_STATION)
	part.Transparency = 0.5
	part:SetAttribute("ServiceType", "Check-in")
	CollectionService:AddTag(part, "Station")
end

----------------------------------------------------------------
-- Entry point
----------------------------------------------------------------

-- The first tagged part of any of these kinds, used to anchor the rest
local function existingAnchor(): BasePart?
	for _, tag in { "GuestQueue", "Station", "GuestSpawn" } do
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("BasePart") then
				return instance
			end
		end
	end
	return nil
end

function Placeholders.ensure()
	local needStations = #CollectionService:GetTagged("Station") == 0
	local needQueue = #CollectionService:GetTagged("GuestQueue") == 0
	local needSpawn = #CollectionService:GetTagged("GuestSpawn") == 0
	if not (needStations or needQueue or needSpawn) then
		print("[Placeholders] map provides stations, spawn and queue; nothing to build")
		return
	end

	-- Everything is laid out along one line: stations, then the queue pad in
	-- front of them, then the spawn pad further out in the same direction.
	-- The anchor's LookVector is "towards the guests"; its position is the queue pad.
	local anchor = existingAnchor()
	local origin: CFrame
	if anchor then
		local flat = Vector3.new(anchor.CFrame.LookVector.X, 0, anchor.CFrame.LookVector.Z)
		local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
		origin = CFrame.lookAt(anchor.Position, anchor.Position + forward)
		if CollectionService:HasTag(anchor, "Station") then
			origin = origin * CFrame.new(0, 0, -QUEUE_DISTANCE) -- a station: the queue is in front of it
		elseif CollectionService:HasTag(anchor, "GuestSpawn") then
			origin = origin * CFrame.new(0, 0, -SPAWN_DISTANCE) -- a spawn: the queue is ahead of it
		end
	else
		warn("[Placeholders] nothing tagged on the map; using a fixed layout near the origin")
		origin = FALLBACK_ORIGIN
	end

	local folder = Instance.new("Folder")
	folder.Name = "Placeholders"
	folder.Parent = workspace

	if needStations then
		-- A row across the line, QUEUE_DISTANCE behind the queue pad, facing it
		local rowCenter = origin * CFrame.new(0, 0, QUEUE_DISTANCE)
		for i = 1, STATION_COUNT do
			local across = (i - (STATION_COUNT + 1) / 2) * STATION_GAP
			station(folder, ("PlaceholderCheckIn%d"):format(i), rowCenter * CFrame.new(across, 0, 0))
		end
	end
	if needQueue then
		pad(folder, "PlaceholderGuestQueue", origin, "GuestQueue", COLOR_QUEUE)
	end
	if needSpawn then
		pad(folder, "PlaceholderGuestSpawn", origin * CFrame.new(0, 0, -SPAWN_DISTANCE), "GuestSpawn", COLOR_SPAWN)
	end
	print(("[Placeholders] built stand-ins at (%.0f, %.0f, %.0f): stations=%s queue=%s spawn=%s"):format(
		origin.X, origin.Y, origin.Z, tostring(needStations), tostring(needQueue), tostring(needSpawn)))
end

return Placeholders
