--!strict
-- Server entry point. Everything that affects the run (coins, tokens, seal)
-- is decided here. Never trust values sent by a client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

-- Remotes are created here at boot so the client can WaitForChild on them.
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local function ensureRemote(name: string, className: string): Instance
	local existing = remotes:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotes
	return remote
end
ensureRemote("RunState", "RemoteEvent") -- server -> client: RunState snapshots

local RunController = require(script.Parent.RunController)

print(
	("[Spiritbound] Server ready. Night %ds, dawn %ds, seal %d/%d stars, time scale x%d."):format(
		Config.NIGHT_LENGTH_SECONDS,
		Config.DAWN_LENGTH_SECONDS,
		Config.SEAL_START_STARS,
		Config.SEAL_MAX_STARS,
		Config.DEBUG_TIME_SCALE
	)
)

-- Until the lobby exists, the run starts as soon as the first player arrives.
if #Players:GetPlayers() > 0 then
	RunController.start()
else
	Players.PlayerAdded:Once(function()
		RunController.start()
	end)
end
