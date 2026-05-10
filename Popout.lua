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

local ROW_HEIGHT = 24
local ROW_WIDTH = 200
local MAX_ROWS = 30

local function makePreviewRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(ROW_WIDTH, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 8, -28 - (index - 1) * (ROW_HEIGHT + 2))

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 0, 0)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.name:SetWidth(ROW_WIDTH - 80)
  row.name:SetJustifyH("LEFT")

  row.delta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.delta:SetPoint("RIGHT", -4, 0)

  row.bestBorder = row:CreateTexture(nil, "BACKGROUND")
  row.bestBorder:SetAllPoints(row)
  row.bestBorder:SetColorTexture(1, 0.82, 0, 0.25)
  row.bestBorder:Hide()

  return row
end

function Popout:CreateFrame()
  frame = CreateFrame("Frame", "SlotPeekPopoutFrame", UIParent, "BackdropTemplate")
  frame:SetSize(ROW_WIDTH + 16, 40)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)  -- block mouse from reaching slot frames behind the popout
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

  frame.rows = {}
  for i = 1, MAX_ROWS do
    frame.rows[i] = makePreviewRow(frame, i)
    frame.rows[i]:Hide()
  end
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
local dismissTimer
function Popout:OnSlotEnter(slot)
  local invSlotID = SLOT_TO_INVSLOT[slot:GetName()]
  if not invSlotID then return end
  if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
  if hoverTimer then hoverTimer:Cancel() end
  local delay = (SlotPeek.db and SlotPeek.db.profile.hoverDelay) or 0.15
  hoverTimer = C_Timer.NewTimer(delay, function() self:Show(slot, invSlotID) end)
end

function Popout:OnSlotLeave(slot)
  if hoverTimer then hoverTimer:Cancel(); hoverTimer = nil end
  if dismissTimer then dismissTimer:Cancel() end
  dismissTimer = C_Timer.NewTimer(0.2, function()
    if not frame:IsMouseOver() then Popout:Hide() end
    dismissTimer = nil
  end)
end

function Popout:Show(slot, invSlotID)
  if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
  local cands = SlotPeek.BagIndex:GetCandidates(invSlotID)
  SlotPeek.BagIndex:SortByScore(cands)

  local equipped = GetInventoryItemLink("player", invSlotID)
  local equippedScore = equipped and SlotPeek.PawnAdapter:Score(equipped)

  for i, row in ipairs(frame.rows) do row:Hide() end

  local n = math.min(#cands, MAX_ROWS)
  for i = 1, n do
    local c = cands[i]
    local _, _, quality, _, _, _, _, _, _, icon = GetItemInfo(c.itemLink)
    local row = frame.rows[i]
    row.icon:SetTexture(icon or c.icon)
    local r, g, b = GetItemQualityColor(quality or 1)
    row.name:SetText(c.itemLink:match("%[(.-)%]") or "?")
    row.name:SetTextColor(r, g, b)

    local score = SlotPeek.PawnAdapter:Score(c.itemLink)
    if score and equippedScore and equippedScore > 0 then
      local pct = (score - equippedScore) / equippedScore * 100
      row.delta:SetText(("%+0.1f%%"):format(pct))
      if pct > 0 then row.delta:SetTextColor(0.4, 1, 0.4)
      elseif pct < 0 then row.delta:SetTextColor(1, 0.5, 0.5)
      else row.delta:SetTextColor(1, 1, 1) end
    elseif score then
      row.delta:SetText(tostring(math.floor(score)))
      row.delta:SetTextColor(1, 1, 1)
    else
      row.delta:SetText("…")
      row.delta:SetTextColor(0.7, 0.7, 0.7)
    end

    row.bestBorder:SetShown(i == 1 and n > 0)
    row:Show()
  end

  frame:SetHeight(28 + n * (ROW_HEIGHT + 2) + 8)
  frame.header:SetText(("%s — %d items"):format(
    slot:GetName():gsub("Character",""):gsub("Slot",""), #cands))

  frame:ClearAllPoints()
  if GameTooltip:IsShown() and GameTooltip:GetOwner() == slot then
    frame:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -2)
  else
    frame:SetPoint("TOPLEFT", slot, "TOPRIGHT", 8, 0)
  end
  frame:Show()
end

function Popout:Hide()
  frame:Hide()
end

function Popout:OnEnable()
  self:CreateFrame()
  self:Attach()
end
