local _, ns = ...

local BREATH_ATLAS = "ui-castingbar-filling-applyingcrafting"
local PREVIEW_BREATH_MS = 60000
local PREVIEW_SPEED = 3
local PREVIEW_DROWNING_SECONDS = 3
local PREVIEW_DIVE = { startMs = PREVIEW_BREATH_MS, maxMs = PREVIEW_BREATH_MS }
local preview
local previewStartedAt = 0

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

local function TimerBarsAnchor()
	local container = MirrorTimerContainer

	if container and container:GetNumPoints() > 0 then
		local point, relativeTo, relativePoint, x, y = container:GetPoint(1)

		return point, relativeTo or UIParent, relativePoint, x, y, container:GetScale()
	end

	return "TOP", UIParent, "TOP", 0, -100, 1
end

function ns.StartPreview()
	if ns.IsDiving() then
		ns.Print("you're under water now, so watch the real bar. Try the preview on dry land.")

		return
	end

	preview = preview or BuildPreview()

	local point, relativeTo, relativePoint, x, y, scale = TimerBarsAnchor()

	previewStartedAt = GetTime()

	preview:ClearAllPoints()

	preview:SetPoint(point, relativeTo, relativePoint, x, y)

	preview:SetScale(scale)

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

	local previewSeconds = GetTime() - previewStartedAt
	local leftMs = math.max(0, PREVIEW_BREATH_MS - previewSeconds * PREVIEW_SPEED * 1000)
	local drowningSeconds = previewSeconds - PREVIEW_BREATH_MS / 1000 / PREVIEW_SPEED

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

function ns.DescribePreview()
	if not preview then
		return "preview: not built yet"
	end

	local point, relativeTo, relativePoint, x, y = preview:GetPoint(1)

	return ("preview: %s, %.1fs in, %s of %s at %s %s, %s"):format(
		preview:IsShown() and "shown" or "hidden",
		GetTime() - previewStartedAt,
		tostring(point),
		relativeTo and (relativeTo:GetName() or "a frame") or "nothing",
		tostring(relativePoint),
		tostring(x),
		tostring(y)
	)
end
