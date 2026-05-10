local SlotPeek = SlotPeek
local Popout = {}
SlotPeek.Popout = Popout

local frame
local SLOT_FRAMES = {
  CharacterHeadSlot, CharacterNeckSlot, CharacterShoulderSlot, CharacterBackSlot,
  CharacterChestSlot, CharacterWristSlot, CharacterHandsSlot, CharacterWaistSlot,
  CharacterLegsSlot, CharacterFeetSlot, CharacterFinger0Slot, CharacterFinger1Slot,
  CharacterTrinket0Slot, CharacterTrinket1Slot, CharacterMainHandSlot,
  CharacterSecondaryHandSlot, CharacterRangedSlot,
}

local SLOT_TO_INVSLOT = {
  CharacterHeadSlot = INVSLOT_HEAD,
  CharacterNeckSlot = INVSLOT_NECK,
  CharacterShoulderSlot = INVSLOT_SHOULDER,
  CharacterBackSlot = INVSLOT_BACK,
  CharacterChestSlot = INVSLOT_CHEST,
  CharacterWristSlot = INVSLOT_WRIST,
  CharacterHandsSlot = INVSLOT_HAND,
  CharacterWaistSlot = INVSLOT_WAIST,
  CharacterLegsSlot = INVSLOT_LEGS,
  CharacterFeetSlot = INVSLOT_FEET,
  CharacterFinger0Slot = INVSLOT_FINGER1,
  CharacterFinger1Slot = INVSLOT_FINGER2,
  CharacterTrinket0Slot = INVSLOT_TRINKET1,
  CharacterTrinket1Slot = INVSLOT_TRINKET2,
  CharacterMainHandSlot = INVSLOT_MAINHAND,
  CharacterSecondaryHandSlot = INVSLOT_OFFHAND,
  CharacterRangedSlot = INVSLOT_RANGED,
}

function Popout:CreateFrame()
  frame = CreateFrame("Frame", "SlotPeekPopoutFrame", UIParent, "BackdropTemplate")
  frame:SetSize(220, 40)
  frame:SetFrameStrata("DIALOG")
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
  end
  frame:Hide()
  self.frame = frame

  frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.header:SetPoint("TOPLEFT", 8, -8)
  frame.header:SetText("(no items)")
end

function Popout:Attach()
  for _, slot in ipairs(SLOT_FRAMES) do
    if slot then
      slot:HookScript("OnEnter", function(s) self:OnSlotEnter(s) end)
      slot:HookScript("OnLeave", function(s) self:OnSlotLeave(s) end)
    end
  end
end

local hoverTimer
function Popout:OnSlotEnter(slot)
  local invSlotID = SLOT_TO_INVSLOT[slot:GetName()]
  if not invSlotID then return end
  if hoverTimer then hoverTimer:Cancel() end
  local delay = (SlotPeek.db and SlotPeek.db.profile.hoverDelay) or 0.15
  hoverTimer = C_Timer.NewTimer(delay, function() self:Show(slot, invSlotID) end)
end

function Popout:OnSlotLeave(slot)
  if hoverTimer then hoverTimer:Cancel(); hoverTimer = nil end
  C_Timer.After(0.2, function() if not frame:IsMouseOver() then self:Hide() end end)
end

function Popout:Show(slot, invSlotID)
  local cands = SlotPeek.BagIndex:GetCandidates(invSlotID)
  SlotPeek.BagIndex:SortByScore(cands)
  frame.header:SetText(("%s — %d items"):format(slot:GetName():gsub("Character",""):gsub("Slot",""), #cands))
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", slot, "TOPRIGHT", 8, 0)
  frame:Show()
end

function Popout:Hide()
  frame:Hide()
end

function Popout:OnEnable()
  self:CreateFrame()
  self:Attach()
end
