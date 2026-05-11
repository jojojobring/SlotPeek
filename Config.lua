local SlotPeek = SlotPeek
local Config = {}
SlotPeek.Config = Config

local function pawnScales()
  local scales = {}
  if PawnGetAllScales then
    for _, name in ipairs(PawnGetAllScales()) do
      scales[name] = name
    end
  end
  return scales
end

local optionsTable = {
  type = "group",
  name = "SlotPeek",
  args = {
    enabled = {
      type = "toggle",
      name = "Enabled",
      desc = "Show the popout when hovering an equipment slot.",
      order = 1,
      width = "full",
      get = function() return SlotPeek.db.profile.enabled end,
      set = function(_, v) SlotPeek.db.profile.enabled = v end,
    },
    hoverDelay = {
      type = "range",
      name = "Hover delay (seconds)",
      desc = "How long the cursor must rest on a slot before the popout appears.",
      order = 2,
      min = 0, max = 0.5, step = 0.025,
      get = function() return SlotPeek.db.profile.hoverDelay end,
      set = function(_, v) SlotPeek.db.profile.hoverDelay = v end,
    },
    scaleName = {
      type = "select",
      name = "Pawn scale",
      desc = "Which Pawn scale to use for scoring. Leave blank to auto-pick the first visible scale.",
      order = 3,
      values = pawnScales,
      get = function() return SlotPeek.db.profile.scaleName end,
      set = function(_, v)
        SlotPeek.db.profile.scaleName = v
        SlotPeek.BagIndex:Refresh()
      end,
    },
    debug = {
      type = "toggle",
      name = "Debug logging",
      desc = "Print diagnostic breadcrumbs to chat.",
      order = 4,
      get = function() return SlotPeek.db.profile.debug end,
      set = function(_, v) SlotPeek.db.profile.debug = v end,
    },
  },
}

function Config:OnEnable()
  LibStub("AceConfig-3.0"):RegisterOptionsTable("SlotPeek", optionsTable)
  self.blizPanel = LibStub("AceConfigDialog-3.0")
    :AddToBlizOptions("SlotPeek", "SlotPeek")
end

function Config:Open()
  LibStub("AceConfigDialog-3.0"):Open("SlotPeek")
end
