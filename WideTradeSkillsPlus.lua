-- Cache global functions for performance and clarity
local tinsert = table.insert
local _G = _G
local GetSpellInfo = GetSpellInfo
local GetNumSkillLines = GetNumSkillLines
local GetSkillLineInfo = GetSkillLineInfo
local IsAddOnLoaded = IsAddOnLoaded
local UnitAffectingCombat = UnitAffectingCombat
local IsCurrentSpell = IsCurrentSpell
local IsPassiveSpell = IsPassiveSpell
local CloseTradeSkill = CloseTradeSkill
local CloseCraft = CloseCraft
local UpdateUIPanelPositions = UpdateUIPanelPositions
local hooksecurefunc = hooksecurefunc
local FauxScrollFrame_GetOffset = FauxScrollFrame_GetOffset
local GetItemQualityColor = GetItemQualityColor
local GetItemInfo = GetItemInfo

-- Initialization variables and constants
local numTabs, craftTabs = 0, nil
local skinUI, loadedUI, delay
local DISPLAY_SIZE = 22  -- Fixed number of recipe buttons to display

------------------------------------------------------------
-- Database and UI Skin Initialization
------------------------------------------------------------
local function initDB()
  WTSPlusDB = WTSPlusDB or {
    Tabs = {},  -- Holds enabled status for profession tabs (all enabled by default)
  }

  if IsAddOnLoaded("Aurora") then
    skinUI = "Aurora"
    loadedUI = unpack(Aurora)
  elseif IsAddOnLoaded("ElvUI") then
    skinUI = "ElvUI"
    loadedUI = unpack(ElvUI):GetModule("Skins")
  end
end

------------------------------------------------------------
-- Main Event Frame
------------------------------------------------------------
local f = CreateFrame("Frame", "WideTradeSkillsPlus")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("SKILL_LINES_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")

------------------------------------------------------------
-- Profession Spell Data (Cached)
------------------------------------------------------------
local profMining   = GetSpellInfo(2576)
local profSmelting = GetSpellInfo(2656)
local profSkinning = GetSpellInfo(8613)
local profEnchant  = GetSpellInfo(7412)
local profFishing  = GetSpellInfo(7731)
local profCooking  = GetSpellInfo(3102)

------------------------------------------------------------
-- Get Player Professions
------------------------------------------------------------
local function getProfessions()
  local section, mainProfs, subProfs = 0, {}, {}
  for i = 1, GetNumSkillLines() do
    local name, isHeader = GetSkillLineInfo(i)
    if isHeader then
      section = section + 1
    elseif section == 2 or section == 3 then
      if name ~= profSkinning and name ~= profFishing then
        if name == profMining then name = profSmelting end
        if name == "가죽 세공" then name = "가죽세공" end
        local id = select(7, GetSpellInfo(name))
        if id and not IsPassiveSpell(id) then
          tinsert(mainProfs, id)
          if name == profEnchant then
            tinsert(subProfs, 13262) -- Disenchant
          elseif name == profCooking then
            tinsert(subProfs, 818) -- Campfire
          end
        end
      end
    end
  end
  return mainProfs, subProfs
end

------------------------------------------------------------
-- Tab Button Management
------------------------------------------------------------
-- Update tab state (always show; no toggling options)
local function updateTabState(self)
  local frame = self:GetParent()
  -- For the CraftFrame, only show the tab if the displayed skill is Enchanting
  if frame == CraftFrame and not UnitAffectingCombat("player") then
    if not IsCurrentSpell(profEnchant) then
      self:Hide()
      return
    else
      self:Show()
    end
  end

  if self.id and IsCurrentSpell(self.id) then
    self:SetChecked(true)
    self:RegisterForClicks()
  else
    self:SetChecked(false)
    self:RegisterForClicks("AnyDown")
  end
end

-- Create and initialize a tab button for a given profession
local function addTab(id, index, isSub, frame)
  local name, _, icon = GetSpellInfo(id)
  if not (name and icon) then return end

  local tabName = "WTSPlusTab-" .. frame:GetName() .. "_" .. index
  local tab = _G[tabName] or CreateFrame("CheckButton", tabName, frame, "SpellBookSkillLineTabTemplate, SecureActionButtonTemplate")
  tab:SetScript("OnEvent", updateTabState)
  tab:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
  tab.id = id
  tab.isSub = isSub
  tab.tooltip = name
  tab:SetNormalTexture(icon)
  tab:SetAttribute("type", "spell")
  tab:SetAttribute("spell", id)
  updateTabState(tab)

  if skinUI and not tab.skinned then
    local checkedTexture
    if skinUI == "Aurora" then
      checkedTexture = "Interface\\AddOns\\Aurora\\media\\CheckButtonHilight"
    elseif skinUI == "ElvUI" then
      checkedTexture = tab:CreateTexture(nil, "HIGHLIGHT")
      checkedTexture:SetColorTexture(1, 1, 1, 0.3)
      checkedTexture:SetInside()
      tab:SetHighlightTexture("")
    end
    tab:SetCheckedTexture(checkedTexture)
    tab:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tab:GetRegions():Hide()
    tab.skinned = true
  end
end

-- Remove all tab buttons from both TradeSkillFrame and CraftFrame
local function removeTabs()
  for _, frame in pairs({TradeSkillFrame, CraftFrame}) do
    for i = 1, numTabs do
      local tab = _G["WTSPlusTab-" .. frame:GetName() .. "_" .. i]
      if tab and tab:IsShown() then
        tab:UnregisterEvent("CURRENT_SPELL_CAST_CHANGED")
        tab:Hide()
      end
    end
  end
end

-- Sort and reposition tabs so that primary (main) tabs are at the top
-- and secondary (sub) tabs are at the bottom. We rely on Blizzard's
-- default UI for the actual frame location (no manual SetPoint).
local function sortTabs()
  local horizontalOffset = skinUI and -33 or -34
  local verticalSpacing = 50
  local bottomMargin = 100

  local mainTabs, subTabs = getProfessions()
  local primaryCount = #mainTabs

  for _, frame in pairs({TradeSkillFrame, CraftFrame}) do
    -- Position primary tabs (top-down)
    local primaryIndex = 1
    for i = 1, primaryCount do
      local tab = _G["WTSPlusTab-" .. frame:GetName() .. "_" .. i]
      if tab then
        local yOffset = -verticalSpacing * primaryIndex
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", horizontalOffset, yOffset)
        tab:Show()
        primaryIndex = primaryIndex + 1
      end
    end

    -- Position secondary tabs (bottom-up)
    local subIndex = 1
    for i = primaryCount + 1, primaryCount + #subTabs do
      local tab = _G["WTSPlusTab-" .. frame:GetName() .. "_" .. i]
      if tab then
        local yOffset = bottomMargin + (verticalSpacing * (subIndex - 1))
        tab:ClearAllPoints()
        tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", horizontalOffset, yOffset)
        tab:Show()
        subIndex = subIndex + 1
      end
    end
  end
end

-- Update the profession tabs based on current professions (all enabled)
local function updateTabs(init)
  local mainTabs, subTabs = getProfessions()
  if init and not WTSPlusDB.Panel and mainTabs[1] then
    WTSPlusDB.Panel = GetSpellInfo(mainTabs[1])
  end

  local _, playerClass = UnitClass("player")
  if playerClass == "ROGUE" and IsUsableSpell(1804) then
    tinsert(subTabs, 1804)  -- Include PickLock for rogues
  end

  local totalTabs = #mainTabs + #subTabs
  numTabs = totalTabs

  removeTabs()
  for i = 1, numTabs do
    local id = mainTabs[i] or subTabs[i - #mainTabs]
    addTab(id, i, mainTabs[i] and 0 or 1, TradeSkillFrame)
    if CraftFrame then
      addTab(id, i, mainTabs[i] and 0 or 1, CraftFrame)
      craftTabs = true
    end
  end
  sortTabs()
end

------------------------------------------------------------
-- Frame Layout and Recipe Refresh
------------------------------------------------------------
local function updateSize(frame)
  -- If the displayed skill is Beast Training, skip custom wide layout
  if frame == "TradeSkill"
     and GetTradeSkillDisplaySkillLine
     and GetTradeSkillDisplaySkillLine() == "Beast Training" then
    return
  end

  local mainFrame = _G[frame .. "Frame"]
  mainFrame:SetWidth(714)
  mainFrame:SetHeight(skinUI and 512 or 487)

  local detailScroll = _G[frame .. "DetailScrollFrame"]
  detailScroll:ClearAllPoints()
  detailScroll:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 362, -92)
  detailScroll:SetSize(296, 332)
  _G[frame .. "DetailScrollFrameTop"]:SetAlpha(0)
  _G[frame .. "DetailScrollFrameBottom"]:SetAlpha(0)

  local listScroll = _G[frame .. "ListScrollFrame"]
  listScroll:ClearAllPoints()
  if frame == "Craft" then
    listScroll:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 23.8, -74.3)
    listScroll:SetSize(296, 357)
  else
    listScroll:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 23.8, -99)
    listScroll:SetSize(296, 332)
  end

  if not IsAddOnLoaded("Aurora") and not IsAddOnLoaded("ElvUI") then
    local scrollFix = listScroll:CreateTexture(nil, "BACKGROUND")
    scrollFix:SetPoint("TOPRIGHT", listScroll, "TOPRIGHT", 28.9, -110)
    scrollFix:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-ScrollBar")
    scrollFix:SetTexCoord(0, 0.5, 0.2, 0.9)
    scrollFix:SetSize(32, 0)
  end

  local regions = { mainFrame:GetRegions() }
  if not IsAddOnLoaded("Aurora") and not IsAddOnLoaded("ElvUI") then
    regions[2]:SetTexture("Interface\\QuestFrame\\UI-QuestLogDualPane-Left")
    regions[2]:SetSize(512, 512)

    regions[3]:ClearAllPoints()
    regions[3]:SetPoint("TOPLEFT", regions[2], "TOPRIGHT")
    regions[3]:SetTexture("Interface\\QuestFrame\\UI-QuestLogDualPane-Right")
    regions[3]:SetSize(256, 512)

    regions[4]:Hide()
    regions[5]:Hide()
  end
  regions[9]:Hide()
  regions[10]:Hide()

  if not IsAddOnLoaded("Aurora") and not IsAddOnLoaded("ElvUI") then
    local recipeInset = mainFrame:CreateTexture(nil, "ARTWORK")
    recipeInset:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 16.3, -72)
    recipeInset:SetTexture("Interface\\RaidFrame\\UI-RaidFrame-GroupBg")
    recipeInset:SetSize(326.5, 360.8)

    local detailsInset = mainFrame:CreateTexture(nil, "ARTWORK")
    detailsInset:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 349, -73)
    detailsInset:SetAtlas("tradeskill-background-recipe")
    detailsInset:SetSize(324, 339)
  end

  _G[frame .. "ExpandTabLeft"]:Hide()

  local cancelButton = _G[frame .. "CancelButton"]
  cancelButton:ClearAllPoints()
  cancelButton:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -40, skinUI and 79 or 54)
  local createButton = _G[frame .. "CreateButton"]
  createButton:ClearAllPoints()
  createButton:SetPoint("RIGHT", cancelButton, "LEFT", -1, 0)

  if frame == "Craft" then
    CraftFramePointsLabel:ClearAllPoints()
    CraftFramePointsLabel:SetPoint("RIGHT", CraftCreateButton, "LEFT", -55, 0)
    CraftFramePointsText:ClearAllPoints()
    CraftFramePointsText:SetPoint("LEFT", CraftFramePointsLabel, "RIGHT", 5, 0)
  end

  if frame == "TradeSkill" then
    TradeSkillInvSlotDropdown:ClearAllPoints()
    TradeSkillInvSlotDropdown:SetPoint("TOPLEFT", TradeSkillFrame, "TOPLEFT", 200, -72)
    TradeSkillSubClassDropdown:ClearAllPoints()
    TradeSkillSubClassDropdown:SetPoint("TOPRIGHT", TradeSkillInvSlotDropdown, "TOPLEFT", -6, 0)
  end

  local skillButton
  if frame == "Craft" then
    skillButton = "Craft"
    CRAFTS_DISPLAYED = DISPLAY_SIZE
  else
    skillButton = "TradeSkillSkill"
    TRADE_SKILLS_DISPLAYED = DISPLAY_SIZE
  end

  for i = 1, DISPLAY_SIZE do
    local button = _G[skillButton .. i] or CreateFrame("Button", skillButton .. i, mainFrame, skillButton .. "ButtonTemplate")
    if i > 1 then
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", _G[skillButton .. (i - 1)], "BOTTOMLEFT", 0, 1)
    end
  end
end

------------------------------------------------------------
-- Refresh Recipe Display (Always show recipe level)
------------------------------------------------------------
local function refreshRecipes(frame)
  -- If Beast Training, skip
  if frame == "TradeSkill"
     and GetTradeSkillDisplaySkillLine
     and GetTradeSkillDisplaySkillLine() == "Beast Training" then
    return
  end

  local function hookFrame()
    if not frame or not frame:IsShown() then return end

    local skillButton, scrollFrame, getSkillInfo
    if frame == TradeSkillFrame then
      skillButton = "TradeSkillSkill"
      scrollFrame = TradeSkillListScrollFrame
      getSkillInfo = GetTradeSkillInfo
    elseif frame == CraftFrame then
      skillButton = "Craft"
      scrollFrame = CraftListScrollFrame
      getSkillInfo = GetCraftInfo
    end

    for i = 1, DISPLAY_SIZE do
      local button = _G[skillButton .. i]
      if button then
        if not button.WTSPlusLevel then
          button.WTSPlusLevel = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
          button.WTSPlusLevel:SetPoint("RIGHT", button, "LEFT", 20, 2)
        end

        local offset = FauxScrollFrame_GetOffset(scrollFrame)
        local index = i + offset
        local recipe, hdr, quality, quantity, _, _, level = getSkillInfo(index)
        if recipe and level then
          if level > 1 then
            button.WTSPlusLevel:SetText(level)
            button.WTSPlusLevel:SetTextColor(GetItemQualityColor(1, 1, 1))
          else
            button.WTSPlusLevel:SetText("")
          end
          if not ClassicProfessionFilterSearchBoxMixIn then
            if quantity == 0 then
              button:SetText("      " .. recipe)
            else
              button:SetText("      " .. recipe .. " [" .. quantity .. "]")
            end
          end
        else
          button.WTSPlusLevel:SetText("")
        end
      end
    end
  end
  hooksecurefunc(frame:GetName() .. "_Update", hookFrame)
end

------------------------------------------------------------
-- Panel Switching Handler
------------------------------------------------------------
local function switchPanel(self)
  local frameName = self:GetName()
  if frameName == "CraftFrame" and CraftFrame:IsShown() then
    CloseTradeSkill()
  else
    CloseCraft()
  end
  -- No custom SetPoint calls here; let Blizzard handle it
end

------------------------------------------------------------
-- Main Event Handler
------------------------------------------------------------
f:SetScript("OnEvent", function(self, event, arg1)
  if event == "PLAYER_LOGIN" then
    initDB()
    -- We do NOT manually position frames here; we let the default UI handle it
    updateTabs(true)
    updateSize("TradeSkill")
    refreshRecipes(TradeSkillFrame)

  elseif event == "ADDON_LOADED" and arg1 == "Blizzard_CraftUI" then
    if UnitAffectingCombat("player") then
      delay = true
    else
      updateTabs()
    end
    -- Again, no manual SetPoint
    updateSize("Craft")
    refreshRecipes(CraftFrame)
    CraftFrame:HookScript("OnShow", switchPanel)
    TradeSkillFrame:HookScript("OnShow", switchPanel)
    f:UnregisterEvent("ADDON_LOADED")

  elseif event == "SKILL_LINES_CHANGED" then
    if numTabs > 0 then
      if UnitAffectingCombat("player") then
        delay = true
      else
        updateTabs()
      end
    end

  elseif event == "PLAYER_REGEN_ENABLED" and delay then
    updateTabs()
    delay = false
  end
end)
