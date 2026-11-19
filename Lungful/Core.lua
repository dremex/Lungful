local ADDON, ns = ...

local SETTINGS_VERSION = 2
local PALE_YELLOW = { 1, 0.93, 0.58 }
local YELLOW = { 1, 0.82, 0 }
local ORANGE = { 1, 0.45, 0 }
local RED = { 1, 0.08, 0.05 }
local YELLOW_LEAD_PERCENT = 40
local ORANGE_LEAD_PERCENT = 20
local RED_LEAD_PERCENT = 10
local SHIFT_STEP = 0.4
local FLASH_LAG_PERCENT = 5
local WHOLE_BAR_PERCENT = 10
local SLOWEST_PULSES_PER_SECOND, FASTEST_PULSES_PER_SECOND = 1, 3
local WHOLE_BAR_PULSES_PER_SECOND = 4
local DIMMEST_PULSE_BRIGHTNESS = 0.35
local FULL_BAR_EXAMPLE_MS = 60000
local loadedCallbacks = {}

ns.MODES = { percent = true, trip = true }

ns.LIMITS = {
	turnBackPercent = { min = 5, max = 95 },
	marginSeconds = { min = 0, max = 30 },
}

ns.STAGE_PERCENTS = {
	yellowLead = YELLOW_LEAD_PERCENT,
	orangeLead = ORANGE_LEAD_PERCENT,
	flashLag = FLASH_LAG_PERCENT,
	wholeBar = WHOLE_BAR_PERCENT,
}

ns.defaults = {
	mode = "percent",
	turnBackPercent = 30,
	marginSeconds = 5,
	flash = true,
	fatigue = true,
}

local function Clamp(value, low, high)
	return math.min(high, math.max(low, value))
end

local function Lerp(from, to, progress)
	return from + (to - from) * progress
end

local function Blend(fromColor, toColor, progress)
	return Lerp(fromColor[1], toColor[1], progress),
		Lerp(fromColor[2], toColor[2], progress),
		Lerp(fromColor[3], toColor[3], progress)
end

local function Shifted(progress)
	return SHIFT_STEP + (1 - SHIFT_STEP) * Clamp(progress, 0, 1)
end

local function ColorAbove(turnBackLeadPercent)
	if turnBackLeadPercent >= ORANGE_LEAD_PERCENT then
		local deepening = (YELLOW_LEAD_PERCENT - turnBackLeadPercent) / (YELLOW_LEAD_PERCENT - ORANGE_LEAD_PERCENT)

		return Blend(PALE_YELLOW, YELLOW, Clamp(deepening, 0, 1))
	end

	if turnBackLeadPercent >= RED_LEAD_PERCENT then
		local towardOrange = (ORANGE_LEAD_PERCENT - turnBackLeadPercent) / (ORANGE_LEAD_PERCENT - RED_LEAD_PERCENT)

		return Blend(YELLOW, ORANGE, Shifted(towardOrange))
	end

	return Blend(ORANGE, RED, Shifted((RED_LEAD_PERCENT - turnBackLeadPercent) / RED_LEAD_PERCENT))
end

function ns.ClampSetting(key, value)
	local limits = ns.LIMITS[key]

	return Clamp(math.floor(value + 0.5), limits.min, limits.max)
end

function ns.LoadSettings(saved)
	local settings = type(saved) == "table" and saved or {}

	if type(settings.version) ~= "number" or settings.version < SETTINGS_VERSION then
		settings.mode = nil
	end

	settings.version = SETTINGS_VERSION

	for key, value in pairs(ns.defaults) do
		if type(settings[key]) ~= type(value) then
			settings[key] = value
		end
	end

	if not ns.MODES[settings.mode] then
		settings.mode = ns.defaults.mode
	end

	for key in pairs(ns.LIMITS) do
		settings[key] = ns.ClampSetting(key, settings[key])
	end

	return settings
end

ns.db = ns.LoadSettings(nil)

function ns.OnSettingsLoaded(callback)
	table.insert(loadedCallbacks, callback)
end

local loader = CreateFrame("Frame")

loader:RegisterEvent("ADDON_LOADED")

loader:SetScript("OnEvent", function(_, _, addonName)
	if addonName ~= ADDON then
		return
	end

	LungfulDB = ns.LoadSettings(LungfulDB)

	ns.db = LungfulDB

	for _, callback in ipairs(loadedCallbacks) do
		callback()
	end
end)

function ns.IsRecorded(timerName)
	return timerName == "BREATH" or timerName == "EXHAUSTION"
end

function ns.IsColored(timerName)
	return timerName == "BREATH" or (timerName == "EXHAUSTION" and ns.db.fatigue)
end

function ns.TurnBackMs(dive, settings)
	if settings.mode == "percent" then
		return dive.maxMs * settings.turnBackPercent / 100
	end

	return math.min(dive.startMs, (dive.startMs + settings.marginSeconds * 1000) / 2)
end

function ns.Look(leftMs, turnBackMs, maxMs, flash)
	local percentMs = maxMs / 100
	local flashFromMs = turnBackMs - FLASH_LAG_PERCENT * percentMs
	local wholeBarFromMs = math.max(0, math.min(WHOLE_BAR_PERCENT * percentMs, flashFromMs))

	if leftMs <= wholeBarFromMs then
		return RED[1], RED[2], RED[3], flash and WHOLE_BAR_PULSES_PER_SECOND or 0, true
	end

	if leftMs <= flashFromMs then
		local closeness = (flashFromMs - leftMs) / (flashFromMs - wholeBarFromMs)
		local pulsesPerSecond = Lerp(SLOWEST_PULSES_PER_SECOND, FASTEST_PULSES_PER_SECOND, closeness)

		return RED[1], RED[2], RED[3], flash and pulsesPerSecond or 0, false
	end

	local turnBackLeadPercent = (leftMs - turnBackMs) / percentMs

	if turnBackLeadPercent >= YELLOW_LEAD_PERCENT then
		return nil
	end

	local red, green, blue = ColorAbove(turnBackLeadPercent)

	return red, green, blue, 0, false
end

function ns.PulseWave(pulsePhase)
	return 0.5 + 0.5 * math.cos(2 * math.pi * pulsePhase)
end

function ns.PulseBrightness(pulsePhase)
	return Lerp(DIMMEST_PULSE_BRIGHTNESS, 1, ns.PulseWave(pulsePhase))
end

function ns.Describe(settings)
	if settings.mode == "percent" then
		local redPercent = settings.turnBackPercent
		local flashPercent = math.max(0, redPercent - FLASH_LAG_PERCENT)

		return ("Faint yellow from %d%%, full yellow by %d%%, orange by %d%%, red by %d%%, flashing from %d%%, the whole bar flashing from %d%% of breath left."):format(
			math.min(100, redPercent + YELLOW_LEAD_PERCENT),
			math.min(100, redPercent + ORANGE_LEAD_PERCENT),
			math.min(100, redPercent + RED_LEAD_PERCENT),
			redPercent,
			flashPercent,
			math.min(WHOLE_BAR_PERCENT, flashPercent)
		)
	end

	local fullDive = { startMs = FULL_BAR_EXAMPLE_MS, maxMs = FULL_BAR_EXAMPLE_MS }

	return ("Red when swimming back the way you came would reach air with %ds to spare (%ds left on a full %ds bar). Faint yellow, then orange before that, flashing just after, the whole bar flashing from %d%%."):format(
		settings.marginSeconds,
		math.floor(ns.TurnBackMs(fullDive, settings) / 1000),
		FULL_BAR_EXAMPLE_MS / 1000,
		WHOLE_BAR_PERCENT
	)
end

function ns.Print(text)
	print("|cff66ccffLungful|r: " .. text)
end
