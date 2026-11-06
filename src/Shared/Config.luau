--!strict
-- Spiritbound tunables. Shared by server and client.
--
-- Status tags mirror the design doc:
--   DECIDED  = agreed, build against it
--   PROPOSED = needs a yes/no, change freely
--   OPEN     = placeholder so code runs; the real answer is still unknown

local Config = {}

----------------------------------------------------------------
-- Run structure
----------------------------------------------------------------
Config.NIGHT_LENGTH_SECONDS = 240          -- DECIDED  ~4 minutes per night
Config.DAWN_LENGTH_SECONDS = 30            -- DECIDED  ~30 seconds of dawn
Config.LEGENDARY_NIGHT = 100               -- DECIDED  the 100-night goal
Config.TUTORIAL_NIGHT_ENABLED = true       -- PROPOSED "Night 0" teaches serving, seal, dawn
Config.RUN_RESTART_SECONDS = 10            -- OPEN     pause after the seal cracks before a new run (until the lobby exists)

-- Testing only. 1 = real time. 10 = nights are 24 s, dawn 3 s. Keep at 1 when you commit.
Config.DEBUG_TIME_SCALE = 1

----------------------------------------------------------------
-- Lighting (grey-box feel, art pass later)
----------------------------------------------------------------
Config.CLOCK_NIGHT = 0                     -- OPEN     Lighting.ClockTime during a night (midnight)
Config.CLOCK_DAWN = 7                      -- OPEN     where the sun ends up by the end of dawn

----------------------------------------------------------------
-- Seal
----------------------------------------------------------------
Config.SEAL_MAX_STARS = 5                  -- OPEN     star count not set in the doc
Config.SEAL_START_STARS = 5                -- OPEN
Config.SEAL_DRAIN_PER_NIGHT = 1            -- OPEN     stars lost per night if nothing is done
Config.SEAL_CRACK_THRESHOLD = 0            -- DECIDED  run ends when stars reach this

----------------------------------------------------------------
-- Players & servers
----------------------------------------------------------------
Config.MIN_PLAYERS = 1                     -- DECIDED  1–5 players per match server
Config.MAX_PLAYERS = 5                     -- DECIDED
Config.AFK_KICK_SECONDS = 300              -- OPEN     doc asks "kick after a few minutes idle?"

-- Guest scaling, PROPOSED formula: guests = base * (0.5 + 0.25 * players)
Config.GUESTS_BASE_PER_NIGHT = 4           -- OPEN
Config.GUEST_SCALE_OFFSET = 0.5            -- PROPOSED
Config.GUEST_SCALE_PER_PLAYER = 0.25       -- PROPOSED

function Config.guestsForPlayerCount(playerCount: number): number
	local scaled = Config.GUESTS_BASE_PER_NIGHT
		* (Config.GUEST_SCALE_OFFSET + Config.GUEST_SCALE_PER_PLAYER * playerCount)
	return math.max(1, math.floor(scaled + 0.5))
end

----------------------------------------------------------------
-- Economy
----------------------------------------------------------------
-- Spirit Coins: per run, reset when the run ends.      DECIDED
-- Soul Tokens:  permanent, banked every dawn.          DECIDED
-- Coins never become tokens; coins can't buy classes.  DECIDED
Config.COINS_PER_SERVED_GUEST = 10         -- OPEN     "prices and how fast coins come in"
Config.TOKENS_PER_DAWN = 5                 -- OPEN
Config.DEAL_REWARD_PAYOUT_DAWNS = 3        -- PROPOSED pay deal rewards over several dawns

----------------------------------------------------------------
-- Interaction
----------------------------------------------------------------
Config.STATION_HOLD_SECONDS = 1.0          -- PROPOSED "Hold E" ProximityPrompt at every station
Config.CARRY_SLOTS_DEFAULT = 1             -- PROPOSED one item at a time
Config.CARRY_SLOTS_RUNNER = 2              -- PROPOSED Runner class carries two

return Config
