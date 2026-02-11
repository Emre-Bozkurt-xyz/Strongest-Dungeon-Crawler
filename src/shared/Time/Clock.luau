--!strict
-- Clock: central time helpers for consistent timestamps.

local Clock = {}

local function localNow(): number
	return os.clock()
end

local serverNowProvider: () -> number = localNow

function Clock.localNow(): number
	return localNow()
end

function Clock.serverNow(): number
	return serverNowProvider()
end

function Clock.setServerNowProvider(provider: () -> number)
	serverNowProvider = provider
end

function Clock.resetServerNowProvider()
	serverNowProvider = localNow
end

return Clock
