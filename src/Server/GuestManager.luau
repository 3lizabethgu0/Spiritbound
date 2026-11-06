--!strict
-- Spawns guests through the night and keeps the served/total tally.
-- Spawn and queue points are BaseParts tagged "GuestSpawn" and "GuestQueue".

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Guest = require(script.Parent.Guest)
local Stations = require(script.Parent.Stations)

local GuestManager = {}

local changed = Instance.new("BindableEvent")
GuestManager.Changed = changed.Event -- fires (served: number, total: number)

local active: { [number]: any } = {}
local nextId = 0
local served = 0
local total = 0
local spawnGeneration = 0 -- bumped to cancel an in-progress spawn schedule

local folder = workspace:FindFirstChild("Guests") or Instance.new("Folder")
folder.Name = "Guests"
folder.Parent = workspace

local FALLBACK_SPAWN = Vector3.new(0, 3, -16)
local FALLBACK_QUEUE = Vector3.new(0, 5, -66)

local function taggedPoint(tag: string, fallback: Vector3): Vector3
	local parts = CollectionService:GetTagged(tag)
	if #parts == 0 then
		return fallback
	end
	local part = parts[math.random(#parts)] :: BasePart
	return part.Position + Vector3.new(0, part.Size.Y / 2 + 3, 0)
end

local function notify()
	changed:Fire(served, total)
end

function GuestManager.init()
	Stations.init()
end

function GuestManager.spawnGuest()
	nextId += 1
	total += 1
	local id = nextId
	local guest = Guest.new(id, taggedPoint("GuestSpawn", FALLBACK_SPAWN), taggedPoint("GuestQueue", FALLBACK_QUEUE), folder, {
		onServed = function()
			served += 1
			notify()
		end,
		onFinished = function()
			active[id] = nil
		end,
	})
	active[id] = guest
	notify()
end

-- Spread this night's guests over the first part of the night.
function GuestManager.startNight(nightLength: number, playerCount: number)
	spawnGeneration += 1
	local generation = spawnGeneration
	served, total = 0, 0
	notify()

	local count = Config.guestsForPlayerCount(playerCount)
	local window = nightLength * Config.GUEST_ARRIVAL_WINDOW
	local gap = if count > 1 then window / (count - 1) else 0
	print(("[Guests] %d guests tonight, one every %.0fs, %d station(s)"):format(count, gap, Stations.count()))

	task.spawn(function()
		for i = 1, count do
			if generation ~= spawnGeneration then
				return
			end
			GuestManager.spawnGuest()
			if i < count then
				task.wait(gap)
			end
		end
	end)
end

-- Night over: stop spawning, send everyone home, report the tally.
function GuestManager.endNight(): (number, number)
	spawnGeneration += 1
	for _, guest in active do
		guest:dismiss()
	end
	return served, total
end

function GuestManager.getStats(): (number, number)
	return served, total
end

-- Live guests by id. For debugging and tests; game code should not reach in here.
function GuestManager.getActive(): { [number]: any }
	return active
end

return GuestManager
