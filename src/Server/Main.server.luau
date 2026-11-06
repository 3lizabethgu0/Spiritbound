--!strict
-- Server entry point. Everything that affects the run (coins, tokens, seal)
-- is decided here. Never trust values sent by a client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

print(
	("[Spiritbound] Server ready. Night %ds, dawn %ds, seal %d/%d stars."):format(
		Config.NIGHT_LENGTH_SECONDS,
		Config.DAWN_LENGTH_SECONDS,
		Config.SEAL_START_STARS,
		Config.SEAL_MAX_STARS
	)
)

-- TODO night loop, seal, economy, deals
