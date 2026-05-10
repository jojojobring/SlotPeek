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
local ROW_WIDTH = 100
local MAX_ROWS = 30

-- Timer state — declared early so closures inside makePreviewRow / CreateFrame
-- capture these as proper file-locals (not globals).
local hoverTimer
local dismissTimer

-- Combat-safe model preview helpers.
-- Both helpers no-op when InCombatLockdown() is true so they never trigger
-- "Interface action failed because of an AddOn" during combat.
-- `frame` is nil at define-time but captured by reference — safe because
-- closures are only called after Popout:CreateFrame() has run.
local function showPreview(itemLink)
  if InCombatLockdown() then return end
  if not frame or not frame.previewModel then return end
  if CharacterModelFrame then CharacterModelFrame:Hide() end
  frame.previewModel:Show()
  frame.previewModel:SetUnit("player")
  frame.previewModel:TryOn(itemLink)
end

local function hidePreview()
  if InCombatLockdown() then return end
  if frame and frame.previewModel then frame.previewModel:Hide() end
  if CharacterModelFrame then CharacterModelFrame:Show() end
end

local function makePreviewRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(ROW_WIDTH, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 8, -28 - (index - 1) * (ROW_HEIGHT + 2))

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 0, 0)

  -- Rarity-colored border around the icon (set by Show via vertex color).
  row.iconBorder = row:CreateTexture(nil, "OVERLAY")
  row.iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
  row.iconBorder:SetSize(22, 22)
  row.iconBorder:SetPoint("CENTER", row.icon, "CENTER")

  row.delta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.delta:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)

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
    -- 4. Swap the live model for our preview (3D models don't occlude via
    --    frame strata, so we hide the original to avoid double-rendering).
    showPreview(self.itemLink)
  end)
  row:SetScript("OnLeave", function(self)
    -- Hide candidate tooltip; keep equipped tooltip
    GameTooltip:Hide()
    -- Restore the live model
    hidePreview()
    -- Schedule dismiss in case cursor goes directly off-popout from this row.
    if dismissTimer then dismissTimer:Cancel() end
    dismissTimer = C_Timer.NewTimer(0.2, function()
      if frame:IsShown() and not frame:IsMouseOver() then Popout:Hide() end
      dismissTimer = nil
    end)
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

  frame.combatBadge = frame:CreateFontString(nil, "OVERLAY", "GameFontRed")
  frame.combatBadge:SetPoint("TOPRIGHT", -8, -8)
  frame.combatBadge:SetText("[combat]")
  frame.combatBadge:Hide()

  frame.rows = {}
  for i = 1, MAX_ROWS do
    frame.rows[i] = makePreviewRow(frame, i)
    frame.rows[i]:Hide()
  end

  frame.divider = frame:CreateTexture(nil, "OVERLAY")
  frame.divider:SetColorTexture(0.5, 0.5, 0.5, 0.5)
  frame.divider:SetHeight(1)
  frame.divider:Hide()

  equippedTip = CreateFrame("GameTooltip", "SlotPeekEquippedTip", UIParent, "GameTooltipTemplate")

  -- BCC's CharacterModelFrame is a PlayerModel, not a DressUpModel — it has
  -- no TryOn method. Overlay our own DressUpModel at the same position so we
  -- can preview items. It's hidden by default; shown only on row hover.
  if CharacterModelFrame then
    local parent = CharacterModelFrame:GetParent() or PaperDollFrame
    frame.previewModel = CreateFrame("DressUpModel", "SlotPeekPreviewModel", parent)
    frame.previewModel:SetAllPoints(CharacterModelFrame)
    frame.previewModel:SetFrameStrata(CharacterModelFrame:GetFrameStrata())
    frame.previewModel:SetFrameLevel(CharacterModelFrame:GetFrameLevel() + 1)
    -- Pre-initialize the model so first TryOn doesn't race against load.
    frame.previewModel:SetUnit("player")
    frame.previewModel:Hide()
  end

  frame:SetScript("OnEnter", function()
    if Popout._currentSlot and Popout._currentInvSlot then
      equippedTip:SetOwner(Popout._currentSlot, "ANCHOR_RIGHT")
      equippedTip:SetInventoryItem("player", Popout._currentInvSlot)
      equippedTip:Show()
    end
    if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
  end)

  frame:SetScript("OnLeave", function()
    if dismissTimer then dismissTimer:Cancel() end
    dismissTimer = C_Timer.NewTimer(0.2, function()
      if frame:IsShown() and not frame:IsMouseOver() then Popout:Hide() end
      dismissTimer = nil
    end)
  end)

  -- Secure overlay pool -------------------------------------------------
  -- clickContainer is parented to UIParent, NOT frame. CRITICAL: we must
  -- not anchor any secure frame to a non-secure one — in BCC, doing so
  -- propagates protected status up the anchor chain (secure-anchored-to-X
  -- protects X, and X's parent inherits). So instead of
  -- clickContainer:SetAllPoints(frame), we sync the container's position
  -- to UIParent screen-coords in Popout:Show via RunSafe.
  -- Likewise, clickRows are anchored internally within clickContainer
  -- (secure → secure, fine), NOT to frame.rows[i] (which would taint frame).
  frame.clickContainer = CreateFrame("Frame", nil, UIParent)
  frame.clickContainer:SetFrameStrata(frame:GetFrameStrata())
  frame.clickContainer:SetSize(ROW_WIDTH + 16, 40)
  frame.clickContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame.clickContainer:Hide()

  frame.clickRows = {}
  for i = 1, MAX_ROWS do
    local clickRow = CreateFrame("Button", "SlotPeekClickRow" .. i,
                                 frame.clickContainer, "SecureActionButtonTemplate")
    -- Match the preview-row layout (see makePreviewRow line ~67) so the
    -- secure overlay lines up exactly with the visible preview rows.
    clickRow:SetSize(ROW_WIDTH, ROW_HEIGHT)
    clickRow:SetPoint("TOPLEFT", frame.clickContainer, "TOPLEFT",
                      8, -28 - (i - 1) * (ROW_HEIGHT + 2))
    clickRow:RegisterForClicks("AnyDown", "AnyUp")

    -- OnEnter/OnLeave mirror the preview-row handlers. Because the click row
    -- sits on top when clickContainer is shown, the preview row's own scripts
    -- don't fire — these handlers take over.
    clickRow:HookScript("OnEnter", function(self)
      local pr = frame.rows[i]
      if not pr.itemLink then return end
      -- Equipped tooltip on the slot
      if Popout._currentSlot and Popout._currentInvSlot then
        equippedTip:SetOwner(Popout._currentSlot, "ANCHOR_RIGHT")
        equippedTip:SetInventoryItem("player", Popout._currentInvSlot)
        equippedTip:Show()
      end
      -- Candidate tooltip via GameTooltip anchored to the right of the popout
      GameTooltip:SetOwner(frame, "ANCHOR_NONE")
      GameTooltip:ClearAllPoints()
      GameTooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
      GameTooltip:SetHyperlink(pr.itemLink)
      GameTooltip:Show()
      -- 3D model preview
      showPreview(pr.itemLink)
      -- Cancel any pending dismiss
      if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
    end)

    clickRow:HookScript("OnLeave", function(self)
      GameTooltip:Hide()
      hidePreview()
      -- Schedule dismiss in case cursor leaves the popout from this row.
      if dismissTimer then dismissTimer:Cancel() end
      dismissTimer = C_Timer.NewTimer(0.2, function()
        if frame:IsShown() and not frame:IsMouseOver() then Popout:Hide() end
        dismissTimer = nil
      end)
    end)

    -- PostClick fires after the secure click resolves. Bag rows dismiss the
    -- popout; bank rows show a toast (the click was a no-op — attributes were
    -- left unset for bank items).
    clickRow:HookScript("PostClick", function(self)
      local pr = frame.rows[i]
      if pr.isBank then
        UIErrorsFrame:AddMessage("Item is in your bank — withdraw it to equip.", 1.0, 0.82, 0)
      else
        Popout:Hide()
      end
    end)

    frame.clickRows[i] = clickRow
  end
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

function Popout:OnSlotEnter(slot)
  local invSlotID = SLOT_TO_INVSLOT[slot:GetName()]
  if not invSlotID then return end
  if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
  if hoverTimer then hoverTimer:Cancel() end
  if equippedTip then equippedTip:Hide() end
  local delay = (SlotPeek.db and SlotPeek.db.profile.hoverDelay) or 0.15
  hoverTimer = C_Timer.NewTimer(delay, function() self:Show(slot, invSlotID) end)
end

function Popout:OnSlotLeave(slot)
  if hoverTimer then hoverTimer:Cancel(); hoverTimer = nil end
  if dismissTimer then dismissTimer:Cancel() end
  dismissTimer = C_Timer.NewTimer(0.2, function()
    if frame:IsShown() and not frame:IsMouseOver() then Popout:Hide() end
    dismissTimer = nil
  end)
end

function Popout:Show(slot, invSlotID)
  if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
  -- Hide stale equipped tooltip from a previous slot before re-showing.
  if equippedTip then equippedTip:Hide() end
  -- Track the last-shown slot so PLAYER_REGEN_ENABLED can re-run Show to
  -- refresh secure attributes now that combat lockdown has lifted.
  self._lastSlot = slot
  self._lastInvSlot = invSlotID
  -- Show the combat badge when the secure click overlay is locked out.
  frame.combatBadge:SetShown(SlotPeek.CombatGuard:IsLocked())
  Popout._currentSlot = slot
  Popout._currentInvSlot = invSlotID
  local cands = SlotPeek.BagIndex:GetCandidates(invSlotID)
  SlotPeek.BagIndex:SortByScore(cands)

  local firstBankIndex
  for i, c in ipairs(cands) do
    if c.source == "bank" then firstBankIndex = i; break end
  end

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
    row.iconBorder:SetVertexColor(r, g, b, 1)

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
    -- Flag used by clickRow's PostClick handler to distinguish bank items.
    row.isBank = (c.source == "bank")
    row:Show()

    -- Configure the matching secure overlay row (must be done via RunSafe
    -- because SetAttribute is blocked during combat lockdown).
    local clickRow = frame.clickRows[i]
    SlotPeek.CombatGuard:RunSafe(function()
      if c.source == "bags" then
        -- "/use <bag> <slot>" reliably equips by container position in BCC.
        -- [nocombat] guard: if combat starts after the popout was opened
        -- (when the macrotext was last set), the macro becomes a no-op
        -- instead of triggering a protected equip → "Interface action failed".
        clickRow:SetAttribute("type", "macro")
        clickRow:SetAttribute("macrotext",
          "/use [nocombat] " .. c.bag .. " " .. c.slot)
      else
        -- Bank rows: leave type unset so click is a no-op; PostClick toasts.
        clickRow:SetAttribute("type", nil)
        clickRow:SetAttribute("macrotext", nil)
      end
      clickRow:Show()
    end)
  end

  -- Hide unused secure overlay rows.
  for i = n + 1, MAX_ROWS do
    SlotPeek.CombatGuard:RunSafe(function()
      frame.clickRows[i]:Hide()
    end)
  end

  if firstBankIndex and firstBankIndex <= n then
    local row = frame.rows[firstBankIndex]
    frame.divider:ClearAllPoints()
    frame.divider:SetPoint("TOPLEFT", row, "TOPLEFT", -4, 1)
    frame.divider:SetPoint("TOPRIGHT", row, "TOPRIGHT", 4, 1)
    frame.divider:Show()
  else
    frame.divider:Hide()
  end

  frame:SetHeight(28 + n * (ROW_HEIGHT + 2) + 8)
  frame.header:SetText(("%d item%s"):format(#cands, #cands == 1 and "" or "s"))

  frame:ClearAllPoints()
  if GameTooltip:IsShown() and GameTooltip:GetOwner() == slot then
    -- Anchor below the tooltip so they stack rather than overlap.
    -- Snapshot screen coords (don't anchor to GameTooltip directly — it
    -- would follow when GameTooltip moves to bag items, etc).
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
  -- Sync clickContainer's screen position to match frame, then show it.
  -- Both ops are protected (clickContainer has secure descendants), so they
  -- run via RunSafe — queued in combat, executed on PLAYER_REGEN_ENABLED.
  local left, top = frame:GetLeft(), frame:GetTop()
  local w, h = frame:GetWidth(), frame:GetHeight()
  SlotPeek.CombatGuard:RunSafe(function()
    if not frame.clickContainer then return end
    if left and top then
      frame.clickContainer:ClearAllPoints()
      frame.clickContainer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    if w and h then frame.clickContainer:SetSize(w, h) end
    frame.clickContainer:Show()
  end)
  if inCombat then dbg("Show EXIT") end
end

function Popout:RevertModel()
  hidePreview()
end

function Popout:Hide()
  if hoverTimer then hoverTimer:Cancel(); hoverTimer = nil end
  if dismissTimer then dismissTimer:Cancel(); dismissTimer = nil end
  self:RevertModel()
  if equippedTip then equippedTip:Hide() end
  if Popout._currentSlot and GameTooltip:GetOwner() == frame then
    GameTooltip:Hide()
  end
  Popout._currentSlot = nil
  Popout._currentInvSlot = nil
  frame:Hide()
  SlotPeek.CombatGuard:RunSafe(function()
    if frame.clickContainer then frame.clickContainer:Hide() end
  end)
end

function Popout:OnEnable()
  self:CreateFrame()
  self:Attach()
  SlotPeek:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() self:RevertModel() end)
  SlotPeek:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if frame and frame.combatBadge then frame.combatBadge:Show() end
    -- clickContainer can't be hidden during lockdown (it's protected via
    -- secure children). Already-hidden state is preserved; if it was shown
    -- when combat started, it stays shown until popout dismisses out of
    -- combat. PostClick on stale attrs is safe (fires Hide).
  end)
  SlotPeek:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if frame and frame.combatBadge then frame.combatBadge:Hide() end
    -- If popout is currently visible for some slot, re-run Show to refresh
    -- the now-actionable secure attributes (and re-show clickContainer).
    if frame and frame:IsShown() and Popout._lastSlot and Popout._lastInvSlot then
      Popout:Show(Popout._lastSlot, Popout._lastInvSlot)
    end
  end)
end
