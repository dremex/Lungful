local _, ns = ...

local function Highlight(text)
	return "|cffffd100" .. tostring(text) .. "|r"
end

local function OnOffText(enabled)
	return Highlight(enabled and "on" or "off")
end

local function ParseOnOff(word, current)
	if word == nil then
		return not current
	end

	if word == "on" then
		return true
	end

	if word == "off" then
		return false
	end
end

local function Help()
	local db = ns.db
	local stages = ns.STAGE_PERCENTS
	local lines = {
		("%s - open the options"):format(Highlight("/lungful")),
		("%s - watch a sped-up dive"):format(Highlight("/lungful test")),
		("%s - red at that %% of breath left, orange from %d above, flashing from %d below (now %s)"):format(
			Highlight("/lungful percent <number>"),
			stages.orangeLead,
			stages.flashLag,
			Highlight(db.turnBackPercent .. "%")
		),
		("%s - red when swimming back would reach air with that many seconds to spare (now %s)"):format(
			Highlight("/lungful trip [seconds]"),
			Highlight(db.marginSeconds .. "s")
		),
		("%s - flash near the end (now %s)"):format(Highlight("/lungful flash on|off"), OnOffText(db.flash)),
		("%s - color the fatigue bar in open water too (now %s)"):format(
			Highlight("/lungful fatigue on|off"),
			OnOffText(db.fatigue)
		),
	}

	ns.Print(ns.Describe(db))

	for _, line in ipairs(lines) do
		print("  " .. line)
	end
end

local function UseMode(mode, key, number)
	ns.db.mode = mode

	if number then
		ns.db[key] = ns.ClampSetting(key, number)
	end

	ns.SettingsChanged()

	ns.Print(ns.Describe(ns.db))
end

local function SetPercent(argument)
	local number = tonumber(argument)

	if not number then
		return Help()
	end

	UseMode("percent", "turnBackPercent", number)
end

local function SetTrip(argument)
	local number = tonumber(argument)

	if argument and not number then
		return Help()
	end

	UseMode("trip", "marginSeconds", number)
end

local function Toggle(key, label)
	return function(argument)
		local enabled = ParseOnOff(argument, ns.db[key])

		if enabled == nil then
			return Help()
		end

		ns.db[key] = enabled

		ns.SettingsChanged()

		ns.Print(("%s %s."):format(label, OnOffText(enabled)))
	end
end

local function OpenOptions()
	if not ns.OpenOptions() then
		Help()
	end
end

local commands = {
	options = OpenOptions,
	help = Help,
	test = ns.StartPreview,
	preview = ns.StartPreview,
	percent = SetPercent,
	trip = SetTrip,
	flash = Toggle("flash", "flashing"),
	fatigue = Toggle("fatigue", "fatigue bar"),
}

SLASH_LUNGFUL1 = "/lungful"

SlashCmdList.LUNGFUL = function(input)
	local words = {}

	for word in strlower(input or ""):gmatch("%S+") do
		table.insert(words, word)
	end

	local command = commands[words[1] or "options"] or Help

	command(words[2])
end

function Lungful_OnAddonCompartmentClick(_, mouseButton)
	if mouseButton == "RightButton" then
		ns.StartPreview()
	else
		OpenOptions()
	end
end

function Lungful_OnAddonCompartmentEnter(_, frame)
	GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")

	GameTooltip:SetText("Lungful")

	GameTooltip:AddLine(ns.Describe(ns.db), 1, 1, 1, true)
	GameTooltip:AddLine("Click for options. Right-click to preview a dive.", 0.6, 0.6, 0.6, true)

	GameTooltip:Show()
end

function Lungful_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
