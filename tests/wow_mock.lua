-- Just enough of the WoW API to load Lungful under LuaJIT and drive it like the
-- game does. The mirror timer part copies Blizzard_MirrorTimer/Mainline from
-- the 1.60.1 Forever client: a MirrorTimerContainer with three timer frames,
-- each holding a StatusBar, handed out to timers by GetActiveTimer. The
-- Settings part follows Blizzard_Settings_Shared from the same client.

local mock = { printed = {}, frames = {}, blizzardCalls = {}, blizzardWrites = {} }
local clock = { now = 1000 }

mock.clock = clock

function GetTime()
	return clock.now
end

function wipe(tbl)
	for key in pairs(tbl) do
		tbl[key] = nil
	end

	return tbl
end

strlower = string.lower

function print(...)
	local parts = {}

	for i = 1, select("#", ...) do
		table.insert(parts, tostring(select(i, ...)))
	end

	table.insert(mock.printed, table.concat(parts, " "))
end

SlashCmdList = {}

local ATLAS_INFO = {
	["ui-castingbar-filling-standard"] = {
		file = 4505182,
		leftTexCoord = 0.25,
		rightTexCoord = 0.75,
		topTexCoord = 0.5,
		bottomTexCoord = 0.625,
	},
}

C_Texture = {
	GetAtlasInfo = function(atlas)
		return ATLAS_INFO[atlas]
	end,
}

local Methods = {}

Methods.Region = {
	Show = function(self)
		self.shown = true
	end,
	Hide = function(self)
		self.shown = false
	end,
	SetShown = function(self, shown)
		self.shown = not not shown
	end,
	IsShown = function(self)
		return self.shown
	end,
	IsVisible = function(self)
		local region = self

		while region do
			if not region.shown then
				return false
			end

			region = region.parent
		end

		return true
	end,
	SetPoint = function(self, point, relativeTo, relativePoint, x, y)
		table.insert(self.points, { point, relativeTo, relativePoint, x, y })
	end,
	ClearAllPoints = function(self)
		self.points = {}

		self.allPointsTarget = nil
	end,
	SetAllPoints = function(self, target)
		self.allPointsTarget = target or self.parent
	end,
	SetSize = function(self, width, height)
		self.width, self.height = width, height
	end,
	SetAlpha = function(self, alpha)
		self.alpha = alpha
	end,
	GetAlpha = function(self)
		return self.alpha
	end,
	GetPoint = function(self, index)
		return unpack(self.points[index or 1] or {})
	end,
	GetNumPoints = function(self)
		return #self.points
	end,
	SetScale = function(self, scale)
		self.scale = scale
	end,
	GetScale = function(self)
		return self.scale or 1
	end,
	GetName = function(self)
		return self.name
	end,
}

Methods.Texture = {
	SetTexture = function(self, asset)
		self.asset, self.atlas, self.texCoord = asset, nil, { 0, 1, 0, 1 }
	end,
	SetColorTexture = function(self, red, green, blue)
		self.asset, self.atlas, self.colorTexture = nil, nil, { red, green, blue }
	end,
	SetAtlas = function(self, atlas)
		self.atlas, self.asset = atlas, nil

		return true
	end,
	SetTexCoord = function(self, left, right, top, bottom)
		self.texCoord = { left, right, top, bottom }
	end,
	SetDesaturated = function(self, desaturated)
		self.desaturated = desaturated
	end,
	SetVertexColor = function(self, red, green, blue)
		self.color = { red, green, blue }
	end,
	GetVertexColor = function(self)
		return unpack(self.color or { 1, 1, 1 })
	end,
}

Methods.FontString = {
	SetText = function(self, text)
		self.text = text
	end,
	GetText = function(self)
		return self.text
	end,
	SetJustifyH = function() end,
}

local NewRegion

Methods.Frame = {
	RegisterEvent = function(self, event)
		self.events[event] = true
	end,
	SetScript = function(self, handler, script)
		self.scripts[handler] = script
	end,
	GetScript = function(self, handler)
		return self.scripts[handler]
	end,
	SetFrameStrata = function(self, strata)
		self.strata = strata
	end,
	SetFrameLevel = function(self, level)
		self.level = level
	end,
	GetFrameLevel = function(self)
		return self.level
	end,
	CreateTexture = function(self, name, layer, template, subLevel)
		local texture = NewRegion("Texture", self)

		texture.layer, texture.subLevel = layer, subLevel

		table.insert(self.textures, texture)

		return texture
	end,
	CreateFontString = function(self, name, layer, template)
		return NewRegion("FontString", self)
	end,
}

Methods.StatusBar = {
	SetMinMaxValues = function(self, minValue, maxValue)
		self.minValue, self.maxValue = minValue, maxValue
	end,
	GetMinMaxValues = function(self)
		return self.minValue, self.maxValue
	end,
	SetValue = function(self, value)
		self.value = value
	end,
	GetValue = function(self)
		return self.value
	end,
	SetStatusBarTexture = function(self, asset)
		self.fill = self.fill or NewRegion("Texture", self)

		self.fill.atlas = asset
	end,
	GetStatusBarTexture = function(self)
		return self.fill
	end,
}

local KIND_CHAIN = {
	Texture = { "Texture", "Region" },
	FontString = { "FontString", "Region" },
	Frame = { "Frame", "Region" },
	StatusBar = { "StatusBar", "Frame", "Region" },
}

local function FindMethod(kind, key)
	for _, methodsKind in ipairs(KIND_CHAIN[kind]) do
		local method = Methods[methodsKind][key]

		if method then
			return method
		end
	end
end

local regionMeta = {
	__index = function(self, key)
		return FindMethod(rawget(self, "kind"), key)
	end,
}

function NewRegion(kind, parent)
	local region = setmetatable({
		kind = kind,
		parent = parent,
		shown = true,
		points = {},
		alpha = 1,
		events = {},
		scripts = {},
		textures = {},
		level = parent and parent.level and parent.level + 1 or 1,
	}, regionMeta)

	table.insert(mock.frames, region)

	return region
end

UIParent = NewRegion("Frame")

UIParent.name = "UIParent"

function CreateFrame(kind, name, parent)
	local frame = NewRegion(kind, parent or UIParent)

	if name then
		frame.name = name

		_G[name] = frame
	end

	return frame
end

GameTooltip = CreateFrame("Frame")

GameTooltip.SetOwner = function() end
GameTooltip.SetText = function() end
GameTooltip.AddLine = function() end

-- Settings records what the addon registers, so tests can work the options
-- page the way a player would: read and change each setting, and click the button.
local settingsPanel = { categories = {}, settings = {}, controls = {} }

mock.settingsPanel = settingsPanel

local function AddControl(kind, category, setting, options, tooltip)
	local control = { kind = kind, category = category, setting = setting, options = options, tooltip = tooltip }

	function control:SetParentInitializer(parentInitializer, modifyPredicate)
		assert(parentInitializer and parentInitializer ~= self)

		self.parentInitializer, self.modifyPredicate = parentInitializer, modifyPredicate
	end

	table.insert(settingsPanel.controls, control)

	return control
end

Settings = {
	VarType = { Boolean = "boolean", String = "string", Number = "number" },
	RegisterVerticalLayoutCategory = function(name)
		local category = { name = name, id = 100 + #settingsPanel.categories }
		local layout = {}

		function category:GetID()
			return self.id
		end

		function layout:AddInitializer(initializer)
			table.insert(settingsPanel.controls, initializer)
		end

		table.insert(settingsPanel.categories, category)

		return category, layout
	end,
	RegisterAddOnCategory = function(category)
		category.registered = true
	end,
	RegisterProxySetting = function(category, variable, variableType, name, defaultValue, getValue, setValue)
		assert(type(defaultValue) == variableType, variable .. "'s default isn't a " .. variableType)
		assert(settingsPanel.settings[variable] == nil, variable .. " is registered twice")

		local setting = { category = category, variable = variable, variableType = variableType, name = name }

		function setting:GetValue()
			return getValue()
		end

		function setting:SetValue(value)
			assert(type(value) == variableType, variable .. " was set to a " .. type(value))

			setValue(value)
		end

		settingsPanel.settings[variable] = setting

		return setting
	end,
	CreateControlTextContainer = function()
		local container = { data = {} }

		function container:Add(value, label, tooltip)
			table.insert(self.data, { value = value, label = label, text = label, tooltip = tooltip })
		end

		function container:GetData()
			return self.data
		end

		return container
	end,
	CreateSliderOptions = function(minValue, maxValue, rate)
		local options = { minValue = minValue, maxValue = maxValue, steps = (maxValue - minValue) / rate }

		function options:SetLabelFormatter(labelType, formatter)
			self.labelType, self.formatter = labelType, formatter
		end

		return options
	end,
	CreateDropdown = function(category, setting, options, tooltip)
		return AddControl("dropdown", category, setting, options, tooltip)
	end,
	CreateSlider = function(category, setting, options, tooltip)
		return AddControl("slider", category, setting, options, tooltip)
	end,
	CreateCheckbox = function(category, setting, tooltip)
		return AddControl("checkbox", category, setting, nil, tooltip)
	end,
	OpenToCategory = function(categoryID)
		settingsPanel.openedCategoryID = categoryID
	end,
}

MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }

function CreateSettingsButtonInitializer(name, buttonText, buttonClick, tooltip, addSearchTags)
	assert(addSearchTags ~= nil, "Blizzard asserts addSearchTags is given")

	return { kind = "button", name = name, buttonText = buttonText, buttonClick = buttonClick, tooltip = tooltip }
end

-- Blizzard's frames record every method addon code calls on them and every
-- field it writes, so the tests can prove Lungful only reads them (and adds its
-- own textures). The mock's Blizzard side writes through `raw`, unrecorded.
local function Watched(raw, label)
	local proxy = setmetatable({}, {
		__index = function(_, key)
			local value = raw[key]

			if type(value) == "function" then
				return function(_, ...)
					mock.blizzardCalls[label .. ":" .. key] = true

					return value(raw, ...)
				end
			end

			return value
		end,
		__newindex = function(_, key, value)
			mock.blizzardWrites[label .. "." .. key] = true

			raw[key] = value
		end,
	})

	rawset(proxy, "__raw", raw)

	return proxy
end

local container = { activeTimers = {}, mirrorTimers = {}, timers = {} }

for index = 1, 3 do
	local timerFrame = NewRegion("Frame", UIParent)
	local statusBar = NewRegion("StatusBar", timerFrame)
	local watchedBar = Watched(statusBar, "StatusBar" .. index)

	timerFrame.shown = false

	timerFrame.StatusBar = watchedBar

	statusBar.fill = NewRegion("Texture", statusBar)

	statusBar.minValue, statusBar.maxValue, statusBar.value = 0, 1, 0

	container.mirrorTimers[index] = {
		frame = timerFrame,
		watchedFrame = Watched(timerFrame, "MirrorTimer" .. index),
		bar = statusBar,
		watched = watchedBar,
	}
end

-- Blizzard's layout shrinks the container to 0x0 while no timer is up, which
-- leaves it without a usable position: anything anchored to it isn't drawn.
-- It sits where Edit Mode puts it, TOP of UIParent at -100 by default.
MirrorTimerContainer = Watched({
	GetName = function()
		return "MirrorTimerContainer"
	end,
	GetNumPoints = function()
		return 1
	end,
	GetPoint = function()
		return "TOP", UIParent, "TOP", 0, -100
	end,
	GetScale = function()
		return 1.2
	end,
	GetActiveTimer = function(_, timerName)
		local slot = container.activeTimers[timerName]

		return slot and slot.watchedFrame
	end,
}, "MirrorTimerContainer")

mock.container = container

function mock.BlizzardBar(slotIndex)
	return container.mirrorTimers[slotIndex].watched
end

function mock.RawBlizzardBar(slotIndex)
	return container.mirrorTimers[slotIndex].bar
end

function mock.Overlay(statusBar)
	local raw = rawget(statusBar, "__raw") or statusBar

	return raw.textures[1]
end

function mock.WholeBarOverlay(statusBar)
	local raw = rawget(statusBar, "__raw") or statusBar

	return raw.textures[2]
end

local function FreeSlot(timerName)
	if container.activeTimers[timerName] then
		return container.activeTimers[timerName]
	end

	for _, slot in ipairs(container.mirrorTimers) do
		if not slot.timer then
			return slot
		end
	end
end

local function SyncBar(timerName)
	local timer = container.timers[timerName]
	local slot = container.activeTimers[timerName]

	if timer and slot then
		slot.bar.minValue, slot.bar.maxValue, slot.bar.value = 0, timer.maxMs / 1000, timer.valueMs / 1000
	end
end

function GetMirrorTimerProgress(timerName)
	local timer = container.timers[timerName]

	return timer and timer.valueMs or 0
end

function GetMirrorTimerInfo(index)
	local slot = container.mirrorTimers[index]
	local timer = slot.timer and container.timers[slot.timer]

	if not timer then
		return "UNKNOWN", 0, 0, 0, 0, ""
	end

	return slot.timer, timer.startMs, timer.maxMs, timer.scale, timer.paused and 1 or 0, timer.label, 0
end

function mock.Fire(event, ...)
	for _, frame in ipairs(mock.frames) do
		if frame.events[event] and frame.scripts.OnEvent then
			frame.scripts.OnEvent(frame, event, ...)
		end
	end
end

function mock.StartTimer(timerName, valueMs, maxMs, scale, options)
	local settings = options or {}
	local slot = settings.slot and container.mirrorTimers[settings.slot] or FreeSlot(timerName)
	local previous = container.activeTimers[timerName]

	if previous and previous ~= slot then
		previous.timer = nil

		previous.frame.shown = false
	end

	container.timers[timerName] = {
		valueMs = valueMs,
		startMs = valueMs,
		maxMs = maxMs,
		scale = scale,
		paused = settings.paused,
		label = timerName == "BREATH" and "Breath" or "Fatigue",
	}

	slot.timer = timerName

	slot.frame.shown = true

	slot.bar.fill.atlas = "blizzard-" .. timerName

	container.activeTimers[timerName] = slot

	SyncBar(timerName)

	if not settings.silent then
		mock.Fire("MIRROR_TIMER_START", timerName, valueMs, maxMs, scale, settings.paused and 1 or 0, timerName)
	end
end

function mock.StopTimer(timerName)
	local slot = container.activeTimers[timerName]

	if slot then
		slot.timer = nil

		slot.frame.shown = false
	end

	container.activeTimers[timerName] = nil
	container.timers[timerName] = nil

	mock.Fire("MIRROR_TIMER_STOP", timerName)
end

function mock.PauseTimer(timerName, paused)
	container.timers[timerName].paused = paused

	mock.Fire("MIRROR_TIMER_PAUSE", timerName, paused and 1 or 0)
end

local function RunOnUpdates(elapsedSeconds)
	for _, frame in ipairs(mock.frames) do
		local onUpdate = frame.scripts.OnUpdate

		if onUpdate and frame:IsVisible() then
			onUpdate(frame, elapsedSeconds)
		end
	end
end

function mock.Advance(seconds)
	local stepSeconds = 0.1
	local steps = math.floor(seconds / stepSeconds + 0.5)

	for _ = 1, steps do
		clock.now = clock.now + stepSeconds

		for timerName, timer in pairs(container.timers) do
			if not timer.paused then
				timer.valueMs = math.min(timer.maxMs, math.max(0, timer.valueMs + timer.scale * stepSeconds * 1000))

				SyncBar(timerName)
			end
		end

		RunOnUpdates(stepSeconds)
	end
end

function mock.LoadAddon(folder, addonName)
	local namespace = {}
	local toc = assert(io.open(folder .. "/" .. addonName .. ".toc")):read("*a")

	for line in toc:gmatch("[^\n]+") do
		if line:match("%.lua$") then
			assert(loadfile(folder .. "/" .. line))(addonName, namespace)
		end
	end

	return namespace
end

return mock
