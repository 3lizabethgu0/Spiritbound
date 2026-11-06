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
local Economy = require(script.Parent.Economy)
local Stations = require(script.Parent.Stations)

export type GuestState = "Arriving" | "Waiting" | "Served" | "Angry" | "Gone"

export type Callbacks = {
	onServed: (guest: any, player: Player) -> (),
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
	local ok = pcall(function()
		path:ComputeAsync(root.Position, target)
	end)
	local waypoints: { PathWaypoint }
	if ok and path.Status == Enum.PathStatus.Success then
		waypoints = path:GetWaypoints()
	else
		-- No path (e.g. a wall with no door): walk straight and hope. Logged so the map can be fixed.
		warn(("[Guest] %s found no path to %s, walking straight"):format(self.name, tostring(target)))
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

	-- 2. Wait. Patience starts now and keeps ticking while walking to a station.
	local patience = Config.scaled(Config.GUEST_PATIENCE_SECONDS)
	self.deadline = os.clock() + patience
	if self.dismissed then
		self.state = "Angry"
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
