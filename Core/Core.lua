local addonName, root = ... --[[@type string, table]]

-- Type definitions are located in LibsIH.definition.lua (not packaged)

---@class LibsIHCore
local addon = LibStub('AceAddon-3.0'):NewAddon(addonName, 'AceEvent-3.0', 'AceTimer-3.0', 'AceHook-3.0')

-- Make addon globally accessible
root.Core = addon

---@class LibsIH.DB.Profile
local profile = {
	FilterGenericUse = false,
	FilterToys = true,
	FilterAppearance = true,
	FilterMounts = true,
	FilterRepGain = true,
	FilterCompanion = true,
	FilterCurios = true,
	FilterKnowledge = true,
	FilterContainers = true,
	CreatableItem = true,
	ShowGlow = true, -- Show animated blue-to-green glow
	ShowIndicator = true, -- Show static treasure map icon
	-- Animation Settings
	AnimationCycleTime = 0.5,
	TimeBetweenCycles = 0.10,
	AnimationUpdateInterval = 0.1,
	-- Bag System Selection
	BagSystem = 'auto' -- "auto", "baganator", "blizzard", "bagnon", "adibags"
}

-- Localization
local Localized = {
	deDE = {
		['Use: Teaches you how to summon this mount'] = 'Benutzen: Lehrt Euch, dieses Reittier herbeizurufen',
		['Use: Collect the appearance'] = 'Benutzen: Sammelt das Aussehen',
		['reputation with'] = 'Ruf bei',
		['reputation towards'] = 'Ruf bei'
	},
	esES = {
		['Use: Teaches you how to summon this mount'] = 'Uso: Te enseña a invocar esta montura',
		['Use: Collect the appearance'] = 'Uso: Recoge la apariencia',
		['reputation with'] = 'reputación con',
		['reputation towards'] = 'reputación hacia'
	},
    ruRU = {
	    ['Use: Teaches you how to summon this mount'] = 'Использование: Обучает призыву этого маунта',
	    ['Use: Collect the appearance'] = 'Использование: Собирает внешний вид',
	    ['reputation with'] = 'репутация с',
	    ['reputation towards'] = 'репутация к'
    },		
	frFR = {
		['Use: Teaches you how to summon this mount'] = 'Utilisation: Vous apprend à invoquer cette monture',
		['Use: Collect the appearance'] = "Utilisation: Collectionnez l'apparence",
		['reputation with'] = 'réputation auprès',
		['reputation towards'] = 'réputation envers'
	}
}

local Locale = GetLocale()
function GetLocaleString(key)
	if Localized[Locale] then
		return Localized[Locale][key]
	end
	return key
end

local REP_USE_TEXT = QUEST_REPUTATION_REWARD_TOOLTIP:match('%%d%s*(.-)%s*%%s') or GetLocaleString('reputation with')

-- SpartanUI Logger Integration
local logger = nil

-- Initialize SpartanUI Logger integration
local function InitializeSUILogger()
	if SUI and SUI.Logger and SUI.Logger.RegisterAddon then
		-- Register with SpartanUI Logger for proper external addon integration
		logger = SUI.Logger.RegisterAddon("Lib's - Item Highlighter")
		return true
	end
	return false
end

-- Logging function with SpartanUI integration
local function Log(msg, level)
	if logger then
		-- Use registered SpartanUI logger
		logger(tostring(msg), level or 'info')
	end
end

-- Export utilities
root.Log = Log
root.GetLocaleString = GetLocaleString
root.REP_USE_TEXT = REP_USE_TEXT

-- Tooltip for item scanning
local Tooltip = CreateFrame('GameTooltip', 'BagOpenableTooltip', nil, 'GameTooltipTemplate')

local SearchItems = {
	'Open the container',
	'Use: Open',
	'Right Click to Open',
	'Right click to open',
	'<Right Click to Open>',
	'<Right click to open>',
	ITEM_OPENABLE
}

-- Helper function to cache and return openable result
local function CacheOpenableResult(itemID, isOpenable)
	if itemID and addon.GlobalDB and addon.GlobalDB.itemCache then
		if isOpenable then
			addon.GlobalDB.itemCache.openable[itemID] = true
			Log('Cached item ' .. itemID .. ' as openable', 'debug')
		else
			addon.GlobalDB.itemCache.notOpenable[itemID] = true
			Log('Cached item ' .. itemID .. ' as not openable', 'debug')
		end
	end
	return isOpenable
end

local function CheckItem(itemDetails)
	if not itemDetails or not itemDetails.itemLink then
		return nil
	end

	local itemLink = itemDetails.itemLink
	local bagID, slotID = itemDetails.bagID, itemDetails.slotID

	-- Get itemID for caching
	local itemID = C_Item.GetItemInfoInstant(itemLink)
	if itemID and addon.GlobalDB and addon.GlobalDB.itemCache then
		-- Check cache first
		if addon.GlobalDB.itemCache.openable[itemID] then
			Log('Cache hit: Item ' .. itemID .. ' is openable', 'debug')
			return true
		elseif addon.GlobalDB.itemCache.notOpenable[itemID] then
			Log('Cache hit: Item ' .. itemID .. ' is not openable', 'debug')
			return false
		end
	end

	-- Quick check for common openable item types
	local _, _, _, _, _, itemType, itemSubType = C_Item.GetItemInfo(itemLink)
	local Consumable = itemType == 'Consumable' or itemSubType == 'Consumables'

	if Consumable and itemSubType and string.find(itemSubType, 'Curio') and addon.DB.FilterCurios then
		return CacheOpenableResult(itemID, true)
	end

	-- Use tooltip scanning for detailed analysis
	Tooltip:ClearLines()
	Tooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	if bagID and slotID then
		Tooltip:SetBagItem(bagID, slotID)
	else
		Tooltip:SetHyperlink(itemLink)
	end

	local numLines = Tooltip:NumLines()
	Log('Tooltip has ' .. numLines .. ' lines for item: ' .. itemLink, 'debug')

	for i = 1, numLines do
		local leftLine = _G['BagOpenableTooltipTextLeft' .. i]
		local rightLine = _G['BagOpenableTooltipTextRight' .. i]

		if leftLine then
			local LineText = leftLine:GetText()
			if LineText then
				-- Search for basic openable items
				for _, v in pairs(SearchItems) do
					if string.find(LineText, v) then
						return CacheOpenableResult(itemID, true)
					end
				end

				-- Check for containers (caches, chests, etc.)
				if
					addon.DB.FilterContainers and
						(string.find(LineText, 'Weekly cache') or string.find(LineText, 'Cache of') or string.find(LineText, 'Right [Cc]lick to open') or string.find(LineText, '<Right [Cc]lick to [Oo]pen>') or
							string.find(LineText, 'Contains'))
				 then
					Log('Found container with right click text: ' .. LineText)
					return CacheOpenableResult(itemID, true)
				end

				if addon.DB.FilterAppearance and (string.find(LineText, ITEM_COSMETIC_LEARN) or string.find(LineText, GetLocaleString('Use: Collect the appearance'))) then
					return CacheOpenableResult(itemID, true)
				end

				-- Remove (%s). from ITEM_CREATE_LOOT_SPEC_ITEM
				local CreateItemString = ITEM_CREATE_LOOT_SPEC_ITEM:gsub(' %(%%s%)%.', '')
				if
					addon.DB.CreatableItem and (string.find(LineText, CreateItemString) or string.find(LineText, 'Create a soulbound item for your class') or string.find(LineText, 'item appropriate for your class'))
				 then
					return CacheOpenableResult(itemID, true)
				end

				if LineText == LOCKED then
					return CacheOpenableResult(itemID, true)
				end

				if addon.DB.FilterToys and string.find(LineText, ITEM_TOY_ONUSE) then
					return CacheOpenableResult(itemID, true)
				end

				if addon.DB.FilterCompanion and string.find(LineText, 'companion') then
					return CacheOpenableResult(itemID, true)
				end

				if addon.DB.FilterKnowledge and (string.find(LineText, 'Knowledge') and string.find(LineText, 'Study to increase')) then
					return CacheOpenableResult(itemID, true)
				end

				if
					addon.DB.FilterRepGain and (string.find(LineText, REP_USE_TEXT) or string.find(LineText, GetLocaleString('reputation towards')) or string.find(LineText, GetLocaleString('reputation with'))) and
						string.find(LineText, ITEM_SPELL_TRIGGER_ONUSE)
				 then
					return CacheOpenableResult(itemID, true)
				end

				if addon.DB.FilterMounts and (string.find(LineText, GetLocaleString('Use: Teaches you how to summon this mount')) or string.find(LineText, 'Drakewatcher Manuscript')) then
					return CacheOpenableResult(itemID, true)
				end

				if addon.DB.FilterGenericUse and string.find(LineText, ITEM_SPELL_TRIGGER_ONUSE) then
					return CacheOpenableResult(itemID, true)
				end
			end
		end

		if rightLine then
			local RightLineText = rightLine:GetText()
			if RightLineText then
				-- Search right side text too
				for _, v in pairs(SearchItems) do
					if string.find(RightLineText, v) then
						return CacheOpenableResult(itemID, true)
					end
				end

				-- Check right side for containers
				if addon.DB.FilterContainers and (string.find(RightLineText, 'Right [Cc]lick to open') or string.find(RightLineText, '<Right [Cc]lick to [Oo]pen>')) then
					Log('Found container with right click text: ' .. RightLineText)
					return CacheOpenableResult(itemID, true)
				end
			end
		end
	end

	return CacheOpenableResult(itemID, false)
end

-- Export the item checking function
root.CheckItem = CheckItem

-- Bag system registry
local bagSystems = {}

function addon:RegisterBagSystem(name, integration)
	bagSystems[name] = integration
	Log('Registered bag system: ' .. name)
end

function addon:GetAllAvailableBagSystems()
	local availableSystems = {}

	Log('Scanning for all available bag systems...')

	-- Check all registered systems - integrate with everything that's available
	for name, integration in pairs(bagSystems) do
		if integration and integration.IsAvailable and integration:IsAvailable() then
			Log('Found available bag system: ' .. name)
			table.insert(availableSystems, {name = name, integration = integration})
		end
	end

	if #availableSystems > 0 then
		local systemNames = {}
		for _, system in ipairs(availableSystems) do
			table.insert(systemNames, system.name)
		end
		Log('Will integrate with all available systems: ' .. table.concat(systemNames, ', '))
	else
		Log('No bag systems detected')
	end

	return availableSystems
end

-- Legacy function for compatibility - now returns first available system or nil
function addon:GetActiveBagSystem()
	local systemName = self.DB.BagSystem

	if systemName == 'auto' then
		local availableSystems = self:GetAllAvailableBagSystems()
		return #availableSystems > 0 and availableSystems[1].integration or nil
	else
		-- Manual selection - respect user's choice for single system
		Log('Using manually selected bag system: ' .. systemName)
		return bagSystems[systemName]
	end
end

function addon:OnInitialize()
	-- Initialize SpartanUI Logger first
	InitializeSUILogger()

	Log('LibsIH core initializing...')
	if logger then
		Log('Registered with SpartanUI Logger system')
	end
	-- Setup DB with global cache
	---@class LibsIH.DB
	local defaults = {
		profile = profile,
		global = {
			itemCache = {
				openable = {}, -- itemID -> true for confirmed openable items
				notOpenable = {} -- itemID -> true for confirmed non-openable items
			}
		}
	}
	self.DataBase = LibStub('AceDB-3.0'):New('LibsIHDB', defaults, true) ---@type LibsIH.DB
	self.DB = self.DataBase.profile
	self.GlobalDB = self.DataBase.global
	Log('Database initialized with ShowGlow: ' .. tostring(self.DB.ShowGlow) .. ', ShowIndicator: ' .. tostring(self.DB.ShowIndicator))

	-- Setup options panel
	self:SetupOptions()
end

function addon:OnEnable()
	Log('LibsIH core enabling...')

	-- Store enabled systems for later cleanup
	self.enabledBagSystems = {}

	-- Enable all available bag systems
	local availableSystems = self:GetAllAvailableBagSystems()
	if #availableSystems > 0 then
		for _, systemData in ipairs(availableSystems) do
			local integration = systemData.integration
			local name = systemData.name

			Log('Enabling bag system: ' .. name)
			if integration.OnEnable then
				local success, error =
					pcall(
					function()
						integration:OnEnable()
					end
				)

				if success then
					table.insert(self.enabledBagSystems, integration)
					Log('Successfully enabled ' .. name .. ' integration')
				else
					Log('Failed to enable ' .. name .. ' integration: ' .. tostring(error), 'error')
				end
			else
				Log('Warning: ' .. name .. ' integration has no OnEnable method', 'warning')
			end
		end

		Log('Enabled ' .. #self.enabledBagSystems .. ' bag system integrations')
	else
		Log('No compatible bag systems found', 'warning')
	end
end

function addon:OnDisable()
	Log('LibsIH core disabling...')

	-- Stop global animation timer and cleanup all widgets
	root.Animation.StopGlobalTimer()
	root.Animation.CleanupAllWidgets()

	-- Disable all enabled bag systems
	if self.enabledBagSystems then
		for _, integration in ipairs(self.enabledBagSystems) do
			if integration.OnDisable then
				local success, error =
					pcall(
					function()
						integration:OnDisable()
					end
				)

				if not success then
					Log('Error disabling bag system integration: ' .. tostring(error), 'error')
				end
			end
		end
		Log('Disabled ' .. #self.enabledBagSystems .. ' bag system integrations')
		self.enabledBagSystems = {}
	end

	-- Cancel any running timers
	self:CancelAllTimers()
end

-- Options will be set up in a separate file
function addon:SetupOptions()
	-- This will be implemented in Core/Options.lua
end
