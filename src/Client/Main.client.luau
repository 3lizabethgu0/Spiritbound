--!strict
-- Client entry point. HUD, input, and local effects live under here.
-- The client only displays state and sends requests; it never owns game state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HUD = require(script.Parent.HUD)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local runStateRemote = remotes:WaitForChild("RunState") :: RemoteEvent

runStateRemote.OnClientEvent:Connect(function(state)
	HUD.setState(state)
end)

print("[Spiritbound] Client ready.")
