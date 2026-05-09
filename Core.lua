local addonName, addon = ...
SlotPeek = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0")

function SlotPeek:OnInitialize()
  self:Print("loaded (v0.1.0-dev)")
end

function SlotPeek:OnEnable()
  -- modules attach in later tasks
end
