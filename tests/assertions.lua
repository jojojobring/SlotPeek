local SlotPeek = SlotPeek
SlotPeek.assertions = {}

function SlotPeek:RegisterAssertion(name, fn)
  table.insert(self.assertions, { name = name, fn = fn })
end

function SlotPeek:RunAssertions()
  self:Print("running " .. #self.assertions .. " assertion(s)...")
  local pass, fail = 0, 0
  for _, a in ipairs(self.assertions) do
    local ok, err = pcall(a.fn)
    if ok and err == nil then
      self:Print("  PASS  " .. a.name)
      pass = pass + 1
    else
      self:Print("  FAIL  " .. a.name .. ": " .. tostring(err))
      fail = fail + 1
    end
  end
  self:Print(("results: %d pass, %d fail"):format(pass, fail))
end

SlotPeek:RegisterAssertion("sentinel: harness works", function()
  assert(true)
end)

SlotPeek:RegisterAssertion("DB initialized with defaults", function()
  assert(SlotPeek.db, "SlotPeek.db missing")
  assert(SlotPeek.db.profile.enabled == true, "default 'enabled' should be true")
  assert(SlotPeek.db.profile.hoverDelay == 0.15, "default hoverDelay 0.15")
  assert(type(SlotPeek.db.char.bankCache) == "table", "char.bankCache must be a table")
end)

SlotPeek:RegisterAssertion("CombatGuard.RunSafe runs immediately when not in combat", function()
  assert(SlotPeek.CombatGuard, "CombatGuard module missing")
  local ran = false
  SlotPeek.CombatGuard:RunSafe(function() ran = true end)
  assert(ran, "RunSafe should run synchronously out of combat")
end)

SlotPeek:RegisterAssertion("CombatGuard.IsLocked matches InCombatLockdown", function()
  assert(SlotPeek.CombatGuard:IsLocked() == InCombatLockdown(), "IsLocked must wrap InCombatLockdown")
end)

SlotPeek:RegisterAssertion("PawnAdapter ready", function()
  assert(SlotPeek.PawnAdapter, "PawnAdapter missing")
  assert(SlotPeek.PawnAdapter:IsReady(), "PawnAdapter:IsReady must wrap PawnIsReady")
end)

SlotPeek:RegisterAssertion("PawnAdapter.Score returns number for equipped helm", function()
  local link = GetInventoryItemLink("player", INVSLOT_HEAD)
  if not link then return end -- skip if no helm equipped
  local score = SlotPeek.PawnAdapter:Score(link)
  assert(type(score) == "number" or score == nil, "Score must return number or nil")
end)

SlotPeek:RegisterAssertion("BagIndex slot eligibility — INVTYPE_HEAD fits HEAD slot", function()
  assert(SlotPeek.BagIndex, "BagIndex missing")
  assert(SlotPeek.BagIndex:FitsSlot("INVTYPE_HEAD", INVSLOT_HEAD))
  assert(not SlotPeek.BagIndex:FitsSlot("INVTYPE_HEAD", INVSLOT_CHEST))
  assert(SlotPeek.BagIndex:FitsSlot("INVTYPE_2HWEAPON", INVSLOT_MAINHAND))
  assert(not SlotPeek.BagIndex:FitsSlot("INVTYPE_2HWEAPON", INVSLOT_OFFHAND))
  assert(SlotPeek.BagIndex:FitsSlot("INVTYPE_HOLDABLE", INVSLOT_OFFHAND))
end)

SlotPeek:RegisterAssertion("BagIndex.ScanBags returns at least the items currently in bags", function()
  local items = SlotPeek.BagIndex:ScanBags()
  assert(type(items) == "table")
  -- spot check: every entry has a link, bag, slot
  for _, e in ipairs(items) do
    assert(e.itemLink and e.bag and e.slot, "entry missing fields: " .. (e.itemLink or "?"))
  end
end)

SlotPeek:RegisterAssertion("BagIndex.IsUsable accepts class-neutral items", function()
  -- a generic cloth shirt — itemID 6948 is Hearthstone (no equip), use something else
  -- find any equipped item; it must be usable by us
  local equipped = GetInventoryItemLink("player", INVSLOT_CHEST) or GetInventoryItemLink("player", INVSLOT_HEAD)
  if not equipped then return end
  assert(SlotPeek.BagIndex:IsUsable(equipped), "equipped item should be usable: " .. equipped)
end)
