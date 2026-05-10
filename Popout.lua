local SlotPeek = SlotPeek
local Popout = {}
SlotPeek.Popout = Popout

local frame
local equippedTip
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

  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    if not self.itemLink then return end
    -- 1. Keep equipped tooltip visible on the slot
    if Popout._currentSlot and Popout._currentInvSlot then
      equippedTip:SetOwner(Popout._currentSlot, "ANCHOR_RIGHT")
      equippedTip:SetInventoryItem("player", Popout._currentInvSlot)
      equippedTip:Show()
    end
    -- 2. Show candidate tooltip via GameTooltip, anchored to right of popout
    --    (using GameTooltip lets Pawn's hooks fire so its values appear)
    GameTooltip:SetOwner(parent, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
    GameTooltip:SetHyperlink(self.itemLink)
    GameTooltip:Show()
    -- 3. Cancel any pending dismiss
    if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
    -- 4. Preview the item on the character model
    if CharacterModelFrame then
      CharacterModelFrame:TryOn(self.itemLink)
    end
  end)
  row:SetScript("OnLeave", function(self)
    -- Hide candidate tooltip; keep equipped tooltip
    GameTooltip:Hide()
    Popout:RevertModel()
  end)

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

  equippedTip = CreateFrame("GameTooltip", "SlotPeekEquippedTip", UIParent, "GameTooltipTemplate")

  frame:SetScript("OnEnter", function()
    if Popout._currentSlot and Popout._currentInvSlot then
      equippedTip:SetOwner(Popout._currentSlot, "ANCHOR_RIGHT")
      equippedTip:SetInventoryItem("player", Popout._currentInvSlot)
      equippedTip:Show()
    end
    if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
  end)

  frame:SetScript("OnLeave", function()
    -- schedule dismiss if cursor truly left popout
    if dismissTimer then dismissTimer:Cancel() end
    dismissTimer = C_Timer.NewTimer(0.2, function()
      if not frame:IsMouseOver() then Popout:Hide() end
      dismissTimer = nil
    end)
  end)
end

function Popout:Attach()
  for _, slot in ipairs(SLOT_FRAMES) do
    if slot then
      slot:HookScript("OnEnter", function(s) self:OnSlotEnter(s) end)
      slot:HookScript("OnLeave", function(s) self:OnSlotLeave(s) end)
    end
  end
  -- Dismiss the popout if the character pane closes while the cursor is on it.
  -- (Without this, hidden slots can't fire OnLeave, so the popout would persist.)
  if CharacterFrame then
    CharacterFrame:HookScript("OnHide", function() self:Hide() end)
  end
end

local hoverTimer
local dismissTimer
function Popout:OnSlotEnter(slot)
  local invSlotID = SLOT_TO_INVSLOT[slot:GetName()]
  if not invSlotID then return end
  if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
  if hoverTimer then hoverTimer:Cancel() end
  -- Hide our equipped tooltip when cursor returns to a slot — Blizzard's
  -- standard tooltip takes over.
  if equippedTip then equippedTip:Hide() end
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
  -- Hide stale equipped tooltip from a previous slot before re-showing.
  if equippedTip then equippedTip:Hide() end
  Popout._currentSlot = slot
  Popout._currentInvSlot = invSlotID
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
    elseif score and score ~= 0 then
      row.delta:SetText(tostring(math.floor(score)))
      row.delta:SetTextColor(1, 1, 1)
    elseif score then
      -- score returned 0 — Pawn doesn't value this item type for the active scale
      row.delta:SetText("—")
      row.delta:SetTextColor(0.7, 0.7, 0.7)
    else
      row.delta:SetText("…")
      row.delta:SetTextColor(0.7, 0.7, 0.7)
    end

    row.bestBorder:SetShown(i == 1 and n > 0)
    row.itemLink = c.itemLink
    row:Show()
  end

  frame:SetHeight(28 + n * (ROW_HEIGHT + 2) + 8)
  frame.header:SetText(("%s — %d items"):format(
    slot:GetName():gsub("Character",""):gsub("Slot",""), #cands))

  frame:ClearAllPoints()
  if GameTooltip:IsShown() and GameTooltip:GetOwner() == slot then
    -- Snapshot tooltip's screen position; anchor to UIParent at those absolute
    -- coords so the popout doesn't follow GameTooltip when it moves to other
    -- frames (e.g. a bag item the cursor wanders to).
    local left = GameTooltip:GetLeft()
    local bottom = GameTooltip:GetBottom()
    if left and bottom then
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, bottom - 2)
    else
      frame:SetPoint("TOPLEFT", slot, "TOPRIGHT", 8, 0)
    end
  else
    frame:SetPoint("TOPLEFT", slot, "TOPRIGHT", 8, 0)
  end
  frame:Show()
end

function Popout:RevertModel()
  if CharacterModelFrame then
    CharacterModelFrame:Undress()
    CharacterModelFrame:Dress()
  end
end

function Popout:Hide()
  self:RevertModel()
  if equippedTip then equippedTip:Hide() end
  if Popout._currentSlot and GameTooltip:GetOwner() == frame then
    GameTooltip:Hide()
  end
  Popout._currentSlot = nil
  Popout._currentInvSlot = nil
  frame:Hide()
end

function Popout:OnEnable()
  self:CreateFrame()
  self:Attach()
  SlotPeek:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() self:RevertModel() end)
end
