--!strict
-- Drives a run: Night -> Dawn -> Night ... until the seal cracks (Ended),
-- then starts a fresh run after a short pause (the lobby will replace that later).
--
-- The server owns the clock. Each phase change broadcasts a RunState with
-- absolute end times; clients count down locally from those.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Seal = require(script.Parent.Seal)

type RunState = Types.RunState
type RunPhase = Types.RunPhase

local RunController = {}

local runStateRemote = ReplicatedStorage.Remotes:WaitForChild("RunState") :: RemoteEvent

local state: RunState = {
	phase = "Ended",
	night = 0,
	stars = Seal.Stars,
	maxStars = Config.SEAL_MAX_STARS,
	phaseStartedAt = 0,
	phaseEndsAt = 0,
}

-- Bumped every time a run starts so an old loop notices it has been replaced.
local runId = 0
local clockTween: Tween? = nil

local function scaled(seconds: number): number
	return seconds / math.max(Config.DEBUG_TIME_SCALE, 0.01)
end

local function broadcast()
	runStateRemote:FireAllClients(state)
end

local function setPhase(phase: RunPhase, duration: number)
	local now = workspace:GetServerTimeNow()
	state.phase = phase
	state.stars = Seal.Stars
	state.phaseStartedAt = now
	state.phaseEndsAt = now + duration
	print(("[Run] %s | night %d | stars %d/%d | %.0fs"):format(phase, state.night, state.stars, state.maxStars, duration))
	broadcast()
end

local function tweenClock(target: number, duration: number)
	if clockTween then
		clockTween:Cancel()
	end
	clockTween = TweenService:Create(
		Lighting,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ ClockTime = target }
	)
	clockTween:Play()
end

local function runLoop(id: number)
	state.night = 0
	Seal.reset()

	while id == runId do
		-- Night
		state.night += 1
		tweenClock(Config.CLOCK_NIGHT, scaled(2))
		setPhase("Night", scaled(Config.NIGHT_LENGTH_SECONDS))
		task.wait(scaled(Config.NIGHT_LENGTH_SECONDS))
		if id ~= runId then
			return
		end

		-- Night over: the seal weakens unless something stopped it (nothing does yet)
		Seal.add(-Config.SEAL_DRAIN_PER_NIGHT)

		if Seal.isCracked() then
			setPhase("Ended", scaled(Config.RUN_RESTART_SECONDS))
			task.wait(scaled(Config.RUN_RESTART_SECONDS))
			if id ~= runId then
				return
			end
			state.night = 0
			Seal.reset()
		else
			-- Dawn
			tweenClock(Config.CLOCK_DAWN, scaled(Config.DAWN_LENGTH_SECONDS))
			setPhase("Dawn", scaled(Config.DAWN_LENGTH_SECONDS))
			task.wait(scaled(Config.DAWN_LENGTH_SECONDS))
		end
	end
end

function RunController.getState(): RunState
	return state
end

function RunController.start()
	runId += 1
	task.spawn(runLoop, runId)
end

function RunController.stop()
	runId += 1
end

-- Keep the broadcast state in sync with the seal between phase changes
Seal.Changed:Connect(function(stars)
	state.stars = stars
	broadcast()
end)

-- Late joiners get the current state immediately
Players.PlayerAdded:Connect(function(player)
	runStateRemote:FireClient(player, state)
end)

return RunController
