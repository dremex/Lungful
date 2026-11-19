local _, ns = ...

local OVERLAY_ATLAS = "ui-castingbar-filling-standard"
local MIRROR_TIMER_COUNT = 3
local STEADY_WHOLE_BAR_ALPHA = 0.5

local function ReadOverlayAtlasInfo()
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(OVERLAY_ATLAS)

	if info and (info.file or info.filename) then
		return info
	end
end

local overlayAtlasInfo = ReadOverlayAtlasInfo()
local dives = {}
local overlays = {}
local paintedThisFrame = {}
local driver = CreateFrame("Frame")

driver:Hide()

local function IsPaused(paused)
	return paused == true or (type(paused) == "number" and paused ~= 0)
end

local function BlizzardBar(timerName)
	local container = MirrorTimerContainer
	local timerFrame = container and container.GetActiveTimer and container:GetActiveTimer(timerName)

	return timerFrame and timerFrame.StatusBar
end

local function NewOverlayTexture(statusBar, subLevel)
	local texture = statusBar:CreateTexture(nil, "OVERLAY", nil, subLevel)

	if overlayAtlasInfo then
		texture:SetTexture(overlayAtlasInfo.file or overlayAtlasInfo.filename)

		texture:SetDesaturated(true)
	else
		texture:SetColorTexture(1, 1, 1)
	end

	texture:Hide()

	return texture
end

local function CropToAtlas(texture, shownFraction)
	if not overlayAtlasInfo then
		return
	end

	local info = overlayAtlasInfo
	local rightTexCoord = info.leftTexCoord + (info.rightTexCoord - info.leftTexCoord) * shownFraction

	texture:SetTexCoord(info.leftTexCoord, rightTexCoord, info.topTexCoord, info.bottomTexCoord)
end

local function OverlayFor(statusBar)
	if overlays[statusBar] then
		return overlays[statusBar]
	end

	local fill = NewOverlayTexture(statusBar, 0)
	local wholeBar = NewOverlayTexture(statusBar, 1)
	local overlay = { fill = fill, wholeBar = wholeBar, pulsePhase = 0 }

	wholeBar:SetAllPoints(statusBar)

	CropToAtlas(wholeBar, 1)

	overlays[statusBar] = overlay

	return overlay
end

local function FillFraction(statusBar)
	local minValue, maxValue = statusBar:GetMinMaxValues()

	if not (minValue and maxValue) or maxValue <= minValue then
		return 0
	end

	return math.min(1, math.max(0, (statusBar:GetValue() - minValue) / (maxValue - minValue)))
end

local function PlaceFill(overlay, statusBar)
	local fillTexture = statusBar:GetStatusBarTexture()

	if overlay.fillAnchor ~= fillTexture then
		overlay.fillAnchor = fillTexture

		overlay.fill:ClearAllPoints()

		overlay.fill:SetAllPoints(fillTexture)
	end

	CropToAtlas(overlay.fill, FillFraction(statusBar))
end

local function HideOverlay(overlay)
	overlay.fill:Hide()
	overlay.wholeBar:Hide()

	overlay.pulsePhase = 0
end

function ns.Paint(statusBar, dive, leftMs, elapsedSeconds)
	local overlay = OverlayFor(statusBar)
	local settings = ns.db
	local red, green, blue, alpha, pulsesPerSecond, flashesWholeBar =
		ns.Look(leftMs, ns.TurnBackMs(dive, settings), dive.maxMs, settings.flash and not dive.paused)

	paintedThisFrame[statusBar] = true

	if not red then
		HideOverlay(overlay)

		return
	end

	overlay.pulsePhase = pulsesPerSecond > 0 and (overlay.pulsePhase + pulsesPerSecond * elapsedSeconds) % 1 or 0

	local fillBrightness = flashesWholeBar and 1 or ns.PulseBrightness(overlay.pulsePhase)

	PlaceFill(overlay, statusBar)

	overlay.fill:SetVertexColor(red * fillBrightness, green * fillBrightness, blue * fillBrightness)

	overlay.fill:SetAlpha(alpha)

	overlay.fill:Show()

	if flashesWholeBar then
		overlay.wholeBar:SetVertexColor(red, green, blue)

		overlay.wholeBar:SetAlpha(pulsesPerSecond > 0 and ns.PulseWave(overlay.pulsePhase) or STEADY_WHOLE_BAR_ALPHA)

		overlay.wholeBar:Show()
	else
		overlay.wholeBar:Hide()
	end
end

function ns.IsDiving()
	for timerName in pairs(dives) do
		if ns.IsColored(timerName) then
			return true
		end
	end

	return false
end

function ns.SettingsChanged()
	driver:Show()
end

driver:SetScript("OnUpdate", function(self, elapsedSeconds)
	local diving = ns.IsDiving()

	wipe(paintedThisFrame)

	for timerName, dive in pairs(dives) do
		local statusBar = ns.IsColored(timerName) and BlizzardBar(timerName)
		local leftMs = statusBar and GetMirrorTimerProgress(timerName)

		if type(leftMs) == "number" then
			ns.Paint(statusBar, dive, leftMs, elapsedSeconds)
		end
	end

	local previewRunning = ns.StepPreview(elapsedSeconds, diving)

	for statusBar, overlay in pairs(overlays) do
		if not paintedThisFrame[statusBar] then
			HideOverlay(overlay)
		end
	end

	if not diving and not previewRunning then
		self:Hide()
	end
end)

local function StartDive(timerName, valueMs, maxMs, scale, paused)
	if not ns.IsRecorded(timerName) then
		return
	end

	if type(scale) ~= "number" or scale >= 0 then
		dives[timerName] = nil

		return
	end

	local previous = dives[timerName]
	local startMs = previous and math.max(previous.startMs, valueMs) or valueMs

	dives[timerName] = { startMs = startMs, maxMs = maxMs, paused = IsPaused(paused) }

	driver:Show()
end

local function StopDive(timerName)
	dives[timerName] = nil
end

local function PauseDive(timerName, paused)
	local dive = dives[timerName]

	if dive then
		dive.paused = IsPaused(paused)
	end
end

local function ReadRunningTimers()
	wipe(dives)

	for index = 1, MIRROR_TIMER_COUNT do
		local timerName, startMs, maxMs, scale, paused = GetMirrorTimerInfo(index)

		if timerName and timerName ~= "UNKNOWN" then
			StartDive(timerName, startMs, maxMs, scale, paused)
		end
	end
end

local eventHandlers = {
	PLAYER_ENTERING_WORLD = ReadRunningTimers,
	MIRROR_TIMER_START = StartDive,
	MIRROR_TIMER_STOP = StopDive,
	MIRROR_TIMER_PAUSE = PauseDive,
}

local events = CreateFrame("Frame")

for event in pairs(eventHandlers) do
	events:RegisterEvent(event)
end

events:SetScript("OnEvent", function(_, event, ...)
	eventHandlers[event](...)
end)
