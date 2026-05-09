# SlotPeek Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the SlotPeek WoW addon as specified in `DESIGN.md` — a hover-popout for character pane equipment slots that lists matching bag/bank items with Pawn scoring, click-to-equip, and live model preview.

**Architecture:** Ace3-based addon (AceAddon, AceEvent, AceDB, AceConfig, AceConsole, AceGUI), embedded library set, hard dependency on Pawn. Seven runtime modules: `Core`, `DB`, `BagIndex`, `PawnAdapter`, `CombatGuard`, `Popout`, `Config`. Combat-lockdown handled via a `RunSafe` wrapper that defers secure operations to `PLAYER_REGEN_ENABLED`.

**Tech Stack:** Lua 5.1, WoW BCC Anniversary 2.5.5 client (interface `20505`), Ace3 (embedded), Pawn (external dependency).

**Repo:** `C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\SlotPeek\` — git initialized, `main` branch, origin `git@github.com:jojojobring/SlotPeek.git`.

**Spec reference:** `DESIGN.md` at repo root — defer to it for any decision not specified here. Section numbers in this plan refer to `DESIGN.md` sections.

---

## Testing model

WoW addons cannot be unit-tested in CI. The plan uses three layers:

1. **Static syntax check** — `luac -p <file>.lua` after every edit. Lua 5.1 syntax. Catches typos before reload.
2. **`/slotpeek test` slash command** — accumulates per-module assertions. Each new logic function gets an assertion. Runs in-game; results post to chat.
3. **Manual smoke** — for UI behavior, secure clicks, and model preview, document what to do in-game and what to expect.

For tasks marked **"Test: in-game smoke,"** the verification step is "follow the listed manual steps and confirm the expected behavior." For tasks marked **"Test: assertion,"** add an assertion to `tests/assertions.lua` (a file we create in Task 2) and verify it fails before the implementation, then passes after.

`luac` must be on `$PATH`. If not available, install via `scoop install lua` or skip syntax checks (the WoW client itself reports syntax errors at load via `/console scriptErrors 1`).

---

## File structure

```
SlotPeek/
├── SlotPeek.toc                     # interface 20505, deps: Pawn
├── Libs/                            # embedded Ace3
│   ├── Libs.xml                     # <Include>/<Script> manifest
│   ├── LibStub/
│   ├── CallbackHandler-1.0/
│   ├── AceAddon-3.0/
│   ├── AceEvent-3.0/
│   ├── AceConsole-3.0/
│   ├── AceDB-3.0/
│   ├── AceConfig-3.0/
│   └── AceGUI-3.0/
├── Core.lua                         # AceAddon scaffold, /slotpeek slash command
├── DB.lua                           # AceDB defaults
├── CombatGuard.lua                  # RunSafe + IsLocked
├── PawnAdapter.lua                  # Score, BestForSlot, retry queue
├── BagIndex.lua                     # bag scan, bank cache, slot candidates
├── Popout.lua                       # popout Frame, button pool, model preview
├── Config.lua                       # AceConfig options
├── tests/
│   └── assertions.lua               # /slotpeek test assertion suite
├── DESIGN.md                        # design doc (already committed)
├── LICENSE                          # MIT (already committed)
├── .gitignore
├── README.md                        # written in Task 22
├── TESTING.md                       # written in Task 22
└── docs/plans/2026-05-09-implementation-plan.md   # this file
```

---

## Task 0: Obtain Ace3 libraries

**Files:**
- Create: `Libs/LibStub/LibStub.lua`
- Create: `Libs/CallbackHandler-1.0/CallbackHandler-1.0.{lua,xml}`
- Create: `Libs/AceAddon-3.0/AceAddon-3.0.{lua,xml}`
- Create: `Libs/AceEvent-3.0/AceEvent-3.0.{lua,xml}`
- Create: `Libs/AceConsole-3.0/AceConsole-3.0.{lua,xml}`
- Create: `Libs/AceDB-3.0/AceDB-3.0.{lua,xml}`
- Create: `Libs/AceConfig-3.0/` (recursive — includes AceConfigCmd, AceConfigDialog, AceConfigRegistry)
- Create: `Libs/AceGUI-3.0/` (recursive — many widgets)
- Create: `Libs/Libs.xml`

- [ ] **Step 1: Download Ace3 from CurseForge**

Two options:

**(Preferred)** Download the standalone Ace3 zip from `https://www.curseforge.com/wow/addons/ace3/files` (latest release). Extract. Inside, find the `Ace3/` folder containing `LibStub/`, `CallbackHandler-1.0/`, etc. Copy each library subfolder into `SlotPeek/Libs/`.

**(Fallback)** Copy from an installed addon that embeds Ace3, e.g. `..\Bartender4\libs\` or `..\DBM-Core\Libs\`. Copy `LibStub/`, `CallbackHandler-1.0/`, `AceAddon-3.0/`, `AceEvent-3.0/`, `AceConsole-3.0/`, `AceDB-3.0/`, `AceConfig-3.0/` (plus its sub-libraries `AceConfigCmd-3.0`, `AceConfigDialog-3.0`, `AceConfigRegistry-3.0` if separate folders), and `AceGUI-3.0/` into `SlotPeek/Libs/`.

- [ ] **Step 2: Create `Libs/Libs.xml`**

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/">
  <Script file="LibStub\LibStub.lua"/>
  <Include file="CallbackHandler-1.0\CallbackHandler-1.0.xml"/>
  <Include file="AceAddon-3.0\AceAddon-3.0.xml"/>
  <Include file="AceEvent-3.0\AceEvent-3.0.xml"/>
  <Include file="AceConsole-3.0\AceConsole-3.0.xml"/>
  <Include file="AceDB-3.0\AceDB-3.0.xml"/>
  <Include file="AceConfig-3.0\AceConfig-3.0.xml"/>
  <Include file="AceGUI-3.0\AceGUI-3.0.xml"/>
</Ui>
```

- [ ] **Step 3: Verify file count**

Run: `find Libs -name "*.lua" | wc -l` — expect 30+ files (varies by Ace3 version).

- [ ] **Step 4: Commit**

```bash
git add Libs
git commit -m "Add embedded Ace3 libraries"
```

---

## Task 1: TOC file and Core.lua skeleton — addon loads without error

**Files:**
- Create: `SlotPeek.toc`
- Create: `Core.lua`

- [ ] **Step 1: Write `SlotPeek.toc`**

```
## Interface: 20505
## Title: SlotPeek
## Notes: Hover an equipment slot to see all matching items in your bags and bank, scored by Pawn.
## Author: jojojobring
## Version: 0.1.0-dev
## Dependencies: Pawn
## SavedVariables: SlotPeekDB
## X-License: MIT

Libs\Libs.xml

Core.lua
```

- [ ] **Step 2: Write `Core.lua` skeleton**

```lua
local addonName, addon = ...
SlotPeek = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0", "AceConsole-3.0")

function SlotPeek:OnInitialize()
  self:Print("loaded (v0.1.0-dev)")
end

function SlotPeek:OnEnable()
  -- modules attach in later tasks
end
```

- [ ] **Step 3: Syntax check**

Run: `luac -p Core.lua`
Expected: no output (success).

- [ ] **Step 4: In-game smoke test**

In WoW: `/reload`. In chat, expect: `SlotPeek: loaded (v0.1.0-dev)`. Run `/console scriptErrors 1` first if you want Lua errors to surface as red error frames.

If it fails to load, check the BCC client's `Logs/FrameXML.log` for parse errors.

- [ ] **Step 5: Commit**

```bash
git add SlotPeek.toc Core.lua
git commit -m "Bootstrap addon: TOC and Core.lua scaffold"
```

---

## Task 2: Slash command and assertion harness

**Files:**
- Modify: `Core.lua`
- Create: `tests/assertions.lua`
- Modify: `SlotPeek.toc` (add `tests/assertions.lua`)

- [ ] **Step 1: Create `tests/assertions.lua`**

```lua
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
```

Assertion convention: each assertion function does `assert(condition, "message")` to fail; otherwise returns nil (or simply finishes) for pass.

- [ ] **Step 2: Wire `/slotpeek test` in `Core.lua`**

Replace `OnEnable` body:

```lua
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
```

- [ ] **Step 3: Add `tests/assertions.lua` to TOC**

In `SlotPeek.toc`, between `Core.lua` and the end:

```
Core.lua
tests\assertions.lua
```

- [ ] **Step 4: Add a sentinel assertion**

In `tests/assertions.lua` at the bottom:

```lua
SlotPeek:RegisterAssertion("sentinel: harness works", function()
  assert(true)
end)
```

- [ ] **Step 5: Syntax check**

Run: `luac -p Core.lua tests/assertions.lua`
Expected: no output.

- [ ] **Step 6: In-game smoke test**

`/reload`. Run `/slotpeek test`. Expect:
```
SlotPeek: running 1 assertion(s)...
SlotPeek:   PASS  sentinel: harness works
SlotPeek: results: 1 pass, 0 fail
```

- [ ] **Step 7: Commit**

```bash
git add Core.lua tests/assertions.lua SlotPeek.toc
git commit -m "Add /slotpeek slash command and assertion harness"
```

---

## Task 3: AceDB scaffold (DB.lua)

**Files:**
- Create: `DB.lua`
- Modify: `Core.lua`
- Modify: `SlotPeek.toc`
- Modify: `tests/assertions.lua`

- [ ] **Step 1: Add failing assertion**

In `tests/assertions.lua`, append:

```lua
SlotPeek:RegisterAssertion("DB initialized with defaults", function()
  assert(SlotPeek.db, "SlotPeek.db missing")
  assert(SlotPeek.db.profile.enabled == true, "default 'enabled' should be true")
  assert(SlotPeek.db.profile.hoverDelay == 0.15, "default hoverDelay 0.15")
  assert(type(SlotPeek.db.char.bankCache) == "table", "char.bankCache must be a table")
end)
```

- [ ] **Step 2: Verify assertion fails**

`/reload`, `/slotpeek test`. Expect FAIL: `SlotPeek.db missing`.

- [ ] **Step 3: Write `DB.lua`**

```lua
local SlotPeek = SlotPeek

local defaults = {
  profile = {
    enabled    = true,
    hoverDelay = 0.15,
    scaleName  = nil,
    debug      = false,
    dbVersion  = 1,
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
```

- [ ] **Step 4: Call `InitDB` from `OnInitialize`**

In `Core.lua`:

```lua
function SlotPeek:OnInitialize()
  self:InitDB()
  self:Print("loaded (v0.1.0-dev)")
end
```

- [ ] **Step 5: Add `DB.lua` to TOC**

In `SlotPeek.toc`, between `Core.lua` and `tests\assertions.lua`:

```
Core.lua
DB.lua
tests\assertions.lua
```

- [ ] **Step 6: Syntax check, in-game verify**

Run: `luac -p DB.lua Core.lua`
`/reload`, `/slotpeek test`. Expect both assertions PASS.

- [ ] **Step 7: Commit**

```bash
git add DB.lua Core.lua SlotPeek.toc tests/assertions.lua
git commit -m "Add AceDB scaffold with profile and char defaults"
```

---

## Task 4: CombatGuard module

**Files:**
- Create: `CombatGuard.lua`
- Modify: `SlotPeek.toc`
- Modify: `Core.lua`
- Modify: `tests/assertions.lua`

- [ ] **Step 1: Add failing assertion**

In `tests/assertions.lua`:

```lua
SlotPeek:RegisterAssertion("CombatGuard.RunSafe runs immediately when not in combat", function()
  assert(SlotPeek.CombatGuard, "CombatGuard module missing")
  local ran = false
  SlotPeek.CombatGuard:RunSafe(function() ran = true end)
  assert(ran, "RunSafe should run synchronously out of combat")
end)

SlotPeek:RegisterAssertion("CombatGuard.IsLocked matches InCombatLockdown", function()
  assert(SlotPeek.CombatGuard:IsLocked() == InCombatLockdown(), "IsLocked must wrap InCombatLockdown")
end)
```

- [ ] **Step 2: Verify failing**

`/reload`, `/slotpeek test`. Both new assertions FAIL.

- [ ] **Step 3: Write `CombatGuard.lua`**

```lua
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
```

- [ ] **Step 4: Boot CombatGuard from `Core.lua`**

In `OnEnable`:

```lua
function SlotPeek:OnEnable()
  self:RegisterChatCommand("slotpeek", "HandleSlash")
  self.CombatGuard:OnEnable()
end
```

- [ ] **Step 5: Add to TOC**

After `DB.lua`:

```
DB.lua
CombatGuard.lua
tests\assertions.lua
```

- [ ] **Step 6: Verify**

`luac -p CombatGuard.lua Core.lua`
`/reload`, `/slotpeek test`. All assertions PASS.

- [ ] **Step 7: Commit**

```bash
git add CombatGuard.lua Core.lua SlotPeek.toc tests/assertions.lua
git commit -m "Add CombatGuard with RunSafe and PLAYER_REGEN_ENABLED flush"
```

---

## Task 5: PawnAdapter — basic Score function

**Files:**
- Create: `PawnAdapter.lua`
- Modify: `SlotPeek.toc`
- Modify: `tests/assertions.lua`

- [ ] **Step 1: Add failing assertions**

```lua
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
```

- [ ] **Step 2: Verify failing**

`/reload`, `/slotpeek test`. Both fail.

- [ ] **Step 3: Write `PawnAdapter.lua`**

```lua
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
  for name, _ in pairs(PawnGetAllScales()) do
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
```

- [ ] **Step 4: Add `AceEvent-3.0` SendMessage capability**

Confirmed already — `AceEvent-3.0` provides `SendMessage` since SlotPeek embeds it as a mixin. No code change needed.

- [ ] **Step 5: Add to TOC**

```
CombatGuard.lua
PawnAdapter.lua
tests\assertions.lua
```

- [ ] **Step 6: Verify**

`luac -p PawnAdapter.lua`
`/reload`, `/slotpeek test`. New assertions PASS (Score may return nil if Pawn has no scale visible — that's fine, the assertion accepts nil).

- [ ] **Step 7: Commit**

```bash
git add PawnAdapter.lua SlotPeek.toc tests/assertions.lua
git commit -m "Add PawnAdapter with Score, BestForSlot, and retry queue"
```

---

## Task 6: BagIndex — slot eligibility table

**Files:**
- Create: `BagIndex.lua`
- Modify: `SlotPeek.toc`
- Modify: `tests/assertions.lua`

- [ ] **Step 1: Add failing assertion**

```lua
SlotPeek:RegisterAssertion("BagIndex slot eligibility — INVTYPE_HEAD fits HEAD slot", function()
  assert(SlotPeek.BagIndex, "BagIndex missing")
  assert(SlotPeek.BagIndex:FitsSlot("INVTYPE_HEAD", INVSLOT_HEAD))
  assert(not SlotPeek.BagIndex:FitsSlot("INVTYPE_HEAD", INVSLOT_CHEST))
  assert(SlotPeek.BagIndex:FitsSlot("INVTYPE_2HWEAPON", INVSLOT_MAINHAND))
  assert(not SlotPeek.BagIndex:FitsSlot("INVTYPE_2HWEAPON", INVSLOT_OFFHAND))
  assert(SlotPeek.BagIndex:FitsSlot("INVTYPE_HOLDABLE", INVSLOT_OFFHAND))
end)
```

- [ ] **Step 2: Verify failing**

- [ ] **Step 3: Write `BagIndex.lua` with eligibility table**

```lua
local SlotPeek = SlotPeek
local BagIndex = {}
SlotPeek.BagIndex = BagIndex

local SLOT_FITS = {
  [INVSLOT_HEAD]      = { INVTYPE_HEAD = true },
  [INVSLOT_NECK]      = { INVTYPE_NECK = true },
  [INVSLOT_SHOULDER]  = { INVTYPE_SHOULDER = true },
  [INVSLOT_CHEST]     = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
  [INVSLOT_WAIST]     = { INVTYPE_WAIST = true },
  [INVSLOT_LEGS]      = { INVTYPE_LEGS = true },
  [INVSLOT_FEET]      = { INVTYPE_FEET = true },
  [INVSLOT_WRIST]     = { INVTYPE_WRIST = true },
  [INVSLOT_HAND]      = { INVTYPE_HAND = true },
  [INVSLOT_FINGER1]   = { INVTYPE_FINGER = true },
  [INVSLOT_FINGER2]   = { INVTYPE_FINGER = true },
  [INVSLOT_TRINKET1]  = { INVTYPE_TRINKET = true },
  [INVSLOT_TRINKET2]  = { INVTYPE_TRINKET = true },
  [INVSLOT_BACK]      = { INVTYPE_CLOAK = true },
  [INVSLOT_MAINHAND]  = { INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPON = true },
  [INVSLOT_OFFHAND]   = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true },
  [INVSLOT_RANGED]    = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true },
}

function BagIndex:FitsSlot(invType, invSlotID)
  local set = SLOT_FITS[invSlotID]
  return set and set[invType] == true or false
end
```

- [ ] **Step 4: Add to TOC**

```
PawnAdapter.lua
BagIndex.lua
tests\assertions.lua
```

- [ ] **Step 5: Verify**

`luac -p BagIndex.lua`. `/reload`, `/slotpeek test`. New assertion PASS.

- [ ] **Step 6: Commit**

```bash
git add BagIndex.lua SlotPeek.toc tests/assertions.lua
git commit -m "Add BagIndex with slot eligibility table"
```

---

## Task 7: BagIndex — bag enumeration

**Files:**
- Modify: `BagIndex.lua`
- Modify: `tests/assertions.lua`

- [ ] **Step 1: Add failing assertion**

```lua
SlotPeek:RegisterAssertion("BagIndex.ScanBags returns at least the items currently in bags", function()
  local items = SlotPeek.BagIndex:ScanBags()
  assert(type(items) == "table")
  -- spot check: every entry has a link, bag, slot
  for _, e in ipairs(items) do
    assert(e.itemLink and e.bag and e.slot, "entry missing fields: " .. (e.itemLink or "?"))
  end
end)
```

- [ ] **Step 2: Verify failing**

- [ ] **Step 3: Implement `ScanBags`**

In `BagIndex.lua`:

```lua
function BagIndex:ScanBags()
  local result = {}
  for bag = 0, NUM_BAG_SLOTS do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink then
        table.insert(result, {
          itemLink = info.hyperlink,
          bag = bag,
          slot = slot,
          itemID = info.itemID,
          icon = info.iconFileID,
          source = "bags",
        })
      end
    end
  end
  return result
end
```

- [ ] **Step 4: Verify**

`/reload`, `/slotpeek test`. Assertion PASS.

- [ ] **Step 5: Commit**

```bash
git add BagIndex.lua tests/assertions.lua
git commit -m "BagIndex: scan bags via C_Container API"
```

---

## Task 8: BagIndex — class usability filter

**Files:**
- Modify: `BagIndex.lua`
- Modify: `tests/assertions.lua`

- [ ] **Step 1: Add failing assertions**

```lua
SlotPeek:RegisterAssertion("BagIndex.IsUsable accepts class-neutral items", function()
  -- a generic cloth shirt — itemID 6948 is Hearthstone (no equip), use something else
  -- find any equipped item; it must be usable by us
  local equipped = GetInventoryItemLink("player", INVSLOT_CHEST) or GetInventoryItemLink("player", INVSLOT_HEAD)
  if not equipped then return end
  assert(SlotPeek.BagIndex:IsUsable(equipped), "equipped item should be usable: " .. equipped)
end)
```

(More precise tests for unusable items require knowing specific items; we rely on the smoke test.)

- [ ] **Step 2: Verify failing**

- [ ] **Step 3: Implement `IsUsable`**

```lua
local CLASS_ARMOR = {
  WARRIOR = { Cloth = 0, Leather = 0, Mail = 40, Plate = 40 },
  PALADIN = { Cloth = 0, Leather = 0, Mail = 40, Plate = 40 },
  HUNTER  = { Cloth = 0, Leather = 0, Mail = 40 },
  ROGUE   = { Cloth = 0, Leather = 0 },
  PRIEST  = { Cloth = 0 },
  SHAMAN  = { Cloth = 0, Leather = 0, Mail = 40 },
  MAGE    = { Cloth = 0 },
  WARLOCK = { Cloth = 0 },
  DRUID   = { Cloth = 0, Leather = 0 },
}

local CLASS_WEAPON = {} -- populated below

local scanTip = CreateFrame("GameTooltip", "SlotPeekScanTip", UIParent, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")
local usableCache = {}

local function scanClassRestriction(itemLink)
  scanTip:ClearLines()
  scanTip:SetHyperlink(itemLink)
  local n = scanTip:NumLines()
  local prefix = ITEM_CLASSES_ALLOWED:gsub("%%s.*", "")
  for i = 2, n do
    local left = _G["SlotPeekScanTipTextLeft" .. i]
    local text = left and left:GetText()
    if text and text:find(prefix, 1, true) then
      return text:sub(#prefix + 1)
    end
  end
  return nil
end

function BagIndex:IsUsable(itemLink)
  local itemID = (GetItemInfoInstant and GetItemInfoInstant(itemLink)) or nil
  if itemID and usableCache[itemID] ~= nil then return usableCache[itemID] end

  local _, _, _, _, _, _, _, _, equipLoc, _, _, classID, subclassID = GetItemInfo(itemLink)
  if not equipLoc then return true end

  local _, playerClass = UnitClass("player")

  -- class restriction line
  local restrictedTo = scanClassRestriction(itemLink)
  if restrictedTo then
    local localizedClass = LOCALIZED_CLASS_NAMES_MALE[playerClass] or playerClass
    if not restrictedTo:find(localizedClass, 1, true) then
      if itemID then usableCache[itemID] = false end
      return false
    end
  end

  -- armor proficiency (classID 4 = Armor in BCC)
  if classID == 4 then
    local subTypeName = select(7, GetItemInfo(itemLink)) -- subType localized; use API constant
    -- subclassID for armor: 1=Cloth, 2=Leather, 3=Mail, 4=Plate
    local armorMap = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
    local needed = armorMap[subclassID]
    if needed then
      local prof = CLASS_ARMOR[playerClass]
      if not prof or prof[needed] == nil then
        if itemID then usableCache[itemID] = false end
        return false
      end
      -- level gate
      local minLevel = prof[needed]
      if minLevel and UnitLevel("player") < minLevel then
        -- character will eventually learn it; treat as usable (aspirational gear)
      end
    end
  end

  if itemID then usableCache[itemID] = true end
  return true
end
```

Note: this is a starting implementation that handles the common cases. Edge cases (idols/librams/totems for non-druid/paladin/shaman, weapon proficiencies for low-level classes) are best discovered via the manual smoke matrix in Task 22.

- [ ] **Step 4: Verify**

`/reload`, `/slotpeek test`. Equipped-item-usable assertion PASS.

- [ ] **Step 5: Commit**

```bash
git add BagIndex.lua tests/assertions.lua
git commit -m "BagIndex: class usability filter (armor + class restriction line)"
```

---

## Task 9: BagIndex — GetCandidates with sorting

**Files:**
- Modify: `BagIndex.lua`
- Modify: `tests/assertions.lua`

- [ ] **Step 1: Add failing assertion**

```lua
SlotPeek:RegisterAssertion("BagIndex.GetCandidates(INVSLOT_HEAD) returns slot-compatible items only", function()
  local cands = SlotPeek.BagIndex:GetCandidates(INVSLOT_HEAD)
  assert(type(cands) == "table")
  for _, c in ipairs(cands) do
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(c.itemLink)
    assert(equipLoc == "INVTYPE_HEAD", "non-head item leaked: " .. c.itemLink)
  end
end)
```

- [ ] **Step 2: Verify failing**

- [ ] **Step 3: Implement `GetCandidates`**

Add to `BagIndex.lua`:

```lua
function BagIndex:GetCandidates(invSlotID)
  local result = {}
  local seen = {}

  -- exclude items currently in the "other" finger/trinket slot
  local exclude = {}
  if invSlotID == INVSLOT_FINGER1 then
    exclude[GetInventoryItemLink("player", INVSLOT_FINGER2)] = true
  elseif invSlotID == INVSLOT_FINGER2 then
    exclude[GetInventoryItemLink("player", INVSLOT_FINGER1)] = true
  elseif invSlotID == INVSLOT_TRINKET1 then
    exclude[GetInventoryItemLink("player", INVSLOT_TRINKET2)] = true
  elseif invSlotID == INVSLOT_TRINKET2 then
    exclude[GetInventoryItemLink("player", INVSLOT_TRINKET1)] = true
  end

  -- 2H equipped → no OH candidates
  if invSlotID == INVSLOT_OFFHAND then
    local mh = GetInventoryItemLink("player", INVSLOT_MAINHAND)
    if mh then
      local _, _, _, _, _, _, _, _, mhLoc = GetItemInfo(mh)
      if mhLoc == "INVTYPE_2HWEAPON" then return {} end
    end
  end

  local function consider(entry)
    if exclude[entry.itemLink] or seen[entry.itemLink] then return end
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(entry.itemLink)
    if not equipLoc or equipLoc == "" then return end
    if not self:FitsSlot(equipLoc, invSlotID) then return end
    if not self:IsUsable(entry.itemLink) then return end
    seen[entry.itemLink] = true
    table.insert(result, entry)
  end

  for _, e in ipairs(self:ScanBags()) do consider(e) end
  -- bank scan in Task 17
  return result
end

function BagIndex:SortByScore(candidates)
  table.sort(candidates, function(a, b)
    local sa = SlotPeek.PawnAdapter:Score(a.itemLink) or -math.huge
    local sb = SlotPeek.PawnAdapter:Score(b.itemLink) or -math.huge
    return sa > sb
  end)
end
```

- [ ] **Step 4: Verify**

`/reload`, `/slotpeek test`. Assertion PASS.

- [ ] **Step 5: Commit**

```bash
git add BagIndex.lua tests/assertions.lua
git commit -m "BagIndex: GetCandidates with finger/trinket exclusion and 2H/OH guard"
```

---

## Task 10: Popout shell — basic frame, no rows

**Files:**
- Create: `Popout.lua`
- Modify: `SlotPeek.toc`
- Modify: `Core.lua`

- [ ] **Step 1: Write `Popout.lua` skeleton**

```lua
local SlotPeek = SlotPeek
local Popout = {}
SlotPeek.Popout = Popout

local frame
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

function Popout:CreateFrame()
  frame = CreateFrame("Frame", "SlotPeekPopoutFrame", UIParent, "BackdropTemplate")
  frame:SetSize(220, 40)
  frame:SetFrameStrata("DIALOG")
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
  frame.header:SetText("(no items)")
end

function Popout:Attach()
  for _, slot in ipairs(SLOT_FRAMES) do
    if slot then
      slot:HookScript("OnEnter", function(s) self:OnSlotEnter(s) end)
      slot:HookScript("OnLeave", function(s) self:OnSlotLeave(s) end)
    end
  end
end

local hoverTimer
function Popout:OnSlotEnter(slot)
  local invSlotID = SLOT_TO_INVSLOT[slot:GetName()]
  if not invSlotID then return end
  if hoverTimer then hoverTimer:Cancel() end
  local delay = (SlotPeek.db and SlotPeek.db.profile.hoverDelay) or 0.15
  hoverTimer = C_Timer.NewTimer(delay, function() self:Show(slot, invSlotID) end)
end

function Popout:OnSlotLeave(slot)
  if hoverTimer then hoverTimer:Cancel(); hoverTimer = nil end
  C_Timer.After(0.2, function() if not frame:IsMouseOver() then self:Hide() end end)
end

function Popout:Show(slot, invSlotID)
  local cands = SlotPeek.BagIndex:GetCandidates(invSlotID)
  SlotPeek.BagIndex:SortByScore(cands)
  frame.header:SetText(("%s — %d items"):format(slot:GetName():gsub("Character",""):gsub("Slot",""), #cands))
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", slot, "TOPRIGHT", 8, 0)
  frame:Show()
end

function Popout:Hide()
  frame:Hide()
end

function Popout:OnEnable()
  self:CreateFrame()
  self:Attach()
end
```

- [ ] **Step 2: Boot from `Core.lua`**

```lua
function SlotPeek:OnEnable()
  self:RegisterChatCommand("slotpeek", "HandleSlash")
  self.CombatGuard:OnEnable()
  self.Popout:OnEnable()
end
```

- [ ] **Step 3: Add to TOC**

```
BagIndex.lua
Popout.lua
tests\assertions.lua
```

- [ ] **Step 4: Syntax check, in-game smoke**

`luac -p Popout.lua Core.lua`
`/reload`. Open character pane (`C`). Hover slots. Expect: a small black tooltip-style frame appears next to each slot showing "Head — N items" etc. Move cursor away — it disappears after 200ms.

- [ ] **Step 5: Commit**

```bash
git add Popout.lua Core.lua SlotPeek.toc
git commit -m "Popout: basic frame, slot hooks with hover delay, anchor next to slot"
```

---

## Task 11: Popout — anchor below GameTooltip when present

**Files:**
- Modify: `Popout.lua`

- [ ] **Step 1: Modify `Popout:Show`**

Replace the `frame:SetPoint(...)` block:

```lua
function Popout:Show(slot, invSlotID)
  local cands = SlotPeek.BagIndex:GetCandidates(invSlotID)
  SlotPeek.BagIndex:SortByScore(cands)
  frame.header:SetText(("%s — %d items"):format(slot:GetName():gsub("Character",""):gsub("Slot",""), #cands))

  frame:ClearAllPoints()
  if GameTooltip:IsShown() and GameTooltip:GetOwner() == slot then
    -- anchor below tooltip
    frame:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", 0, -2)
  else
    -- empty slot — anchor next to slot frame
    frame:SetPoint("TOPLEFT", slot, "TOPRIGHT", 8, 0)
  end
  frame:Show()
end
```

- [ ] **Step 2: In-game smoke test**

`/reload`. Hover a slot with an item: expect popout below the GameTooltip. Hover an empty slot (e.g. shirt — but we excluded that; use a deliberately-empty equippable slot like ranged on a non-hunter): expect popout to the right of the slot.

- [ ] **Step 3: Commit**

```bash
git add Popout.lua
git commit -m "Popout: anchor below GameTooltip when slot has tooltip, beside slot when empty"
```

---

## Task 12: Popout — row pool with non-secure preview rows

**Files:**
- Modify: `Popout.lua`

The row pool will be expanded to secure buttons in Task 14; this task lays down the visual layout with non-secure rows.

- [ ] **Step 1: Add row creation helper**

In `Popout.lua`, near the top after `SLOT_TO_INVSLOT`:

```lua
local ROW_HEIGHT = 24
local ROW_WIDTH = 200
local MAX_ROWS = 30

local function makePreviewRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(ROW_WIDTH, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 8, -28 - (index - 1) * (ROW_HEIGHT + 2))

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 0, 0)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.name:SetWidth(ROW_WIDTH - 80)
  row.name:SetJustifyH("LEFT")

  row.delta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.delta:SetPoint("RIGHT", -4, 0)

  row.bestBorder = row:CreateTexture(nil, "BACKGROUND")
  row.bestBorder:SetAllPoints(row)
  row.bestBorder:SetColorTexture(1, 0.82, 0, 0.25)
  row.bestBorder:Hide()

  return row
end
```

- [ ] **Step 2: Modify `CreateFrame` to allocate row pool**

Replace the existing `CreateFrame` body's tail with:

```lua
function Popout:CreateFrame()
  frame = CreateFrame("Frame", "SlotPeekPopoutFrame", UIParent, "BackdropTemplate")
  frame:SetSize(ROW_WIDTH + 16, 40)
  frame:SetFrameStrata("DIALOG")
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

  frame.rows = {}
  for i = 1, MAX_ROWS do
    frame.rows[i] = makePreviewRow(frame, i)
    frame.rows[i]:Hide()
  end
end
```

- [ ] **Step 3: Update `Popout:Show` to populate rows**

Replace `Popout:Show` with:

```lua
function Popout:Show(slot, invSlotID)
  local cands = SlotPeek.BagIndex:GetCandidates(invSlotID)
  SlotPeek.BagIndex:SortByScore(cands)

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
    row.name:SetText(c.itemLink:match("%[(.-)%]") or "?")
    row.name:SetTextColor(r, g, b)

    local score = SlotPeek.PawnAdapter:Score(c.itemLink)
    if score and equippedScore and equippedScore > 0 then
      local pct = (score - equippedScore) / equippedScore * 100
      row.delta:SetText(("%+0.1f%%"):format(pct))
      if pct > 0 then row.delta:SetTextColor(0.4, 1, 0.4)
      elseif pct < 0 then row.delta:SetTextColor(1, 0.5, 0.5)
      else row.delta:SetTextColor(1, 1, 1) end
    elseif score then
      row.delta:SetText(tostring(math.floor(score)))
      row.delta:SetTextColor(1, 1, 1)
    else
      row.delta:SetText("…")
      row.delta:SetTextColor(0.7, 0.7, 0.7)
    end

    row.bestBorder:SetShown(i == 1 and n > 0)
    row:Show()
  end

  frame:SetHeight(28 + n * (ROW_HEIGHT + 2) + 8)
  frame.header:SetText(("%s — %d items"):format(
    slot:GetName():gsub("Character",""):gsub("Slot",""), #cands))

  frame:ClearAllPoints()
  if GameTooltip:IsShown() and GameTooltip:GetOwner() == slot then
    frame:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", 0, -2)
  else
    frame:SetPoint("TOPLEFT", slot, "TOPRIGHT", 8, 0)
  end
  frame:Show()
end
```

- [ ] **Step 4: Smoke test**

`/reload`. Hover Head slot — popout should now show all helms in your bags as rows with icon + name + score delta. Best item (top of sorted list) has gold border tint.

- [ ] **Step 5: Commit**

```bash
git add Popout.lua
git commit -m "Popout: row pool with icon/name/delta and best-row gold border"
```

---

## Task 13: Popout — model preview on row hover

**Files:**
- Modify: `Popout.lua`

- [ ] **Step 1: Add hover handlers in `makePreviewRow`**

Replace `makePreviewRow` body's `return row` line with:

```lua
  row:SetScript("OnEnter", function(self)
    if self.itemLink then
      GameTooltip:SetHyperlink(self.itemLink)
      if CharacterModelFrame then
        CharacterModelFrame:TryOn(self.itemLink)
      end
    end
  end)
  row:SetScript("OnLeave", function(self)
    if CharacterModelFrame then
      CharacterModelFrame:Undress()
      CharacterModelFrame:Dress()
    end
  end)
  row:EnableMouse(true)
  return row
```

- [ ] **Step 2: Store itemLink on each row in `Show`**

In the population loop in `Popout:Show`, after `row.bestBorder:SetShown(...)`:

```lua
    row.itemLink = c.itemLink
```

- [ ] **Step 3: Revert model preview on Popout:Hide**

Modify:

```lua
function Popout:Hide()
  frame:Hide()
  if CharacterModelFrame then
    CharacterModelFrame:Undress()
    CharacterModelFrame:Dress()
  end
end
```

- [ ] **Step 4: Centralize the revert routine and hook all leak paths**

Add to `Popout.lua`:

```lua
function Popout:RevertModel()
  if CharacterModelFrame then
    CharacterModelFrame:Undress()
    CharacterModelFrame:Dress()
  end
end
```

Update `Popout:Hide` to call it:

```lua
function Popout:Hide()
  if unlockTooltip then unlockTooltip() end  -- defined in Task 15
  frame:Hide()
  self:RevertModel()
end
```

Replace the row `OnLeave` body in `makePreviewRow` to call `SlotPeek.Popout:RevertModel()` instead of inlining `Undress`/`Dress`.

In `Popout:OnEnable` after `self:Attach()`:

```lua
  if CharacterFrame then
    CharacterFrame:HookScript("OnHide", function() self:Hide() end)
  end
  SlotPeek:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() self:RevertModel() end)
```

This closes the leak path called out in DESIGN.md §5.5 / §7: equipping anything anywhere — including via the popout itself — reverts the preview to the live model state.

- [ ] **Step 5: Smoke test**

`/reload`. Open character pane. Hover Head → popout shows. Hover a row → character model swaps to show that helm. Move cursor to next row → model swaps. Leave popout → model reverts. Close character pane while a row is hovered → no stale preview when you reopen. Equip an item via drag-from-bag while popout is open → model immediately reverts.

- [ ] **Step 6: Commit**

```bash
git add Popout.lua
git commit -m "Popout: live model preview on row hover; revert via Undress/Dress on all leak paths"
```

---

## Task 14: Popout — secure click-to-equip overlay

**Files:**
- Modify: `Popout.lua`

This is the trickiest task and the central combat-lockdown design from DESIGN.md §5.5. We do **not** replace the preview rows — they remain the always-visible display layer. Instead, we add a parallel pool of `SecureActionButtonTemplate` Buttons that *overlay* the preview rows when out of combat, providing click-to-equip. The secure overlay lives inside its own non-secure Frame container so we can show/hide the overlay as a whole via the container (combat-safe — non-secure parent toggling is allowed).

Pool architecture:
- `frame.rows[1..30]` (preview rows from Task 12) — non-secure Frame children of `frame`. ALWAYS used for visuals. NEVER protected.
- `frame.clickContainer` — non-secure child of `frame`. Holds the secure overlay buttons. We can toggle its `:Show`/`:Hide` in any state.
- `frame.clickRows[1..30]` — `SecureActionButtonTemplate` Button children of `frame.clickContainer`. Each `SetAllPoints(frame.rows[i])` so it overlays preview row `i`. Provides the click. No visuals of its own.

Out of combat: `clickContainer:Show()`, attributes refreshed via `RunSafe`. Click hits the secure button → equips.

In combat: `clickContainer` keeps whatever state it had — typically Shown if popout was open out of combat, Hidden otherwise. We make sure on `PLAYER_REGEN_DISABLED` it gets hidden (out of combat last operation possible) so combat-time hovers are display-only. Task 18 wires that.

- [ ] **Step 1: Add `clickContainer` and `clickRows` allocation in `CreateFrame`**

Insert the following after the `frame.rows[i]` allocation loop (before `end` of `CreateFrame`):

```lua
  frame.clickContainer = CreateFrame("Frame", nil, frame)
  frame.clickContainer:SetAllPoints(frame)

  frame.clickRows = {}
  for i = 1, MAX_ROWS do
    local row = CreateFrame("Button", "SlotPeekClickRow" .. i, frame.clickContainer, "SecureActionButtonTemplate")
    row:SetAllPoints(frame.rows[i])
    row:RegisterForClicks("LeftButtonUp")

    row:HookScript("OnEnter", function(self)
      local pr = frame.rows[i]
      if pr.itemLink then
        GameTooltip:ClearLines()
        GameTooltip:SetHyperlink(pr.itemLink)
        GameTooltip:Show()
        if CharacterModelFrame then CharacterModelFrame:TryOn(pr.itemLink) end
      end
    end)
    row:HookScript("OnLeave", function(self)
      SlotPeek.Popout:RevertModel()
    end)
    row:HookScript("PostClick", function(self)
      local pr = frame.rows[i]
      if pr.isBank then
        UIErrorsFrame:AddMessage("Item is in your bank — withdraw it to equip.", 1.0, 0.82, 0)
      else
        SlotPeek.Popout:Hide()
      end
    end)

    frame.clickRows[i] = row
  end
```

Note: hover/click handlers on the secure button reference data stored on the corresponding **preview row** (`frame.rows[i].itemLink`, `.isBank`). The preview row is always populated; the secure overlay is just the click target. This means the hover handlers on the preview rows from Task 13 are now duplicated by the click row's hooks — that's intentional, because in combat the click rows may be hidden (then preview rows' own hover handlers take over).

- [ ] **Step 2: Set secure attributes and visibility during `Popout:Show`**

In the population loop in `Popout:Show`, after assigning `row.itemLink = c.itemLink` (where `row` is the preview row from `frame.rows[i]`), add:

```lua
    local clickRow = frame.clickRows[i]
    SlotPeek.CombatGuard:RunSafe(function()
      if c.source == "bags" then
        clickRow:SetAttribute("type", "item")
        clickRow:SetAttribute("item", c.bag .. " " .. c.slot)
      else
        clickRow:SetAttribute("type", nil)
        clickRow:SetAttribute("item", nil)
      end
      clickRow:Show()
    end)
```

For unused rows (index > n), wrap their hide too:

```lua
  for i = n + 1, MAX_ROWS do
    SlotPeek.CombatGuard:RunSafe(function()
      frame.clickRows[i]:Hide()
    end)
  end
```

The preview rows' visibility (`frame.rows[i]:Show()`/`:Hide()`) is **non-secure** and can run unconditionally — that's still true. Only the `clickRows` operations need `RunSafe`.

- [ ] **Step 3: Mark preview rows with bank-state for the click handler**

In the population loop in `Popout:Show`, after `row.itemLink = c.itemLink`:

```lua
    row.isBank = (c.source == "bank")
```

(This was previously a Task 17 step; moved here so the click overlay's `PostClick` from Step 1 has the data it needs immediately.)

- [ ] **Step 4: Smoke test — out of combat**

`/reload`. Open character pane. Hover Head slot → popout. Click any row → that helm equips, popout dismisses, no error. Confirm via `/dump GetInventoryItemLink("player", INVSLOT_HEAD)` or visual inspection.

- [ ] **Step 5: Smoke test — combat lockdown (preview-only mode)**

Wait for Task 18 before fully testing combat. For now, after entering combat: hover a slot, popout still appears, but if `clickContainer` happens to be shown, clicks may equip stale items. We'll close that gap in Task 18 by hiding `clickContainer` at `PLAYER_REGEN_DISABLED`. Test only out-of-combat behavior in this task.

- [ ] **Step 6: Commit**

```bash
git add Popout.lua
git commit -m "Popout: SecureActionButtonTemplate overlay pool for click-to-equip"
```

---

## Task 15: Popout — GameTooltip lock during popout open

**Files:**
- Modify: `Popout.lua`

- [ ] **Step 1: Add tooltip lock state**

At the top of `Popout.lua` after `local frame`:

```lua
local tooltipLockedFor
local origSetOwner
```

- [ ] **Step 2: Add lock/unlock helpers**

```lua
local function lockTooltip(slot)
  if origSetOwner then return end
  origSetOwner = GameTooltip.SetOwner
  tooltipLockedFor = slot
  GameTooltip.SetOwner = function(self, owner, anchor, x, y)
    -- allow re-show on the same owner or anything inside our popout (preview rows, click rows, container)
    if owner == tooltipLockedFor or owner == frame
       or (owner.GetParent and (owner:GetParent() == frame or owner:GetParent() == frame.clickContainer)) then
      return origSetOwner(self, owner, anchor, x, y)
    end
    -- silently ignore re-anchor attempts to other frames
  end
end

local function unlockTooltip()
  if origSetOwner then
    GameTooltip.SetOwner = origSetOwner
    origSetOwner = nil
    tooltipLockedFor = nil
  end
end
```

- [ ] **Step 3: Call lock/unlock in Show/Hide**

Inside `Popout:Show`, after the `frame:Show()` line:

```lua
  lockTooltip(slot)
```

Inside `Popout:Hide`, at the top:

```lua
  unlockTooltip()
```

- [ ] **Step 4: Hover-row should set tooltip to row's item without re-anchoring**

The click-row `OnEnter` from Task 14 Step 1 already uses the safe pattern (`ClearLines` + `SetHyperlink` + `Show`). Update the **preview-row** `OnEnter` from Task 13 (in `makePreviewRow`) to match — replace `GameTooltip:SetHyperlink(self.itemLink)` with:

```lua
      GameTooltip:ClearLines()
      GameTooltip:SetHyperlink(self.itemLink)
      GameTooltip:Show()
```

Both row pools now share the same defensive tooltip update pattern. `SetHyperlink` doesn't re-anchor on its own; the lock from Step 2 guards any internal tooltip code that might try.

- [ ] **Step 5: Smoke test**

`/reload`. Hover Head slot → tooltip + popout. Move cursor to a row → tooltip switches to that item's stats but stays anchored above the popout. Move cursor off → tooltip and popout dismiss together; tooltip becomes free again (verify by hovering a different slot — its tooltip anchors correctly).

If anything goes weird with the tooltip (stuck open, no longer anchors), `/slotpeek test` includes a sentinel for tooltip lock leak from Task 22 — for now, manual `/reload` is the recovery.

- [ ] **Step 6: Commit**

```bash
git add Popout.lua
git commit -m "Popout: lock GameTooltip in place while popout is open"
```

---

## Task 16: BagIndex events + index refresh

**Files:**
- Modify: `BagIndex.lua`
- Modify: `Core.lua`

- [ ] **Step 1: Add candidate cache invalidation**

In `BagIndex.lua`, near top:

```lua
local candidateCache = {}
local refreshScheduled = false

function BagIndex:Refresh()
  candidateCache = {}
  refreshScheduled = false
end

function BagIndex:ScheduleRefresh()
  if refreshScheduled then return end
  refreshScheduled = true
  C_Timer.After(0, function() self:Refresh() end)
end
```

Modify `GetCandidates` to use the cache:

```lua
function BagIndex:GetCandidates(invSlotID)
  if candidateCache[invSlotID] then return candidateCache[invSlotID] end
  -- ... existing body ...
  candidateCache[invSlotID] = result
  return result
end
```

- [ ] **Step 2: Register events in `Core.lua`**

Add a `BagIndex:OnEnable` method:

```lua
function BagIndex:OnEnable()
  SlotPeek:RegisterEvent("BAG_UPDATE_DELAYED", function() self:ScheduleRefresh() end)
  SlotPeek:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() self:ScheduleRefresh() end)
  SlotPeek:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() self:ScheduleRefresh() end)
end
```

In `Core.lua`'s `OnEnable`:

```lua
  self.BagIndex:OnEnable()
```

- [ ] **Step 3: Smoke test**

`/reload`. Open character pane, hover Head slot. Note items shown. Have your character pick up or destroy a helm in bags. Hover Head again — list should reflect the change.

- [ ] **Step 4: Commit**

```bash
git add BagIndex.lua Core.lua
git commit -m "BagIndex: invalidation cache, event-driven refresh on bag/equip changes"
```

---

## Task 17: Bank cache + bank rows

**Files:**
- Modify: `BagIndex.lua`
- Modify: `Popout.lua`
- Modify: `Core.lua`
- Modify: `tests/assertions.lua`

- [ ] **Step 1: Bank state and snapshot in `BagIndex.lua`**

```lua
local bankOpen = false

function BagIndex:OnBankOpen()
  bankOpen = true
  self:SnapshotBank()
end

function BagIndex:OnBankClose()
  bankOpen = false
end

function BagIndex:SnapshotBank()
  local cache = SlotPeek.db.char.bankCache
  for k in pairs(cache) do cache[k] = nil end
  -- bank main container
  for slot = 1, C_Container.GetContainerNumSlots(BANK_CONTAINER) or 0 do
    local info = C_Container.GetContainerItemInfo(BANK_CONTAINER, slot)
    if info and info.hyperlink then
      cache[BANK_CONTAINER] = cache[BANK_CONTAINER] or {}
      cache[BANK_CONTAINER][slot] = info.hyperlink
    end
  end
  -- bank bags
  for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.hyperlink then
        cache[bag] = cache[bag] or {}
        cache[bag][slot] = info.hyperlink
      end
    end
  end
  self:Refresh()
end
```

- [ ] **Step 2: Include bank items in `GetCandidates`**

Inside `GetCandidates`, after the bag scan loop, add:

```lua
  -- bank: live if open, cached otherwise
  if bankOpen then
    -- bank main + bank bags via direct API
    local function scanBag(bag)
      local n = C_Container.GetContainerNumSlots(bag) or 0
      for slot = 1, n do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.hyperlink then
          consider({ itemLink = info.hyperlink, bag = bag, slot = slot,
                     itemID = info.itemID, icon = info.iconFileID, source = "bank" })
        end
      end
    end
    scanBag(BANK_CONTAINER)
    for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do scanBag(bag) end
  else
    -- cached
    for bag, slots in pairs(SlotPeek.db.char.bankCache) do
      for slot, link in pairs(slots) do
        consider({ itemLink = link, bag = bag, slot = slot, source = "bank" })
      end
    end
  end
```

- [ ] **Step 3: Wire bank events**

In `BagIndex:OnEnable`:

```lua
  SlotPeek:RegisterEvent("BANKFRAME_OPENED", function() self:OnBankOpen() end)
  SlotPeek:RegisterEvent("BANKFRAME_CLOSED", function() self:OnBankClose() end)
```

- [ ] **Step 4: Bank-row visual divider in `Popout:Show`**

In the population loop in `Popout:Show`, add a divider before the first bank row. Track when we transition from `bags` → `bank`:

Add a divider Frame to `CreateFrame`:

```lua
  frame.divider = frame:CreateTexture(nil, "OVERLAY")
  frame.divider:SetColorTexture(0.5, 0.5, 0.5, 0.5)
  frame.divider:SetHeight(1)
  frame.divider:Hide()
```

In `Popout:Show`, populate rows in the order returned by `GetCandidates` (already sorted by score), and place the divider at the boundary. Re-sort so bag items come first within each tier? No — keep score order; just mark a divider once. Replace the population loop with logic that finds the first bank row index:

```lua
  local firstBankIndex
  for i, c in ipairs(cands) do
    if c.source == "bank" then firstBankIndex = i; break end
  end

  -- existing population loop ...

  if firstBankIndex and firstBankIndex <= n then
    local row = frame.rows[firstBankIndex]
    frame.divider:ClearAllPoints()
    frame.divider:SetPoint("TOPLEFT", row, "TOPLEFT", -4, 1)
    frame.divider:SetPoint("TOPRIGHT", row, "TOPRIGHT", 4, 1)
    frame.divider:Show()
  else
    frame.divider:Hide()
  end
```

- [ ] **Step 5: Verify bank-aware click (already wired in Task 14)**

Task 14 already wired the click overlay's `PostClick` to check `pr.isBank` and toast or hide accordingly, and Task 14 sets `row.isBank` in the population loop. No additional code needed here — this step is just confirmation that those Task 14 paths are in place; if the implementer skipped them, fix them now.

- [ ] **Step 6: Add assertion**

```lua
SlotPeek:RegisterAssertion("bank cache exists after BANKFRAME_OPENED simulation", function()
  -- can't fire BANKFRAME_OPENED without being at a bank, so skip if cache is empty
  -- this assertion just verifies the schema
  assert(type(SlotPeek.db.char.bankCache) == "table")
end)
```

- [ ] **Step 7: Smoke test**

Visit a bank in-game. Open it. Notice popout now includes bank items. Close bank. Walk away. Open character pane → popout still shows bank items (cached) under a divider. Click a bank row → toast appears, popout stays open. Click a bag row → equips, popout dismisses.

- [ ] **Step 8: Commit**

```bash
git add BagIndex.lua Popout.lua tests/assertions.lua
git commit -m "Add bank cache, bank-row divider, and toast-on-click for bank items"
```

---

## Task 18: Combat-state visibility toggle for secure overlay + in-combat badge

**Files:**
- Modify: `Popout.lua`

Per DESIGN.md §5.5: in combat the popout shows non-secure preview rows only — no clickable equip. We achieve this by hiding the entire `clickContainer` (the non-secure parent of the secure overlay buttons) on `PLAYER_REGEN_DISABLED`. Hiding a non-secure parent is itself non-secure, even though its children are protected — which is the trick. With `clickContainer` hidden, the secure rows receive no mouse events; the preview rows underneath are what the user sees and hovers.

- [ ] **Step 1: Add combat badge in `CreateFrame`**

After the `frame.divider` creation (or near other header elements):

```lua
  frame.combatBadge = frame:CreateFontString(nil, "OVERLAY", "GameFontRed")
  frame.combatBadge:SetPoint("TOPRIGHT", -8, -8)
  frame.combatBadge:SetText("[combat]")
  frame.combatBadge:Hide()
```

- [ ] **Step 2: Add hover handlers on preview rows so combat-mode hover still drives tooltip + model preview**

In Task 13 we added `OnEnter`/`OnLeave` on preview rows. In Task 14 we ALSO added them on click rows. When the click rows are visible (out of combat) they receive the mouse events instead of the preview rows beneath. When `clickContainer` is hidden (in combat), preview rows receive mouse events directly. Both paths must drive the same tooltip + model preview behavior.

Verify the preview-row handlers from Task 13 still apply (they do — preview rows always exist). No new code unless they were removed.

- [ ] **Step 3: Toggle clickContainer visibility on combat events in `Popout:OnEnable`**

```lua
  SlotPeek:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    -- Last-second non-secure hide of the click overlay before lockdown begins.
    -- Hiding a non-secure parent disables click receipt for protected children.
    if frame.clickContainer then frame.clickContainer:Hide() end
    frame.combatBadge:Show()
  end)
  SlotPeek:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if frame.clickContainer then frame.clickContainer:Show() end
    frame.combatBadge:Hide()
    -- Force a refresh of the popout's secure rows if it's currently visible
    if frame:IsShown() and self._lastSlot then
      self:Show(self._lastSlot, self._lastInvSlot)
    end
  end)
```

- [ ] **Step 4: Track the last-shown slot for the regen refresh**

In `Popout:Show`, near the start (right after computing `cands`):

```lua
  self._lastSlot = slot
  self._lastInvSlot = invSlotID
```

- [ ] **Step 5: Toggle badge in `Show`**

At the top of `Popout:Show`:

```lua
  frame.combatBadge:SetShown(SlotPeek.CombatGuard:IsLocked())
```

- [ ] **Step 6: Smoke test**

Out of combat: hover slot, click row, equips. Pull a low-level mob (`PLAYER_REGEN_DISABLED` fires) — `clickContainer` hides, badge shows `[combat]`. Hover a row in the popout: tooltip and model preview both still work (driven by preview rows now). Click a row: nothing happens (no red error frame, no equip). End combat (`PLAYER_REGEN_ENABLED`) — badge disappears, `clickContainer` shows again, hover the same slot again to refresh secure rows; click now equips. Verify no taint errors.

If you want to be extra strict, run `/console scriptErrors 1` and `/etrace` (or BugSack) during the test.

- [ ] **Step 7: Commit**

```bash
git add Popout.lua
git commit -m "Popout: hide click overlay on PLAYER_REGEN_DISABLED, show on PLAYER_REGEN_ENABLED"
```

---

## Task 19: Pawn retry — patch row scores in place

**Files:**
- Modify: `Popout.lua`

- [ ] **Step 1: Listen for `SlotPeek_PAWN_RESOLVED`**

In `Popout:OnEnable`:

```lua
  SlotPeek:RegisterMessage("SlotPeek_PAWN_RESOLVED", function() self:RefreshScores() end)
```

- [ ] **Step 2: Add `RefreshScores` method**

```lua
function Popout:RefreshScores()
  if not frame:IsShown() then return end
  for i, row in ipairs(frame.rows) do
    if row:IsShown() and row.itemLink then
      local score = SlotPeek.PawnAdapter:Score(row.itemLink)
      if score then
        local current = row.delta:GetText()
        if current == "…" then
          row.delta:SetText(tostring(math.floor(score)))
        end
      end
    end
  end
end
```

- [ ] **Step 3: Smoke test**

Open a fresh client (`/reload`). Quickly hover a slot before items have time to populate from the WoW client cache (works best for items recently looted). Score column should show "…" first, then refresh to real scores within ~0.5–1s.

- [ ] **Step 4: Commit**

```bash
git add Popout.lua
git commit -m "Popout: refresh row scores when Pawn resolves cached-late items"
```

---

## Task 20: Slash command additions — refresh and debug

**Files:**
- Modify: `Core.lua`

- [ ] **Step 1: Extend slash handler**

```lua
function SlotPeek:HandleSlash(input)
  input = input and input:lower() or ""
  if input == "test" then
    self:RunAssertions()
  elseif input == "config" then
    InterfaceOptionsFrame_OpenToCategory("SlotPeek")
    InterfaceOptionsFrame_OpenToCategory("SlotPeek")
  elseif input == "refresh" then
    self.BagIndex:Refresh()
    self:Print("index refreshed")
  elseif input == "debug" then
    self.db.profile.debug = not self.db.profile.debug
    self:Print("debug = " .. tostring(self.db.profile.debug))
  else
    self:Print("commands: /slotpeek test | config | refresh | debug")
  end
end
```

- [ ] **Step 2: Smoke test**

`/slotpeek refresh` → "index refreshed". `/slotpeek debug` → toggles. `/slotpeek` (no arg) → command list.

- [ ] **Step 3: Commit**

```bash
git add Core.lua
git commit -m "Core: refresh and debug slash subcommands"
```

---

## Task 21: Config UI

**Files:**
- Create: `Config.lua`
- Modify: `Core.lua`
- Modify: `SlotPeek.toc`

- [ ] **Step 1: Write `Config.lua`**

```lua
local SlotPeek = SlotPeek
local Config = {}
SlotPeek.Config = Config

function Config:OnEnable()
  local options = {
    name = "SlotPeek",
    type = "group",
    args = {
      enabled = {
        type = "toggle",
        name = "Enable",
        order = 1,
        get = function() return SlotPeek.db.profile.enabled end,
        set = function(_, v) SlotPeek.db.profile.enabled = v end,
      },
      hoverDelay = {
        type = "range",
        name = "Hover delay (s)",
        min = 0.05, max = 0.5, step = 0.01,
        order = 2,
        get = function() return SlotPeek.db.profile.hoverDelay end,
        set = function(_, v) SlotPeek.db.profile.hoverDelay = v end,
      },
      scaleName = {
        type = "select",
        name = "Pawn scale",
        order = 3,
        values = function()
          local t = {}
          if PawnGetAllScales then
            for name, _ in pairs(PawnGetAllScales()) do
              if PawnIsScaleVisible(name) then t[name] = name end
            end
          end
          return t
        end,
        get = function() return SlotPeek.db.profile.scaleName end,
        set = function(_, v) SlotPeek.db.profile.scaleName = v end,
      },
      debug = {
        type = "toggle",
        name = "Debug",
        order = 4,
        get = function() return SlotPeek.db.profile.debug end,
        set = function(_, v) SlotPeek.db.profile.debug = v end,
      },
      clearBank = {
        type = "execute",
        name = "Clear bank cache",
        order = 5,
        func = function()
          for k in pairs(SlotPeek.db.char.bankCache) do SlotPeek.db.char.bankCache[k] = nil end
          SlotPeek:Print("bank cache cleared")
        end,
      },
    },
  }
  LibStub("AceConfig-3.0"):RegisterOptionsTable("SlotPeek", options)
  LibStub("AceConfigDialog-3.0"):AddToBlizOptions("SlotPeek", "SlotPeek")
end
```

- [ ] **Step 2: Boot from `Core.lua`**

In `OnEnable`:

```lua
  self.Config:OnEnable()
```

- [ ] **Step 3: Add to TOC**

After `Popout.lua`, before `tests\assertions.lua`:

```
Popout.lua
Config.lua
tests\assertions.lua
```

- [ ] **Step 4: Smoke test**

`/slotpeek config` opens the Interface Options panel to SlotPeek. Toggle enable, change hover delay, pick a Pawn scale, hit "Clear bank cache" — verify each via in-game behavior or `/dump SlotPeek.db.profile.hoverDelay`.

- [ ] **Step 5: Commit**

```bash
git add Config.lua Core.lua SlotPeek.toc
git commit -m "Add AceConfig options panel"
```

---

## Task 22: README, TESTING.md, smoke matrix

**Files:**
- Create: `README.md`
- Create: `TESTING.md`

- [ ] **Step 1: Write `README.md`**

```markdown
# SlotPeek

Hover an equipment slot in the character pane to see every item in your bags and bank that fits, scored by Pawn, with click-to-equip and live model preview.

For WoW Burning Crusade Classic Anniversary (2.5.5).

## Install

1. Drop the `SlotPeek/` folder into `Interface\AddOns\`.
2. Ensure [Pawn](https://www.curseforge.com/wow/addons/pawn) is installed and has a scale configured for your class/spec.
3. Launch the game.

## Use

1. Open the character pane (`C`).
2. Hover any equipment slot. After ~150 ms, a list of alternatives appears below the standard tooltip.
3. Hover a row — character model previews that item, tooltip switches to show the candidate's stats.
4. Click a bag row — equips. Click a bank row — toast prompts you to withdraw it first.

## Slash commands

- `/slotpeek` — list commands
- `/slotpeek config` — open options panel
- `/slotpeek test` — run in-game assertions
- `/slotpeek refresh` — force re-scan of bags
- `/slotpeek debug` — toggle debug logging

## License

MIT — see `LICENSE`.

## Design

See `DESIGN.md` for the full design document.
```

- [ ] **Step 2: Write `TESTING.md`**

```markdown
# SlotPeek — Testing

## `/slotpeek test`

Runs the in-game assertion suite. Expected: all assertions PASS.

## Manual smoke matrix

| # | Scenario | Expected |
|---|---|---|
| 1 | Hover Head with multiple helms in bags | Popout below tooltip; best highlighted; scores in delta column |
| 2 | Hover Finger0 while Finger1 has a ring | Finger1's ring excluded |
| 3 | Hover MainHand while a 2H is equipped | OH popout shows empty / "no alternatives" |
| 4 | Click a bag-resident row | Item equipped, popout dismisses, no errors |
| 5 | Click a bank-resident row | Toast appears, popout stays open |
| 6 | Hover row → cursor leaves | Model reverts to live equipment |
| 7 | Open popout, enter combat | Header shows `[combat]` badge; model preview still works |
| 8 | Hover an empty slot | Popout anchors to slot (no tooltip), shows alternatives |
| 9 | `/reload` after Pawn disabled | SlotPeek refuses to load |
| 10 | Pawn loaded, no scale visible | No delta column / shows raw scores; footer prompt |

## Combat lockdown stress test

Pull a low-level mob. While in combat:
- Hover all 17 slots — popout appears with `[combat]` badge.
- Try clicking rows that you'd hovered pre-combat — equip should succeed.
- Watch for any red "interface action failed because of an addon" errors — there should be none.

End combat. Verify popout returns to normal mode.

## Performance

`/dump debugprofilestop()` before and after `/slotpeek refresh`. With ~150 items in bags + cached bank, the delta should be under 50 ms.
```

- [ ] **Step 3: Commit**

```bash
git add README.md TESTING.md
git commit -m "Docs: README and TESTING smoke matrix"
```

---

## Task 23: Final polish — pcall safety net, error handling

**Files:**
- Modify: `Popout.lua`

- [ ] **Step 1: Wrap `Show` in pcall to prevent tooltip-lock leak**

Replace the `Popout:Show` invocation site (in `OnSlotEnter`) with a pcall'd version:

In `OnSlotEnter`:

```lua
  hoverTimer = C_Timer.NewTimer(delay, function()
    local ok, err = pcall(function() self:Show(slot, invSlotID) end)
    if not ok then
      SlotPeek:Print("popout error: " .. tostring(err))
      self:Hide()  -- ensures tooltip lock released even on partial show
    end
  end)
```

- [ ] **Step 2: Pawn-not-ready guard in `OnEnable`**

In `Core.lua`'s `OnEnable`:

```lua
  if not PawnIsReady or not PawnIsReady() then
    self:Print("WARNING: Pawn not ready. SlotPeek will run with degraded scoring.")
  end
```

- [ ] **Step 3: Final smoke**

`/reload`, `/slotpeek test` — all assertions PASS. Hover every slot, click a row, swap a 2H, visit bank, walk away, hover slots again. No errors.

- [ ] **Step 4: Commit**

```bash
git add Popout.lua Core.lua
git commit -m "Polish: pcall safety net around Show; Pawn-not-ready warning"
```

---

## Task 24: Push and tag v0.1.0

- [ ] **Step 1: Verify clean working tree**

```bash
git status
```

Expected: nothing to commit, working tree clean.

- [ ] **Step 2: Push to origin**

```bash
git push origin main
```

- [ ] **Step 3: Tag**

```bash
git tag -a v0.1.0 -m "Initial release: SlotPeek v0.1.0"
git push origin v0.1.0
```

- [ ] **Step 4: Update TOC version**

Edit `SlotPeek.toc`:

```
## Version: 0.1.0
```

Commit:

```bash
git add SlotPeek.toc
git commit -m "Bump version to 0.1.0"
git push origin main
```

---

## Done criteria

- All `/slotpeek test` assertions PASS.
- All 10 manual smoke matrix scenarios behave as specified in `TESTING.md`.
- Combat lockdown stress test produces no red errors.
- Performance: `BagIndex:Refresh` + `GetCandidates` for all 17 slots under 50 ms with realistic bag size.
- v0.1.0 tagged on `origin/main`.

## Things explicitly NOT done in this plan (per DESIGN.md §9)

- `PawnRegisterThirdPartyBag` integration for upgrade arrows.
- Cross-character bank caching.
- Drag-from-popout repositioning.
- Multi-slot comparison (rings as a pair).
- Configurable themes / LibSharedMedia.
- Localization (English-only).
