local _, ns = ...

local BREATH_ATLAS = "ui-castingbar-filling-applyingcrafting"
local PREVIEW_BREATH_MS = 60000
local PREVIEW_SPEED = 3
local PREVIEW_DROWNING_SECONDS = 3
local PREVIEW_DIVE = { startMs = PREVIEW_BREATH_MS, maxMs = PREVIEW_BREATH_MS }
local preview
local previewElapsedSeconds = 0

local function AtlasAround(frame, layer, subLevel, atlas, target, outset)
	local texture = frame:CreateTexture(nil, layer, nil, subLevel)

	texture:SetAtlas(atlas)

	texture:SetPoint("TOPLEFT", target, "TOPLEFT", -outset, outset)
	texture:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", outset, -outset)

	return texture
end

local function BuildPreview()
	local frame = CreateFrame("Frame", nil, UIParent)
	local bar = CreateFrame("StatusBar", nil, frame)
	local textBox = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

	frame:SetSize(206, 32)

	frame:SetFrameStrata("DIALOG")

	frame:Hide()

	bar:SetSize(195, 13)

	bar:SetPoint("TOP", 0, -2)

	bar:SetFrameLevel(frame:GetFrameLevel())

	bar:SetStatusBarTexture(BREATH_ATLAS)

	bar:SetMinMaxValues(0, PREVIEW_BREATH_MS / 1000)

	textBox:SetAtlas("ui-castingbar-textbox")

	textBox:SetPoint("TOPLEFT", bar, "TOPLEFT")
	textBox:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -14)

	AtlasAround(frame, "BACKGROUND", 1, "ui-castingbar-background", bar, 1)
	AtlasAround(frame, "OVERLAY", 0, "ui-castingbar-frame", bar, 2)

	label:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
	label:SetPoint("BOTTOMRIGHT", textBox, "BOTTOMRIGHT", 0, 2)

	label:SetJustifyH("CENTER")

	frame.bar = bar
	frame.label = label

	return frame
end

function ns.StartPreview()
	if ns.IsDiving() then
		ns.Print("you're under water now, so watch the real bar. Try the preview on dry land.")

		return
	end

	preview = preview or BuildPreview()

	previewElapsedSeconds = 0

	preview:ClearAllPoints()

	preview:SetPoint("TOP", MirrorTimerContainer or UIParent, "TOP", 0, MirrorTimerContainer and 0 or -100)

	preview:Show()

	ns.SettingsChanged()

	ns.Print(
		("previewing a full %ds breath bar at %dx speed. %s"):format(
			PREVIEW_BREATH_MS / 1000,
			PREVIEW_SPEED,
			ns.Describe(ns.db)
		)
	)
end

function ns.StepPreview(elapsedSeconds, diving)
	if not (preview and preview:IsShown()) then
		return false
	end

	if diving then
		preview:Hide()

		return false
	end

	previewElapsedSeconds = previewElapsedSeconds + elapsedSeconds

	local leftMs = math.max(0, PREVIEW_BREATH_MS - previewElapsedSeconds * PREVIEW_SPEED * 1000)
	local drowningSeconds = previewElapsedSeconds - PREVIEW_BREATH_MS / 1000 / PREVIEW_SPEED

	if drowningSeconds >= PREVIEW_DROWNING_SECONDS then
		preview:Hide()

		return false
	end

	preview.bar:SetValue(leftMs / 1000)

	preview.label:SetText(
		leftMs > 0 and ("Breath preview: %ds left"):format(math.ceil(leftMs / 1000)) or "Breath preview: drowning"
	)

	ns.Paint(preview.bar, PREVIEW_DIVE, leftMs, elapsedSeconds)

	return true
end
