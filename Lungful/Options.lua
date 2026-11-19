local _, ns = ...

local category

local function Normalized(key, value)
	if ns.LIMITS[key] then
		return ns.ClampSetting(key, value)
	end

	return value
end

local function ProxySetting(optionsCategory, key, name)
	local defaultValue = ns.defaults[key]
	local variable = "LUNGFUL_" .. key:upper()

	local function GetValue()
		return ns.db[key]
	end

	local function SetValue(value)
		ns.db[key] = Normalized(key, value)

		ns.SettingsChanged()
	end

	return Settings.RegisterProxySetting(
		optionsCategory,
		variable,
		type(defaultValue),
		name,
		defaultValue,
		GetValue,
		SetValue
	)
end

local function ModeOptions()
	local container = Settings.CreateControlTextContainer()

	container:Add("percent", "At a set share of breath", "Turns red at the same share of breath left on every dive.")
	container:Add(
		"trip",
		"From how long you've been under",
		"Turns red when swimming back the way you came would only just reach air."
	)

	return container:GetData()
end

local function IsPercentMode()
	return ns.db.mode == "percent"
end

local function IsTripMode()
	return ns.db.mode == "trip"
end

local function PercentLabel(value)
	return ("%d%%"):format(value)
end

local function SecondsLabel(value)
	return ("%ds"):format(value)
end

local function SliderOptions(key, formatLabel)
	local limits = ns.LIMITS[key]
	local options = Settings.CreateSliderOptions(limits.min, limits.max, 1)

	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatLabel)

	return options
end

local function BuildOptions()
	local stages = ns.STAGE_PERCENTS
	local optionsCategory, layout = Settings.RegisterVerticalLayoutCategory("Lungful")
	local modeSetting = ProxySetting(optionsCategory, "mode", "Turn red")
	local percentSetting = ProxySetting(optionsCategory, "turnBackPercent", "Red at")
	local marginSetting = ProxySetting(optionsCategory, "marginSeconds", "Spare seconds")
	local flashSetting = ProxySetting(optionsCategory, "flash", "Flash near the end")
	local fatigueSetting = ProxySetting(optionsCategory, "fatigue", "Color the fatigue bar")
	local modeInitializer = Settings.CreateDropdown(
		optionsCategory,
		modeSetting,
		ModeOptions,
		("How Lungful picks the point where the bar turns red. It fades in orange %d%% of the bar before that and starts flashing %d%% after."):format(
			stages.orangeLead,
			stages.flashLag
		)
	)

	local percentInitializer = Settings.CreateSlider(
		optionsCategory,
		percentSetting,
		SliderOptions("turnBackPercent", PercentLabel),
		"The share of breath left when the bar turns red."
	)

	local marginInitializer = Settings.CreateSlider(
		optionsCategory,
		marginSetting,
		SliderOptions("marginSeconds", SecondsLabel),
		"How much breath you want left when you reach air, if you swim back the way you came."
	)

	percentInitializer:SetParentInitializer(modeInitializer, IsPercentMode)
	marginInitializer:SetParentInitializer(modeInitializer, IsTripMode)

	Settings.CreateCheckbox(
		optionsCategory,
		flashSetting,
		("The red bar flashes faster as breath runs out, and the whole bar flashes from %d%%."):format(stages.wholeBar)
	)
	Settings.CreateCheckbox(
		optionsCategory,
		fatigueSetting,
		"Treat the fatigue bar in deep water the same way as the breath bar."
	)

	layout:AddInitializer(
		CreateSettingsButtonInitializer(
			"Preview",
			"Watch a dive",
			ns.StartPreview,
			"Plays a sped-up dive on a sample bar so you can see each stage.",
			true
		)
	)

	Settings.RegisterAddOnCategory(optionsCategory)

	return optionsCategory
end

function ns.OpenOptions()
	if not category then
		return false
	end

	Settings.OpenToCategory(category:GetID())

	return true
end

ns.OnSettingsLoaded(function()
	if category or not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end

	category = BuildOptions()
end)
