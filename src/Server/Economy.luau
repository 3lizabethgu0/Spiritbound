--!strict
-- Spirit Coins: per-run currency. Lives on the server in each player's
-- leaderstats folder, which Roblox replicates to every client automatically
-- (and shows in the player list). Clients can read it, never write it.

local Players = game:GetService("Players")

local Economy = {}

local function coinsValue(player: Player): IntValue
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local coins = stats:FindFirstChild("Coins")
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Value = 0
		coins.Parent = stats
	end
	return coins :: IntValue
end

function Economy.getCoins(player: Player): number
	return coinsValue(player).Value
end

function Economy.addCoins(player: Player, amount: number)
	local coins = coinsValue(player)
	coins.Value = math.max(0, coins.Value + amount)
end

-- Spirit Coins reset when the run ends (decided in the design doc).
function Economy.resetRun()
	for _, player in Players:GetPlayers() do
		coinsValue(player).Value = 0
	end
end

Players.PlayerAdded:Connect(function(player)
	coinsValue(player)
end)
for _, player in Players:GetPlayers() do
	coinsValue(player)
end

return Economy
