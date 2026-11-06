--!strict
-- One guest, written as a class (a table plus a metatable, the Luau idiom for OOP).
-- Each guest runs its own coroutine through a small state machine:
--   Arriving -> Waiting -> (Served | Angry) -> Gone
-- Served: a player held the prompt at the guest's station in time.
-- Angry:  patience ran out, or dawn came first.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Collisions = require(script.Parent.Collisions)
local Doors = require(script.Parent.Doors)
local Economy = require(script.Parent.Economy)
local Stations = require(script.Parent.Stations)

export type GuestState = "Arriving" | "Waiting" | "Served" | "Angry" | "Gone"

export type Callbacks = {
	onServed: (guest: any, player: Player) -> (),
	onAngry: (guest: any) -> (), -- left unserved: patience ran out or dawn came
	onFinished: (guest: any) -> (),
}

local Guest = {}
Guest.__index = Guest

local NAMES = { "Hanako", "Kuro", "Mizu", "Sora", "Botan", "Tsuki", "Ren", "Yuki", "Kaede", "Haru" }

local COLOR_WAITING = Color3.fromRGB(120, 220, 140)
local COLOR_ANGRY = Color3.fromRGB(255, 96, 96)
local COLOR_SERVED = Color3.fromRGB(255, 221, 120)

local function buildRig(name: string): Model
	-- A plain grey R15 rig with no appearance. Real guest models replace this later.
	local description = Instance.new("HumanoidDescription")
	local grey = Color3.fromRGB(150, 160, 175)
	description.HeadColor = grey
	description.TorsoColor = grey
	description.LeftArmColor = grey
	description.RightArmColor = grey
	description.LeftLegColor = grey
	description.RightLegColor = grey
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = name
	humanoid.WalkSpeed = Config.GUEST_WALK_SPEED
	humanoid.NameDisplayDistance = 0 -- we draw our own tag
	humanoid.HealthDisplayDistance = 0
	Collisions.assign(model, Collisions.GUEST)
	return model
end

local function buildTag(model: Model, name: string): (TextLabel, Frame)
	local head = model:FindFirstChild("Head") :: BasePart
	local gui = Instance.new("BillboardGui")
	gui.Name = "GuestTag"
	gui.Size = UDim2.new(5, 0, 1.4, 0)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.6, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(240, 236, 228)
	label.TextStrokeTransparency = 0.5
	label.Text = name
	label.Parent = gui

	local back = Instance.new("Frame")
	back.Position = UDim2.new(0.1, 0, 0.7, 0)
	back.Size = UDim2.new(0.8, 0, 0.22, 0)
	back.BackgroundColor3 = Color3.fromRGB(20, 18, 22)
	back.BorderSizePixel = 0
	back.Parent = gui

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.BackgroundColor3 = COLOR_WAITING
	bar.BorderSizePixel = 0
	bar.Parent = back

	gui.Parent = head
	return label, bar
end

function Guest.new(id: number, spawnPoint: Vector3, queuePoint: Vector3, parent: Instance, callbacks: Callbacks)
	local self = setmetatable({}, Guest)
	self.id = id
	self.name = NAMES[(id - 1) % #NAMES + 1]
	self.state = "Arriving" :: GuestState
	self.alive = true
	self.dismissed = false
	self.walking = false
	self.spawnPoint = spawnPoint
	self.queuePoint = queuePoint
	self.station = nil :: Stations.Station?
	self.servedBy = nil :: Player?
	self.deadline = 0
	self.callbacks = callbacks

	self.model = buildRig(self.name)
	self.humanoid = self.model:FindFirstChildOfClass("Humanoid") :: Humanoid
	self.root = self.model:FindFirstChild("HumanoidRootPart") :: BasePart
	self.model:PivotTo(CFrame.new(spawnPoint))
	self.model.Parent = parent
	self.label, self.bar = buildTag(self.model, self.name)

	task.spawn(function()
		self:_run()
	end)
	return self
end

-- Walk along a computed path. Returns false if interrupted or stuck.
-- `abortIf` is checked between waypoints so a walk can be cancelled by a state change.
function Guest._walkTo(self: any, target: Vector3, timeout: number, abortIf: (() -> boolean)?): boolean
	local humanoid: Humanoid = self.humanoid
	local root: BasePart = self.root

	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
	local ok = false
	for attempt = 1, 2 do
		ok = pcall(function()
			path:ComputeAsync(root.Position, target)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			break
		end
		if attempt == 1 then
			task.wait(0.5) -- the navmesh may still be settling (e.g. right after a teleport)
		end
	end
	local waypoints: { PathWaypoint }
	if ok and path.Status == Enum.PathStatus.Success then
		waypoints = path:GetWaypoints()
	else
		-- No path (e.g. a wall with no door): walk straight and hope. Logged so the map can be fixed.
		local nearestPlayer = math.huge
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				nearestPlayer = math.min(nearestPlayer, (character:GetPivot().Position - root.Position).Magnitude)
			end
		end
		warn(("[Guest] %s found no path to %s, walking straight (from %s, floor=%s, nearest player %.1f studs, status=%s)"):format(
			self.name, tostring(target), tostring(root.Position), tostring(humanoid.FloorMaterial), nearestPlayer, tostring(path.Status)))
		waypoints = {
			PathWaypoint.new(root.Position, Enum.PathWaypointAction.Walk),
			PathWaypoint.new(target, Enum.PathWaypointAction.Walk),
		}
	end

	local started = os.clock()
	for i = 2, #waypoints do -- waypoint 1 is where we already stand
		if not self.alive or (abortIf and abortIf()) then
			return false
		end
		local waypoint = waypoints[i]
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(waypoint.Position)
		local reached = humanoid.MoveToFinished:Wait()
		if not reached or os.clock() - started > timeout then
			return false
		end
	end
	return true
end

-- Walk into a door and go through it. Does nothing when `door` is nil, so a
-- map without doors (the old "walk straight in" layout) still works.
function Guest._useDoor(self: any, door: Doors.Door?)
	if not door then
		return
	end
	-- aim at the floor under the trigger: pathfinding needs a walkable target
	local floorPoint = door.part.Position - Vector3.new(0, door.part.Size.Y / 2, 0)
	self:_walkTo(floorPoint, Config.scaled(30), function()
		-- only the arrival walk gives up when dawn comes; a leaving guest must still get out
		return self.state == "Arriving" and self.dismissed
	end)
	if self.alive then
		local went = Doors.use(door, self.model)
		if not went then
			task.wait(2.2) -- door cooldown; try once more
			went = Doors.use(door, self.model)
		end
		if not went then
			warn(("[Guest] %s could not use %s"):format(self.name, door.part.Name))
			return
		end
		-- Wait until we are standing on the other side; a path computed mid-air fails.
		local humanoid: Humanoid = self.humanoid
		local landed = os.clock()
		repeat
			task.wait(0.1)
		until humanoid.FloorMaterial ~= Enum.Material.Air or os.clock() - landed > 2
		print(("[Guest] %s through door to %s, landed on %s after %.1fs at %s"):format(self.name, door.targetId, tostring(humanoid.FloorMaterial), os.clock() - landed, tostring(self.root.Position)))
		task.wait(0.2)
	end
end

function Guest._setPatience(self: any, fraction: number)
	local f = math.clamp(fraction, 0, 1)
	self.bar.Size = UDim2.new(f, 0, 1, 0)
	self.bar.BackgroundColor3 = COLOR_WAITING:Lerp(COLOR_ANGRY, 1 - f)
end

function Guest._run(self: any)
	-- 1. Arrive at the queue point (the gate)
	self:_walkTo(self.queuePoint, Config.scaled(60), function()
		return self.dismissed
	end)
	if not self.alive then
		return
	end
	if not self.dismissed then
		self:_useDoor(Doors.nearest(self.root.Position, 25)) -- the front door, if the interior is elsewhere
	end

	-- 2. Wait. Patience starts now and keeps ticking while walking to a station.
	local patience = Config.scaled(Config.GUEST_PATIENCE_SECONDS)
	self.deadline = os.clock() + patience
	if self.dismissed then
		self.state = "Angry"
		self.callbacks.onAngry(self)
	else
		self.state = "Waiting"
	end

	while self.alive and self.state == "Waiting" do
		if not self.station then
			local station = Stations.claim(self)
			if station then
				self.station = station
				-- Walk in a separate thread so this loop keeps the patience bar ticking.
				self.walking = true
				task.spawn(function()
					local arrived = self:_walkTo(station.standSpot, Config.scaled(60), function()
						return self.state ~= "Waiting"
					end)
					if arrived and self.alive and self.state == "Waiting" then
						Stations.setReady(station, self.name)
					end
					self.walking = false
				end)
			end
		end

		local remaining = self.deadline - os.clock()
		self:_setPatience(remaining / patience)
		if (self.dismissed or remaining <= 0) and self.state == "Waiting" then
			self.state = "Angry"
			print(("[Guest] %s left unserved"):format(self.name))
			self.callbacks.onAngry(self)
		end
		task.wait(0.25)
	end

	-- Let any in-progress walk notice the state change and stop before we move again
	while self.walking do
		task.wait(0.1)
	end
	if self.station then
		Stations.release(self.station)
		self.station = nil
	end
	if not self.alive then
		return
	end

	-- 3. Leave the way they came
	if self.state == "Served" then
		self.label.TextColor3 = COLOR_SERVED
		self.bar.Size = UDim2.new(1, 0, 1, 0)
		self.bar.BackgroundColor3 = COLOR_SERVED
	else
		self.label.TextColor3 = COLOR_ANGRY
		self.bar.Size = UDim2.new(0, 0, 1, 0)
	end
	-- Back out through whichever door leads toward the spawn point, if one does
	self:_useDoor(Doors.towards(self.root.Position, self.spawnPoint, 400))
	self:_walkTo(self.spawnPoint, Config.scaled(60))
	self:destroy()
end

-- Called from the station's ProximityPrompt on the server. Validates before paying.
function Guest.serve(self: any, player: Player): boolean
	if self.state ~= "Waiting" or not self.station or self.dismissed then
		return false
	end
	self.state = "Served"
	self.servedBy = player
	Economy.addCoins(player, Config.COINS_PER_SERVED_GUEST)
	print(("[Guest] %s served by %s (+%d coins)"):format(self.name, player.Name, Config.COINS_PER_SERVED_GUEST))
	self.callbacks.onServed(self, player)
	return true
end

-- Dawn came: anyone still here leaves unhappy.
function Guest.dismiss(self: any)
	self.dismissed = true
end

function Guest.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	self.state = "Gone"
	self.model:Destroy()
	self.callbacks.onFinished(self)
end

return Guest
