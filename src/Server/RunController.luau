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
local Economy = require(script.Parent.Economy)
local GuestManager = require(script.Parent.GuestManager)
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
	guestsServed = 0,
	guestsTotal = 0,
}

-- Bumped every time a run starts so an old loop notices it has been replaced.
local runId = 0
local clockTween: Tween? = nil

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

-- The seal rule (every number is OPEN in the design doc):
--   nobody came      -> holds
--   everyone served  -> heals SEAL_PERFECT_NIGHT_BONUS
--   enough served    -> holds
--   otherwise        -> drains SEAL_DRAIN_PER_NIGHT
local function applyNightResult(served: number, total: number): string
	if total == 0 then
		return "quiet"
	elseif served >= total then
		Seal.add(Config.SEAL_PERFECT_NIGHT_BONUS)
		return "perfect"
	elseif served / total >= Config.SEAL_HOLD_RATIO then
		return "held"
	else
		Seal.add(-Config.SEAL_DRAIN_PER_NIGHT)
		return "bad"
	end
end

local function runLoop(id: number)
	state.night = 0
	Seal.reset()

	while id == runId do
		-- Night
		state.night += 1
		state.guestsServed, state.guestsTotal = 0, 0
		local nightLength = Config.scaled(Config.NIGHT_LENGTH_SECONDS)
		tweenClock(Config.CLOCK_NIGHT, Config.scaled(2))
		setPhase("Night", nightLength)
		GuestManager.startNight(nightLength, #Players:GetPlayers())
		task.wait(nightLength)
		if id ~= runId then
			return
		end

		-- Night over: tally the guests and judge the seal
		local served, total = GuestManager.endNight()
		local verdict = applyNightResult(served, total)
		print(("[Run] night %d: %d/%d guests served, %s night, stars now %d"):format(state.night, served, total, verdict, Seal.Stars))

		if Seal.isCracked() then
			Economy.resetRun()
			local pause = Config.scaled(Config.RUN_RESTART_SECONDS)
			setPhase("Ended", pause)
			task.wait(pause)
			if id ~= runId then
				return
			end
			state.night = 0
			Seal.reset()
		else
			-- Dawn
			local dawnLength = Config.scaled(Config.DAWN_LENGTH_SECONDS)
			tweenClock(Config.CLOCK_DAWN, dawnLength)
			setPhase("Dawn", dawnLength)
			task.wait(dawnLength)
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

-- Keep the broadcast state in sync between phase changes
Seal.Changed:Connect(function(stars)
	state.stars = stars
	broadcast()
end)

GuestManager.Changed:Connect(function(served, total)
	state.guestsServed = served
	state.guestsTotal = total
	broadcast()
end)

-- Late joiners get the current state immediately
Players.PlayerAdded:Connect(function(player)
	runStateRemote:FireClient(player, state)
end)

return RunController
