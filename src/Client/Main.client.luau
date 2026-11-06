--!strict
-- Client entry point. HUD, input, and local effects live under here.
-- The client only displays state and sends requests; it never owns game state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

print(("[Spiritbound] Client ready. Expecting %d-second nights."):format(Config.NIGHT_LENGTH_SECONDS))

-- TODO HUD
