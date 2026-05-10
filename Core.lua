local addonName, addon = ...
SlotPeek = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0")

function SlotPeek:OnInitialize()
  self:InitDB()
  self:Print("loaded (v0.1.0-dev)")
end

function SlotPeek:OnEnable()
  self:RegisterChatCommand("slotpeek", "HandleSlash")
end

function SlotPeek:HandleSlash(input)
  input = input and input:lower() or ""
  if input == "test" then
    self:RunAssertions()
  elseif input == "config" then
    self:Print("config UI not yet implemented (Task 21)")
  else
    self:Print("commands: /slotpeek test | config")
  end
end
