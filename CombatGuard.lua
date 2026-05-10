local SlotPeek = SlotPeek
local CombatGuard = {}
SlotPeek.CombatGuard = CombatGuard

local pending = {}

function CombatGuard:IsLocked()
  return InCombatLockdown()
end

function CombatGuard:RunSafe(fn)
  if InCombatLockdown() then
    table.insert(pending, fn)
  else
    fn()
  end
end

function CombatGuard:Flush()
  local n = #pending
  for i = 1, n do
    local fn = pending[i]
    pending[i] = nil
    local ok, err = pcall(fn)
    if not ok then
      SlotPeek:Print("RunSafe deferred fn errored: " .. tostring(err))
    end
  end
end

function CombatGuard:OnEnable()
  SlotPeek:RegisterEvent("PLAYER_REGEN_ENABLED", function() self:Flush() end)
end
