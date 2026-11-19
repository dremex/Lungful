-- Offline tests: loads the addon's real files under LuaJIT (Lua 5.1 like WoW)
-- against the mocked API in tests/wow_mock.lua.
--   luajit tests/run.lua            (from the repository root)

local mock = dofile("tests/wow_mock.lua")
local globalsBeforeLoading = {}

for name in pairs(_G) do
	globalsBeforeLoading[name] = true
end

local ns = mock.LoadAddon("Lungful", "Lungful")
local failures, passes = 0, 0

local function check(condition, label)
	if condition then
		passes = passes + 1
	else
		failures = failures + 1

		io.write("FAIL: " .. label .. "\n")
	end
end

local function section(name)
	io.write("== " .. name .. "\n")
end

local function near(actual, expected, tolerance)
	return type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 1e-6)
end

local function Overlay(slotIndex)
	return mock.Overlay(mock.BlizzardBar(slotIndex))
end

local function WholeBar(slotIndex)
	return mock.WholeBarOverlay(mock.BlizzardBar(slotIndex))
end

local function Shown(texture)
	return texture ~= nil and texture.shown
end

-- green over red: 0.08 for red, 0.45 for orange and 0.82 for yellow, whatever the flash brightness
local function Hue(texture)
	return texture.color[2] / texture.color[1]
end

-- blue over red: about 0.57 for the pale first yellow, 0 for full yellow and orange
local function Paleness(texture)
	return texture.color[3] / texture.color[1]
end

local function IsRed(texture)
	return Shown(texture) and Hue(texture) < 0.1
end

local function Brightness(texture)
	return texture.color[1]
end

local function RangeOver(seconds, read)
	local lowest, highest = math.huge, -math.huge

	for _ = 1, seconds * 10 do
		mock.Advance(0.1)

		lowest, highest = math.min(lowest, read()), math.max(highest, read())
	end

	return lowest, highest
end

local function BrightnessesOver(texture, seconds)
	return RangeOver(seconds, function()
		return Brightness(texture)
	end)
end

local function AlphasOver(texture, seconds)
	return RangeOver(seconds, function()
		return texture.alpha
	end)
end

local function AddonUpdatersRunning()
	for _, frame in ipairs(mock.frames) do
		if frame.scripts.OnUpdate and frame:IsVisible() then
			return true
		end
	end

	return false
end

local function Reset()
	for timerName in pairs(mock.container.timers) do
		mock.StopTimer(timerName)
	end

	LungfulDB = nil

	mock.Fire("ADDON_LOADED", "Lungful")

	mock.Advance(0.1)

	wipe(mock.printed)
end

local function Printed(pattern)
	for _, line in ipairs(mock.printed) do
		if line:find(pattern) then
			return true
		end
	end

	return false
end

local function Slash(text)
	wipe(mock.printed)

	SlashCmdList.LUNGFUL(text)
end

local function PreviewBar()
	for _, frame in ipairs(mock.frames) do
		local isBlizzard = false

		for index = 1, 3 do
			isBlizzard = isBlizzard or frame == mock.RawBlizzardBar(index)
		end

		if frame.kind == "StatusBar" and not isBlizzard then
			return frame
		end
	end
end

mock.Fire("ADDON_LOADED", "Lungful")
mock.Fire("PLAYER_ENTERING_WORLD", true, false)

--------------------------------------------------------------------------------
section("TOC")
--------------------------------------------------------------------------------
local toc = assert(io.open("Lungful/Lungful.toc")):read("*a")

check(toc:find("## Version: @project-version@", 1, true), "the version is left for the release to stamp")
check(toc:find("## Interface: 16001", 1, true), "it targets the WoW: Forever client")
check(toc:find("## SavedVariables: LungfulDB", 1, true), "settings are saved")
check(toc:find("yellow, orange, then red", 1, true), "the notes name the colors in order")

--------------------------------------------------------------------------------
section("settings")
--------------------------------------------------------------------------------
local fresh = ns.LoadSettings(nil)

check(fresh.mode == "percent" and fresh.turnBackPercent == 30 and fresh.marginSeconds == 5, "defaults fill a new save")
check(fresh.flash == true and fresh.fatigue == true, "flashing and the fatigue bar start on")
check(fresh.version == 2, "a new save records its settings version")

local repaired =
	ns.LoadSettings({ version = 2, mode = "sideways", turnBackPercent = 500, marginSeconds = -3, flash = "yes" })

check(repaired.mode == "percent", "an unknown mode falls back to the default")
check(repaired.turnBackPercent == 95 and repaired.marginSeconds == 0, "out-of-range numbers are clamped")
check(repaired.flash == true, "a value of the wrong type is replaced by its default")
check(ns.LoadSettings({ version = 2, turnBackPercent = 32.6 }).turnBackPercent == 33, "numbers are whole")

local firstVersion = ns.LoadSettings({ mode = "trip", marginSeconds = 8, turnBackPercent = 30, flash = false })

check(firstVersion.mode == "percent", "a 0.1.0 save moves from trip to the new percent default")
check(firstVersion.marginSeconds == 8 and firstVersion.flash == false, "and keeps its other choices")
check(firstVersion.version == 2, "and is marked as moved, so it only happens once")
check(ns.LoadSettings({ version = 2, mode = "trip" }).mode == "trip", "trip chosen since then stays trip")

LungfulDB = { version = 2, mode = "trip", turnBackPercent = 40 }

local saved = LungfulDB

mock.Fire("ADDON_LOADED", "SomeOtherAddon")

check(ns.db ~= saved, "another addon loading leaves settings alone")

mock.Fire("ADDON_LOADED", "Lungful")

check(ns.db == saved and LungfulDB == saved, "the saved table becomes the live settings")
check(ns.db.mode == "trip" and ns.db.turnBackPercent == 40, "saved choices survive loading")
check(ns.db.flash == true and ns.db.marginSeconds == 5, "settings added since the save get their defaults")

Reset()

--------------------------------------------------------------------------------
section("color math")
--------------------------------------------------------------------------------
local trip = ns.LoadSettings({ version = 2, mode = "trip", marginSeconds = 5 })
local percent = ns.LoadSettings({ version = 2, mode = "percent", turnBackPercent = 30 })
local fullDive = { startMs = 60000, maxMs = 60000 }
local partialDive = { startMs = 20000, maxMs = 60000 }
local barMs = 60000

check(ns.TurnBackMs(fullDive, percent) == 18000, "percent: 30% of a 60s bar is 18s")
check(ns.TurnBackMs(partialDive, percent) == 18000, "percent: where the dive started doesn't matter")
check(ns.TurnBackMs(fullDive, trip) == 32500, "trip: a full 60s dive turns back at 32.5s, reaching air with 5s left")
check(ns.TurnBackMs(partialDive, trip) == 12500, "trip: a dive started at 20s turns back at 12.5s")
check(
	ns.TurnBackMs({ startMs = 3000, maxMs = 60000 }, trip) == 3000,
	"trip: diving with less than the margin is red at once"
)
check(ns.Look(42000, 18000, barMs, true) == nil, "from 70% up (30% used) the stock bar shows untouched")

local red, green, blue, pulses, wholeBar = ns.Look(41700, 18000, barMs, true)

check(green / red > 0.9 and blue / red > 0.5 and pulses == 0, "just under 70% a faint, pale yellow shows, steady")

red, green, blue = ns.Look(36000, 18000, barMs, true)

check(blue > 0.2 and blue < 0.4, "at 60% it is halfway from pale to full yellow")

red, green, blue = ns.Look(30000, 18000, barMs, true)

check(near(green, 0.82) and near(blue, 0), "at 50% it is full yellow")

red, green, blue = ns.Look(29700, 18000, barMs, true)

check(near(green, 0.82 + (0.45 - 0.82) * 0.43), "just under 50% it steps 40% of the way to orange, then on evenly")

red, green, blue = ns.Look(24000, 18000, barMs, true)

check(near(green, 0.45) and near(blue, 0), "at 40% it is full orange")

red, green, blue = ns.Look(23700, 18000, barMs, true)

check(near(green, 0.45 + (0.08 - 0.45) * 0.43), "just under 40% it steps 40% of the way to red, then on evenly")

red, green, blue = ns.Look(21000, 18000, barMs, true)

check(green > 0.1 and green < 0.28, "at 35% it is between orange and red")

local warming = true
local previousGreen = math.huge

for leftMs = 41940, 18000, -60 do
	local _, stepGreen = ns.Look(leftMs, 18000, barMs, true)

	warming = warming and stepGreen <= previousGreen + 1e-9

	previousGreen = stepGreen
end

check(warming, "from the first yellow to red the bar only ever gets warmer")

red, green, blue, pulses = ns.Look(18000, 18000, barMs, true)

check(near(green / red, 0.08) and pulses == 0, "at 30% it is red, not flashing yet")

red, green, blue, pulses, wholeBar = ns.Look(15000, 18000, barMs, true)

check(near(green / red, 0.08) and near(pulses, 1) and not wholeBar, "at 25% the fill starts flashing once a second")

red, green, blue, pulses, wholeBar = ns.Look(6500, 18000, barMs, true)

check(pulses > 2.5 and pulses < 3 and not wholeBar, "just above 10% the fill flashes nearly three times a second")

red, green, blue, pulses, wholeBar = ns.Look(6000, 18000, barMs, true)

check(near(green / red, 0.08) and pulses == 4 and wholeBar, "at 10% the whole bar flashes fast")

red, green, blue, pulses, wholeBar = ns.Look(0, 18000, barMs, true)

check(pulses == 4 and wholeBar, "and keeps flashing fast while drowning")

red, green, blue, pulses, wholeBar = ns.Look(10000, 18000, barMs, false)

check(near(green / red, 0.08) and pulses == 0 and not wholeBar, "with flashing off it is steady red")

red, green, blue, pulses, wholeBar = ns.Look(3000, 18000, barMs, false)

check(pulses == 0 and wholeBar, "and the whole bar still turns red under 10%, steady")

red, green, blue, pulses, wholeBar = ns.Look(1000, 3000, barMs, true)

check(near(green / red, 0.08) and pulses == 0 and not wholeBar, "red at 5%: no flashing before drowning")

red, green, blue, pulses, wholeBar = ns.Look(0, 3000, barMs, true)

check(pulses == 4 and wholeBar, "red at 5%: the whole bar flashes once drowning")

red, green, blue, pulses, wholeBar = ns.Look(0, 1000, barMs, true)

check(pulses == 4 and wholeBar, "trip, diving almost out of breath: still flashes once drowning")

red, green, blue, pulses = ns.Look(32500, 32500, barMs, true)

check(near(green / red, 0.08) and pulses == 0, "trip: red at the turn-back point")

red, green, blue, pulses = ns.Look(29500, 32500, barMs, true)

check(near(pulses, 1), "trip: flashing starts 5% of the bar later")
check(ns.PulseBrightness(0) == 1 and near(ns.PulseBrightness(0.5), 0.35), "a flash runs from full to dim")
check(
	ns.Describe(percent)
		== "Faint yellow from 70%, full yellow by 50%, orange by 40%, red by 30%, flashing from 25%, the whole bar flashing from 10% of breath left.",
	"percent mode states its thresholds"
)
check(
	ns.Describe(trip):find("reach air with 5s to spare (32s left on a full 60s bar)", 1, true),
	"trip mode says the spare seconds are what's left at the surface"
)

--------------------------------------------------------------------------------
section("a dive on Blizzard's breath bar")
--------------------------------------------------------------------------------
Reset()

mock.StartTimer("BREATH", 60000, 60000, -1)

mock.Advance(5)

check(not Shown(Overlay(1)), "5s in, the bar is stock")

mock.Advance(12)

check(not Shown(Overlay(1)), "at 72% left, still stock")

mock.Advance(1.3)

local overlay = Overlay(1)

check(Shown(overlay) and Paleness(overlay) > 0.5, "just past 70% left (30% used), a faint yellow shows")
check(Hue(overlay) > 0.9, "a pale yellow")
check(overlay.layer == "OVERLAY" and overlay.desaturated, "the overlay sits over the fill, desaturated for tinting")
check(overlay.allPointsTarget == mock.RawBlizzardBar(1).fill, "it covers just the filled part of the bar")

mock.Advance(5.7)

check(Paleness(overlay) > 0.2 and Paleness(overlay) < 0.4, "at 36s left (60%) it is halfway to full yellow")

mock.Advance(6)

check(near(Hue(overlay), 0.82, 0.01) and Paleness(overlay) < 0.01, "at 30s left (50%) it is full yellow")

local steadyBrightness = Brightness(overlay)

mock.Advance(0.5)

check(Brightness(overlay) == steadyBrightness, "and not flashing")
check(Hue(overlay) > 0.6 and Hue(overlay) < 0.7, "just under 50% it steps toward orange")

mock.Advance(5.5)

check(near(Hue(overlay), 0.45, 0.02), "at 24s left (40%) it is full orange")

mock.Advance(0.5)

check(Hue(overlay) > 0.25 and Hue(overlay) < 0.32, "just under 40% it steps toward red")

mock.Advance(2.5)

check(Hue(overlay) > 0.1 and Hue(overlay) < 0.25, "at 21s left (35%) it is between orange and red")

mock.Advance(4)

check(IsRed(overlay), "at 17s left (28%) it is red")

local lowest, highest = BrightnessesOver(overlay, 1)

check(highest == lowest, "but not flashing until 25%")

mock.Advance(2)

check(IsRed(overlay), "at 14s left (23%) still red")

lowest, highest = BrightnessesOver(overlay, 2)

check(highest - lowest > 0.5, "and flashing")
check(not WholeBar(1).shown, "with the flash on the fill only")

local fraction = mock.RawBlizzardBar(1).value / mock.RawBlizzardBar(1).maxValue

check(near(overlay.texCoord[2], 0.25 + 0.5 * fraction), "the overlay's texture is cropped to the fill, like the bar's")
check(overlay.texCoord[1] == 0.25 and overlay.texCoord[3] == 0.5, "within the atlas's own coordinates")

mock.Advance(5.5)

check(not WholeBar(1).shown, "at 6.5s left (11%) the flash is still on the fill")

mock.Advance(1)

local wholeBarOverlay = WholeBar(1)

check(wholeBarOverlay.shown and IsRed(wholeBarOverlay), "at 5.5s left (9%) the whole bar flashes red")
check(wholeBarOverlay.allPointsTarget == mock.BlizzardBar(1), "covering the empty part too")
check(wholeBarOverlay.texCoord[2] == 0.75, "with the whole texture")
check(wholeBarOverlay.subLevel > overlay.subLevel, "drawn over the red fill")
check(IsRed(overlay) and overlay.allPointsTarget == mock.RawBlizzardBar(1).fill, "the red fill stays underneath")

lowest, highest = BrightnessesOver(overlay, 0.5)

check(lowest == 1 and highest == 1, "steady and bright, so what's left shows between flashes")

local quietest, loudest = AlphasOver(wholeBarOverlay, 1)

check(quietest < 0.1 and loudest > 0.9, "the whole-bar flash goes fully on and off")

mock.Advance(5)

check(wholeBarOverlay.shown, "out of breath, the whole bar still flashes")

quietest, loudest = AlphasOver(wholeBarOverlay, 1)

check(quietest < 0.1 and loudest > 0.9, "on and off while drowning")

mock.StartTimer("BREATH", 0, 60000, 10)

mock.Advance(0.1)

check(not Shown(overlay) and not wholeBarOverlay.shown, "surfacing (breath refilling) puts the stock bar back")

mock.StartTimer("BREATH", 20000, 60000, -1)

mock.Advance(0.1)

check(Shown(overlay) and not IsRed(overlay), "a dive started at 33% picks up partway into the fade")

mock.Advance(2.5)

check(IsRed(overlay), "and is red by 30% like any other")

mock.StopTimer("BREATH")

mock.Advance(0.1)

check(not Shown(overlay), "a stopped timer leaves no overlay")
check(not AddonUpdatersRunning(), "and nothing runs every frame once no timer is up")

--------------------------------------------------------------------------------
section("Blizzard's frames are only read")
--------------------------------------------------------------------------------
local allowedCalls = {
	GetName = true,
	GetNumPoints = true,
	GetPoint = true,
	GetScale = true,
	GetActiveTimer = true,
	GetMinMaxValues = true,
	GetValue = true,
	GetStatusBarTexture = true,
	CreateTexture = true,
}

check(next(mock.blizzardWrites) == nil, "no fields are written on Blizzard's frames")

for call in pairs(mock.blizzardCalls) do
	check(allowedCalls[call:match(":(.+)$")], "only reads and our own textures on Blizzard's frames, not " .. call)
end

check(mock.RawBlizzardBar(1).fill.atlas == "blizzard-BREATH", "the stock fill keeps Blizzard's texture")
check(mock.RawBlizzardBar(1).fill.color == nil, "and isn't tinted")

--------------------------------------------------------------------------------
section("timer edge cases")
--------------------------------------------------------------------------------
Reset()

mock.StartTimer("BREATH", 60000, 60000, -1, { slot = 2 })

mock.Advance(47)

check(IsRed(Overlay(2)), "the overlay goes on whichever of Blizzard's bars holds breath")
check(not Shown(Overlay(1)), "and leaves the others alone")

mock.PauseTimer("BREATH", true)

mock.Advance(0.1)

lowest, highest = BrightnessesOver(Overlay(2), 2)

check(IsRed(Overlay(2)) and highest == lowest, "paused breath (water breathing) is red but steady")

mock.PauseTimer("BREATH", false)

lowest, highest = BrightnessesOver(Overlay(2), 2)

check(highest - lowest > 0.5, "unpaused, it flashes again")

mock.StopTimer("BREATH")

mock.StartTimer("EXHAUSTION", 60000, 60000, -1)

mock.Advance(46)

check(IsRed(Overlay(1)), "the fatigue bar gets the same treatment")

mock.StartTimer("BREATH", 60000, 60000, -1)

mock.Advance(44)

check(IsRed(Overlay(2)), "with breath alongside it on the next bar")

Slash("fatigue off")

mock.Advance(0.1)

check(not Shown(Overlay(1)) and not WholeBar(1).shown, "turning fatigue off clears its bar at once")
check(IsRed(Overlay(2)), "and leaves breath alone")

mock.StopTimer("BREATH")

mock.Advance(0.1)

check(not AddonUpdatersRunning(), "an uncolored fatigue bar alone keeps nothing running")

Slash("fatigue on")

mock.Advance(0.1)

check(Shown(Overlay(1)), "turning fatigue back on mid-swim picks the bar up again")

mock.StopTimer("EXHAUSTION")

Reset()

Slash("fatigue off")

mock.StartTimer("EXHAUSTION", 60000, 60000, -1)

mock.Advance(1)

Slash("fatigue on")

mock.Advance(45)

check(IsRed(Overlay(1)), "a fatigue bar that started while fatigue was off is colored once it's on")

mock.StopTimer("EXHAUSTION")

Reset()

Slash("trip")

mock.StartTimer("BREATH", 60000, 60000, -1)

mock.Advance(20)

mock.StartTimer("BREATH", 40000, 60000, -1)

mock.Advance(6)

check(not IsRed(Overlay(1)), "trip: a repeated start mid-dive doesn't move the turn-back point later...")

mock.Advance(2)

check(IsRed(Overlay(1)), "...or earlier: still red at 32.5s left")

mock.StopTimer("BREATH")

mock.StartTimer("BREATH", 20000, 60000, -1)

mock.Advance(1)

mock.StartTimer("BREATH", 60000, 60000, -1)

mock.Advance(26)

check(not IsRed(Overlay(1)), "trip: a start with more breath than the dive began with is a new dive...")

mock.Advance(2)

check(IsRed(Overlay(1)), "...turning red at 32.5s left, not 12.5s")

mock.StopTimer("BREATH")

mock.StartTimer("BREATH", 20000, 60000, -1)

mock.Advance(6.5)

check(Shown(Overlay(1)) and not IsRed(Overlay(1)), "trip: a dive started at 20s isn't red at 13.5s left")

mock.Advance(1.5)

check(IsRed(Overlay(1)), "it is red by 12.5s left: half of what it dove with, plus spare")

mock.StopTimer("BREATH")

mock.StartTimer("BREATH", 60000, 60000, -1, { silent = true })

mock.Advance(20)

check(not Shown(Overlay(1)), "a dive the addon never heard start goes unnoticed...")

mock.Fire("PLAYER_ENTERING_WORLD", false, true)

mock.Advance(6)

check(Shown(Overlay(1)) and not IsRed(Overlay(1)), "...until a reload reads it, from where it started")

mock.Advance(2)

check(IsRed(Overlay(1)), "so trip mode still turns red at 32.5s left")

mock.StopTimer("BREATH")

Reset()

Slash("percent 30")

mock.StartTimer("BREATH", 60000, 60000, -1)

mock.Advance(41)

check(not IsRed(Overlay(1)), "percent mode: not red at 19s left")

mock.Advance(2)

check(IsRed(Overlay(1)), "percent mode: red at 17s left")

Slash("flash off")

mock.Advance(3)

lowest, highest = BrightnessesOver(Overlay(1), 2)

check(IsRed(Overlay(1)) and highest == lowest, "with flashing off, red stays steady")

mock.StopTimer("BREATH")

--------------------------------------------------------------------------------
section("preview")
--------------------------------------------------------------------------------
Reset()

Slash("test")

check(Printed("previewing a full 60s breath bar at 3x speed"), "/lungful test says what it's showing")

local previewBar = PreviewBar()

check(previewBar and previewBar:IsVisible(), "a preview bar appears")
check(previewBar.fill.atlas == "ui-castingbar-filling-applyingcrafting", "drawn with the stock breath fill")
check(previewBar.parent.strata == "DIALOG", "above the options window, so it shows from there too")

local previewAnchor = previewBar.parent.points[1]

check(previewAnchor[2] ~= MirrorTimerContainer, "it isn't anchored to the timer container, which has no size on land")
check(
	previewAnchor[1] == "TOP"
		and previewAnchor[2] == UIParent
		and previewAnchor[3] == "TOP"
		and previewAnchor[5] == -100,
	"it sits where the timer bars do, by copying their anchor"
)
check(previewBar.parent.scale == 1.2, "at the size Edit Mode gives the timer bars")

mock.Advance(5)

check(near(previewBar.value, 45, 0.01), "it drains at 3x speed")

mock.Advance(10)

local previewOverlay = previewBar.textures[1]

check(IsRed(previewOverlay), "it is red at 25% like a real dive")

mock.Advance(6)

check(previewBar.textures[2].shown and previewBar.textures[2].allPointsTarget == previewBar, "and flashes whole")

mock.Advance(3)

check(not previewBar:IsVisible(), "then goes away by itself")
check(not AddonUpdatersRunning(), "and stops updating")

Slash("test")

for _, frame in ipairs(mock.frames) do
	if frame.scripts.OnUpdate and frame:IsVisible() then
		frame.scripts.OnUpdate(frame, 600)
	end
end

check(previewBar:IsVisible(), "a huge first frame time doesn't end the preview early")

mock.Advance(24)

mock.StartTimer("BREATH", 60000, 60000, -1)

Slash("test")

check(Printed("under water"), "under water, the preview says to watch the real bar")
check(not previewBar:IsVisible(), "and stays off it")

mock.StopTimer("BREATH")

Slash("test")

mock.Advance(1)

mock.StartTimer("BREATH", 60000, 60000, -1)

mock.Advance(0.1)

check(not previewBar:IsVisible(), "a real dive takes over from a running preview")

mock.StopTimer("BREATH")

--------------------------------------------------------------------------------
section("options page")
--------------------------------------------------------------------------------
Reset()

local panel = mock.settingsPanel
local category = panel.categories[1]
local controls = panel.controls
local settingNamed = panel.settings

check(#panel.categories == 1 and category.name == "Lungful", "one Lungful page, however often settings load")
check(category.registered, "listed under Options > AddOns")
check(
	controls[1].kind == "dropdown"
		and controls[2].kind == "slider"
		and controls[3].kind == "slider"
		and controls[4].kind == "checkbox"
		and controls[5].kind == "checkbox"
		and controls[6].kind == "button",
	"a mode dropdown, two sliders, two checkboxes and a preview button, in that order"
)
check(controls[1].options()[1].value == "percent" and controls[1].options()[2].value == "trip", "both modes offered")
check(controls[2].options.minValue == 5 and controls[2].options.maxValue == 95, "the red point runs 5% to 95%")
check(controls[2].options.formatter(30) == "30%", "and reads as a percentage")
check(controls[3].options.minValue == 0 and controls[3].options.maxValue == 30, "spare seconds run 0 to 30")
check(controls[3].options.formatter(5) == "5s", "and read as seconds")
check(controls[2].options.labelType == MinimalSliderWithSteppersMixin.Label.Right, "labels sit right of the sliders")
check(controls[2].modifyPredicate() and not controls[3].modifyPredicate(), "in percent mode only the % slider is live")

settingNamed.LUNGFUL_MODE:SetValue("trip")

check(ns.db.mode == "trip", "choosing trip in the dropdown saves it")
check(not controls[2].modifyPredicate() and controls[3].modifyPredicate(), "and makes the seconds slider live instead")

settingNamed.LUNGFUL_TURNBACKPERCENT:SetValue(37.6)

check(ns.db.turnBackPercent == 38, "slider values are saved as whole numbers")

Slash("percent 40")

check(settingNamed.LUNGFUL_TURNBACKPERCENT:GetValue() == 40, "the page shows changes made by slash command")
check(settingNamed.LUNGFUL_MODE:GetValue() == "percent", "including the mode")

settingNamed.LUNGFUL_FLASH:SetValue(false)

check(ns.db.flash == false, "the flash checkbox saves")

settingNamed.LUNGFUL_FATIGUE:SetValue(false)

check(ns.db.fatigue == false, "the fatigue checkbox saves")
check(controls[4].tooltip:find("10%", 1, true), "the flash tooltip names the whole-bar point")

Reset()

mock.StartTimer("BREATH", 60000, 60000, -1)

mock.Advance(35)

check(Shown(Overlay(1)) and not IsRed(Overlay(1)), "at 25s left with red at 30%, the bar isn't red yet")

settingNamed.LUNGFUL_TURNBACKPERCENT:SetValue(45)

mock.Advance(0.1)

check(IsRed(Overlay(1)), "moving the red point to 45% repaints the bar at once")

mock.StopTimer("BREATH")

controls[6].buttonClick()

check(previewBar:IsVisible(), "the preview button runs the preview")

mock.Advance(24)

--------------------------------------------------------------------------------
section("commands")
--------------------------------------------------------------------------------
Reset()

Slash("")

check(panel.openedCategoryID == category:GetID(), "/lungful alone opens the options page")

Slash("help")

check(Printed("red by 30%%"), "/lungful help shows the current setting")
check(
	Printed("faint yellow from 40 above it, orange from 20 above and flashing from 5 below"),
	"and how the stages relate"
)
check(Printed("/lungful fatigue on|off"), "and the commands")

mock.StartTimer("BREATH", 60000, 60000, -1)

mock.Advance(30)

Slash("debug")

check(Printed("debug: mode percent"), "/lungful debug shows the settings")
check(Printed("game timer 1: BREATH"), "the game's timers")
check(Printed("dive BREATH: started 60000 of 60000 ms"), "the dive it's tracking")
check(Printed("fill overlay shown, alpha 1.00, color 1.00 0.82 0.00"), "what the overlay is drawing")
check(Printed("preview: hidden"), "and the preview")

mock.StopTimer("BREATH")

Slash("bogus")

check(Printed("/lungful test"), "an unknown command shows help")

Slash("trip 8")

check(ns.db.mode == "trip" and ns.db.marginSeconds == 8, "/lungful trip 8 sets 8 spare seconds")
check(Printed("reach air with 8s to spare"), "and says so")

Slash("trip 99")

check(ns.db.marginSeconds == 30, "spare seconds are capped")

Slash("trip")

check(ns.db.marginSeconds == 30, "/lungful trip alone keeps the spare seconds")

Slash("trip soon")

check(ns.db.marginSeconds == 30 and Printed("/lungful test"), "/lungful trip with a word shows help")

Slash("percent  40")

check(ns.db.mode == "percent" and ns.db.turnBackPercent == 40, "extra spaces between words are fine")

Slash("PERCENT 35")

check(ns.db.turnBackPercent == 35, "commands ignore case")

Slash("percent")

check(ns.db.turnBackPercent == 35 and Printed("/lungful test"), "/lungful percent without a number shows help")

Slash("flash off")

check(ns.db.flash == false and Printed("flashing"), "/lungful flash off")

Slash("flash of")

check(ns.db.flash == false and Printed("/lungful test"), "a typo shows help instead of flipping the setting")

Slash("flash")

check(ns.db.flash == true, "/lungful flash on its own toggles")

Slash("fatigue off")

check(ns.db.fatigue == false, "/lungful fatigue off")
check(LungfulDB == ns.db, "commands change the saved settings")

Lungful_OnAddonCompartmentClick("Lungful", "LeftButton")

check(panel.openedCategoryID == category:GetID(), "clicking Lungful in the addon menu opens the options")

Lungful_OnAddonCompartmentClick("Lungful", "RightButton")

check(previewBar:IsVisible(), "right-clicking it runs the preview")

mock.Advance(24)

--------------------------------------------------------------------------------
section("globals")
--------------------------------------------------------------------------------
local expectedGlobals = {
	LungfulDB = true,
	SLASH_LUNGFUL1 = true,
	Lungful_OnAddonCompartmentClick = true,
	Lungful_OnAddonCompartmentEnter = true,
	Lungful_OnAddonCompartmentLeave = true,
}

for name in pairs(_G) do
	if not globalsBeforeLoading[name] then
		check(expectedGlobals[name], "the addon only adds the globals it means to, not " .. name)
	end
end

check(SlashCmdList.LUNGFUL ~= nil, "it registers its slash command")

io.write(("\n%d passed, %d failed\n"):format(passes, failures))

os.exit(failures == 0 and 0 or 1)
