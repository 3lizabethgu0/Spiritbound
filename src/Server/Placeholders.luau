--!strict
-- Grey-box stand-ins so the game is playable before the real models exist.
-- Runs at server start and only builds what the map does not already provide:
--   no part tagged "Station"     -> two placeholder tubs on the tatami
--   no part tagged "GuestSpawn"  -> a pad at the foot of the bridge
--   no part tagged "GuestQueue"  -> a pad just outside the front door
-- Tag the real tub / gate parts in Studio and the matching placeholder stops appearing.
-- Everything goes in Workspace.Placeholders and exists only while the game runs.
--
-- Positions are measured from the map at runtime (the Tatami floor, the door
-- Curtains, the bridge) so the map can be moved or rebuilt without touching code.

local CollectionService = game:GetService("CollectionService")

local Placeholders = {}

type Layout = {
	floorY: number,
	door: Vector3, -- doorway at floor level
	outward: Vector3, -- unit vector from inside the building out through the door
	lateral: Vector3, -- unit vector across the doorway
	tatamiCenter: Vector3,
	bridgeFoot: Vector3?, -- far end of the bridge, if there is one
}

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

	local bridgeFoot: Vector3? = nil
	local rampOut = findPart("BridgeRampOut")
	if rampOut then
		local far = rampOut.Position + outward * (math.max(rampOut.Size.X, rampOut.Size.Z) / 2 + 6)
		bridgeFoot = Vector3.new(far.X, 0.5, far.Z)
	end

	return { floorY = floorY, door = door, outward = outward, lateral = lateral, tatamiCenter = center, bridgeFoot = bridgeFoot }
end

local function pad(folder: Folder, name: string, position: Vector3, tag: string, color: Color3)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(6, 1, 6)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = 0.6
	CollectionService:AddTag(part, tag)
	part.Parent = folder
end

local function tub(folder: Folder, name: string, position: Vector3, facing: Vector3)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(6, 3, 4)
	-- lookAt sets the front (LookVector) toward `facing`; guests stand on that side
	part.CFrame = CFrame.lookAt(position, position + facing)
	part.Anchored = true
	part.Color = Color3.fromRGB(70, 150, 160)
	part.Material = Enum.Material.SmoothPlastic
	part:SetAttribute("ServiceType", "Bath")
	CollectionService:AddTag(part, "Station")
	part.Parent = folder
end

function Placeholders.ensure()
	local needStations = #CollectionService:GetTagged("Station") == 0
	local needSpawn = #CollectionService:GetTagged("GuestSpawn") == 0
	local needQueue = #CollectionService:GetTagged("GuestQueue") == 0
	if not (needStations or needSpawn or needQueue) then
		print("[Placeholders] map provides stations, spawn and queue; nothing to build")
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
			tatamiCenter = Vector3.new(0, 4, -90),
			bridgeFoot = Vector3.new(0, 0.5, -16),
		}
	end
	local L = layout :: Layout

	local folder = Instance.new("Folder")
	folder.Name = "Placeholders"
	folder.Parent = workspace

	if needStations then
		local inward = -L.outward
		local row = L.tatamiCenter + inward * 8 + Vector3.new(0, 1.5, 0)
		tub(folder, "PlaceholderTub1", row - L.lateral * 14, L.outward)
		tub(folder, "PlaceholderTub2", row + L.lateral * 14, L.outward)
	end
	if needQueue then
		pad(folder, "PlaceholderGuestQueue", L.door + L.outward * 5 + Vector3.new(0, 0.5, 0), "GuestQueue", Color3.fromRGB(255, 196, 92))
	end
	if needSpawn then
		local spawnAt = L.bridgeFoot or (L.door + L.outward * 45)
		pad(folder, "PlaceholderGuestSpawn", Vector3.new(spawnAt.X, 0.5, spawnAt.Z), "GuestSpawn", Color3.fromRGB(120, 220, 140))
	end
	print(("[Placeholders] built stand-ins: door at (%.0f, %.0f, %.0f), facing out along (%.1f, %.1f)"):format(L.door.X, L.door.Y, L.door.Z, L.outward.X, L.outward.Z))
end

return Placeholders
