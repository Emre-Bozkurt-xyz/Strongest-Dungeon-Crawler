--!strict
-- SessionTypes.luau
-- Shared type definitions for the unified SkillSession system

-- Session State Machine States
export type SessionState = "IDLE" | "CASTING" | "ACTIVE" | "RECOVERY" | "COMPLETED" | "CANCELLED"

-- Legal state transitions (enforced by SessionManager)
export type LegalTransitionsMap = {
	[SessionState]: { SessionState },
}

-- Core session data structure - single source of truth for execution + combo state
export type SkillSession = {
	-- Identity
	id: string, -- Unique session ID (for client correlation)
	skillId: string, -- Which skill is being executed
	casterId: string, -- Who is casting (entityId)

	-- State Machine
	state: SessionState, -- Current state in the lifecycle
	stateEnteredAt: number, -- os.clock() when current state began

	-- Combo (optional, nil for non-combo skills)
	combo: {
		currentStep: number, -- Which step we're on (1-indexed)
		totalSteps: number, -- Total steps in the combo
		windowOpensAt: number?, -- When the next input window opens (nil = open immediately)
		windowExpiresAt: number?, -- When combo input window closes (nil = no window active)
		stepToken: number, -- Sequencing token for validation
	}?,

	-- Timing
	executionExpiresAt: number, -- Hard deadline - session WILL end by this time
	recoveryEndsAt: number?, -- When recovery period ends (if applicable)

	-- Metadata
	createdAt: number, -- When session was created
	lastActivity: number, -- Last time session state changed (for staleness detection)
	isPredicted: boolean?, -- Client-only: predicted session marker
}

-- Configuration for creating a new session
export type SessionConfig = {
	maxDuration: number?, -- Maximum lifetime of session (defaults to 10s, capped at 30s)
	combo: {
		steps: number, -- Total combo steps
		window: number?, -- Default window duration between steps
	}?,
}

-- Event payload sent from server to clients
export type SessionEventPayload = {
	sessionId: string,
	skillId: string,
	casterId: string,
	state: SessionState,
	reason: string?, -- Why this transition happened

	-- Full timing info for client reconciliation
	stateEnteredAt: number,
	executionExpiresAt: number,
	recoveryEndsAt: number?,

	-- Full combo info if applicable
	combo: {
		currentStep: number,
		totalSteps: number,
		windowOpensAt: number?,
		windowExpiresAt: number?,
	}?,

	-- Server timestamp for latency compensation
	serverTime: number,
}

-- Legal transitions table - enforced by SessionManager.transition()
local LEGAL_TRANSITIONS: LegalTransitionsMap = {
	IDLE = { "CASTING" },
	CASTING = { "ACTIVE", "CANCELLED" },
	ACTIVE = { "RECOVERY", "COMPLETED", "CANCELLED" },
	RECOVERY = { "COMPLETED", "CANCELLED" },
	COMPLETED = {}, -- Terminal state
	CANCELLED = {}, -- Terminal state
}

-- Export the transitions table
return {
	LEGAL_TRANSITIONS = LEGAL_TRANSITIONS,
}
