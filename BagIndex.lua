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
