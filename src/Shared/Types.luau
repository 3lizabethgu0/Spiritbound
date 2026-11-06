--!strict
-- Shared type definitions. Both server and client import these.

export type RunPhase = "Night" | "Dawn" | "Ended"

-- Snapshot of the run that the server broadcasts to every client.
-- Timers are absolute server times (workspace:GetServerTimeNow()), so the
-- client computes "time left" itself and the server never has to tick.
export type RunState = {
	phase: RunPhase,
	night: number,        -- 1-based; the night in progress, or the night just finished when Ended
	stars: number,        -- current seal stars
	maxStars: number,
	phaseStartedAt: number,
	phaseEndsAt: number,
}

return nil
