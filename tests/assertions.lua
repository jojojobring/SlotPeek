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
