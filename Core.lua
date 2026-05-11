local addonName, addon = ...
SlotPeek = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0")

function SlotPeek:OnInitialize()
  self:InitDB()
  self:Print("loaded (v0.1.0)")
end

function SlotPeek:OnEnable()
  self:RegisterChatCommand("slotpeek", "HandleSlash")
  self.CombatGuard:OnEnable()
  self.BagIndex:OnEnable()
  self.Popout:OnEnable()
  self.Config:OnEnable()
  if not (PawnGetItemData and PawnGetAllScales) then
    self:Print("|cffff7f7fPawn is not loaded \124 scoring disabled. " ..
               "Install/enable Pawn for item rankings.|r")
  end
end

function SlotPeek:HandleSlash(input)
  input = input and input:lower() or ""
  if input == "test" then
    self:RunAssertions()
  elseif input == "config" then
    self.Config:Open()
  elseif input == "refresh" then
    self.BagIndex:Refresh()
    if BankFrame and BankFrame:IsShown() then
      self.BagIndex:SnapshotBank()
      self:Print("bag + bank cache refreshed")
    else
      self:Print("bag cache refreshed (bank not open — cached snapshot retained)")
    end
  elseif input == "debug" then
    self.db.profile.debug = not self.db.profile.debug
    self:Print("debug " .. (self.db.profile.debug and "ON" or "OFF"))
  else
    self:Print("commands: /slotpeek test | config | refresh | debug")
  end
end
