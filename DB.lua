local SlotPeek = SlotPeek

local defaults = {
  profile = {
    enabled       = true,
    hoverDelay    = 0.15,
    scaleName     = nil,
    debug         = false,
    showItemName  = false,
    dbVersion     = 1,
  },
  char = {
    bankCache = {},
  },
}

function SlotPeek:InitDB()
  self.db = LibStub("AceDB-3.0"):New("SlotPeekDB", defaults, true)
  if self.db.profile.dbVersion ~= defaults.profile.dbVersion then
    self.db.char.bankCache = {}
    self.db.profile.dbVersion = defaults.profile.dbVersion
  end
end
