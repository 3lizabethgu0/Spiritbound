--!strict
-- The seal. Server-only source of truth for the star rating.
-- Anything that hurts or heals the seal (drain, incidents, deals, repairs)
-- goes through Seal.add / Seal.set so every change fires Seal.Changed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Seal = {}

Seal.Stars = Config.SEAL_START_STARS

local changed = Instance.new("BindableEvent")
Seal.Changed = changed.Event -- fires (stars: number)

function Seal.set(value: number)
	local clamped = math.clamp(value, 0, Config.SEAL_MAX_STARS)
	if clamped == Seal.Stars then
		return
	end
	Seal.Stars = clamped
	changed:Fire(clamped)
end

function Seal.add(delta: number)
	Seal.set(Seal.Stars + delta)
end

function Seal.isCracked(): boolean
	return Seal.Stars <= Config.SEAL_CRACK_THRESHOLD
end

function Seal.reset()
	Seal.set(Config.SEAL_START_STARS)
end

return Seal
