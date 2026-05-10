local SlotPeek = SlotPeek
local BagIndex = {}
SlotPeek.BagIndex = BagIndex

local SLOT_FITS = {
  [INVSLOT_HEAD]      = { INVTYPE_HEAD = true },
  [INVSLOT_NECK]      = { INVTYPE_NECK = true },
  [INVSLOT_SHOULDER]  = { INVTYPE_SHOULDER = true },
  [INVSLOT_CHEST]     = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
  [INVSLOT_WAIST]     = { INVTYPE_WAIST = true },
  [INVSLOT_LEGS]      = { INVTYPE_LEGS = true },
  [INVSLOT_FEET]      = { INVTYPE_FEET = true },
  [INVSLOT_WRIST]     = { INVTYPE_WRIST = true },
  [INVSLOT_HAND]      = { INVTYPE_HAND = true },
  [INVSLOT_FINGER1]   = { INVTYPE_FINGER = true },
  [INVSLOT_FINGER2]   = { INVTYPE_FINGER = true },
  [INVSLOT_TRINKET1]  = { INVTYPE_TRINKET = true },
  [INVSLOT_TRINKET2]  = { INVTYPE_TRINKET = true },
  [INVSLOT_BACK]      = { INVTYPE_CLOAK = true },
  [INVSLOT_MAINHAND]  = { INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPON = true },
  [INVSLOT_OFFHAND]   = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true },
  [INVSLOT_RANGED]    = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true },
}

function BagIndex:FitsSlot(invType, invSlotID)
  local set = SLOT_FITS[invSlotID]
  return set and set[invType] == true or false
end

function BagIndex:ScanBags()
  local result = {}
  for bag = 0, NUM_BAG_SLOTS do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink then
        table.insert(result, {
          itemLink = info.hyperlink,
          bag = bag,
          slot = slot,
          itemID = info.itemID,
          icon = info.iconFileID,
          source = "bags",
        })
      end
    end
  end
  return result
end

local CLASS_ARMOR = {
  WARRIOR = { Cloth = 0, Leather = 0, Mail = 40, Plate = 40 },
  PALADIN = { Cloth = 0, Leather = 0, Mail = 40, Plate = 40 },
  HUNTER  = { Cloth = 0, Leather = 0, Mail = 40 },
  ROGUE   = { Cloth = 0, Leather = 0 },
  PRIEST  = { Cloth = 0 },
  SHAMAN  = { Cloth = 0, Leather = 0, Mail = 40 },
  MAGE    = { Cloth = 0 },
  WARLOCK = { Cloth = 0 },
  DRUID   = { Cloth = 0, Leather = 0 },
}

local CLASS_WEAPON = {} -- populated below

local scanTip = CreateFrame("GameTooltip", "SlotPeekScanTip", UIParent, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")
local usableCache = {}

local function scanClassRestriction(itemLink)
  scanTip:ClearLines()
  scanTip:SetHyperlink(itemLink)
  local n = scanTip:NumLines()
  local prefix = ITEM_CLASSES_ALLOWED:gsub("%%s.*", "")
  for i = 2, n do
    local left = _G["SlotPeekScanTipTextLeft" .. i]
    local text = left and left:GetText()
    if text and text:find(prefix, 1, true) then
      return text:sub(#prefix + 1)
    end
  end
  return nil
end

function BagIndex:IsUsable(itemLink)
  local itemID = (GetItemInfoInstant and GetItemInfoInstant(itemLink)) or nil
  if itemID and usableCache[itemID] ~= nil then return usableCache[itemID] end

  local _, _, _, _, _, _, _, _, equipLoc, _, _, classID, subclassID = GetItemInfo(itemLink)
  if not equipLoc then return true end

  local _, playerClass = UnitClass("player")

  -- class restriction line
  local restrictedTo = scanClassRestriction(itemLink)
  if restrictedTo then
    local localizedClass = LOCALIZED_CLASS_NAMES_MALE[playerClass] or playerClass
    if not restrictedTo:find(localizedClass, 1, true) then
      if itemID then usableCache[itemID] = false end
      return false
    end
  end

  -- armor proficiency (classID 4 = Armor in BCC)
  if classID == 4 then
    local subTypeName = select(7, GetItemInfo(itemLink)) -- subType localized; use API constant
    -- subclassID for armor: 1=Cloth, 2=Leather, 3=Mail, 4=Plate
    local armorMap = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
    local needed = armorMap[subclassID]
    if needed then
      local prof = CLASS_ARMOR[playerClass]
      if not prof or prof[needed] == nil then
        if itemID then usableCache[itemID] = false end
        return false
      end
      -- level gate
      local minLevel = prof[needed]
      if minLevel and UnitLevel("player") < minLevel then
        -- character will eventually learn it; treat as usable (aspirational gear)
      end
    end
  end

  if itemID then usableCache[itemID] = true end
  return true
end
