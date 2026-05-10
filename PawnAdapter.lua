local SlotPeek = SlotPeek
local PawnAdapter = {}
SlotPeek.PawnAdapter = PawnAdapter

local pending = {}
local ticker

function PawnAdapter:IsReady()
  return PawnIsReady and PawnIsReady() or false
end

function PawnAdapter:ScaleName()
  if SlotPeek.db and SlotPeek.db.profile.scaleName then
    return SlotPeek.db.profile.scaleName
  end
  if not PawnGetAllScales then return nil end
  -- PawnGetAllScales returns an array of scale name strings (uses tinsert),
  -- so iterate values, not keys.
  for _, name in ipairs(PawnGetAllScales()) do
    if PawnIsScaleVisible(name) then return name end
  end
  return nil
end

function PawnAdapter:Score(itemLink)
  if not itemLink or not PawnGetItemData then return nil end
  local item = PawnGetItemData(itemLink)
  if not item then
    self:_QueueRetry(itemLink)
    return nil
  end
  local scale = self:ScaleName()
  if not scale then return nil end
  local v = PawnGetSingleValueFromItem(item, scale)
  return v
end

function PawnAdapter:BestForSlot(invType)
  local scale = self:ScaleName()
  if not scale or not PawnGetBestItemLink then return nil end
  return PawnGetBestItemLink(scale, invType)
end

function PawnAdapter:_QueueRetry(itemLink)
  if pending[itemLink] == nil then pending[itemLink] = 0 end
  if not ticker then
    ticker = C_Timer.NewTicker(0.5, function() self:_Tick() end)
  end
end

function PawnAdapter:_Tick()
  local resolved = false
  for link, attempts in pairs(pending) do
    if PawnGetItemData(link) then
      pending[link] = nil
      resolved = true
    else
      pending[link] = attempts + 1
      if pending[link] >= 6 then
        pending[link] = nil  -- give up after 6 ticks (~3 seconds)
      end
    end
  end
  if next(pending) == nil and ticker then
    ticker:Cancel()
    ticker = nil
  end
  if resolved then
    SlotPeek:SendMessage("SlotPeek_PAWN_RESOLVED")
  end
end
