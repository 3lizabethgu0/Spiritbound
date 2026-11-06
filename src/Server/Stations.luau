--!strict
-- Stations are any BasePart tagged "Station" (CollectionService). The code never
-- references a specific tub model, so CY can tag the real one later and this
-- keeps working. Optional attributes on the part:
--   ServiceType    (string)  shown on the prompt, default "Bath"
--   ServiceSeconds (number)  how long "Hold E" takes, default Config.STATION_SERVICE_SECONDS
--
-- A ProximityPrompt's Triggered event fires on the server with the player who
-- held it, and Roblox already checks distance. That makes it a safe client ->
-- server request without writing our own RemoteEvent.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Station = {
	part: BasePart,
	prompt: ProximityPrompt,
	serviceType: string,
	standSpot: Vector3, -- where the guest waits, just in front of the part
	occupant: any?, -- the Guest using it (typed any to avoid a require cycle)
}

local Stations = {}

local list: { Station } = {}
local byPart: { [BasePart]: Station } = {}

local function register(instance: Instance)
	if not instance:IsA("BasePart") or byPart[instance] then
		return
	end
	local part = instance :: BasePart

	local prompt = part:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	local serviceType = (part:GetAttribute("ServiceType") :: string?) or "Bath"
	prompt.ActionText = "Serve"
	prompt.ObjectText = serviceType
	prompt.HoldDuration = (part:GetAttribute("ServiceSeconds") :: number?) or Config.STATION_SERVICE_SECONDS
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false -- only on while a guest is waiting here
	prompt.Parent = part

	local station: Station = {
		part = part,
		prompt = prompt,
		serviceType = serviceType,
		-- LookVector is the part's front. Stand 2.5 studs past the front face, at floor level.
		standSpot = part.Position + part.CFrame.LookVector * (part.Size.Z / 2 + 2.5) - Vector3.new(0, part.Size.Y / 2, 0),
		occupant = nil,
	}

	prompt.Triggered:Connect(function(player: Player)
		local guest = station.occupant
		if guest then
			guest:serve(player)
		end
	end)

	byPart[part] = station
	table.insert(list, station)
	print(("[Stations] registered %s (%s)"):format(part:GetFullName(), serviceType))
end

function Stations.init()
	for _, part in CollectionService:GetTagged("Station") do
		register(part)
	end
	CollectionService:GetInstanceAddedSignal("Station"):Connect(register)
end

function Stations.count(): number
	return #list
end

-- Reserve a free station for a guest. Returns nil if all are taken.
function Stations.claim(guest: any): Station?
	for _, station in list do
		if station.occupant == nil then
			station.occupant = guest
			return station
		end
	end
	return nil
end

-- The guest has reached the stand spot: light up the prompt.
function Stations.setReady(station: Station, guestName: string)
	station.prompt.ObjectText = ("%s - %s"):format(guestName, station.serviceType)
	station.prompt.Enabled = true
end

function Stations.release(station: Station)
	station.occupant = nil
	station.prompt.Enabled = false
	station.prompt.ObjectText = station.serviceType
end

return Stations
