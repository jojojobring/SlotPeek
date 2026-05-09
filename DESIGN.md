# SlotPeek — Design

**Date:** 2026-05-09
**Target client:** WoW Burning Crusade Classic Anniversary, patch 2.5.5 (interface `20505`)
**Lua:** 5.1
**Required dependency:** Pawn (for item scoring)
**Embedded libraries:** Ace3 (AceAddon, AceEvent, AceDB, AceConfig + Dialog/Cmd/Registry, AceConsole, AceGUI), LibStub, CallbackHandler-1.0

---

## 1. Problem and goals

When choosing gear in WoW, the existing UI forces the player to open their bags, hunt visually for items that fit a given slot, hover each one to read stats, and mentally compare against what they have equipped. SlotPeek collapses this into a single-hover interaction on the character pane.

Concretely, when the player hovers an equipment slot in `PaperDollFrame`:

1. A popout appears below the standard GameTooltip listing every item in their bags, plus a snapshot cache of their bank, that fits the slot.
2. Each row shows the item icon, name (in quality color), and Pawn score delta vs. the currently-equipped item in that slot.
3. The "best" alternative is visually highlighted (gold border) — defined as the candidate row with the highest Pawn score among the items the popout actually displays (i.e. the top of the sorted list). Pawn's `PawnGetBestItemLink` is consulted as a sanity reference but is *not* the highlight source, because that function returns Pawn's globally-best link which may not be present in the player's bags or cached bank.
4. Hovering a row live-previews that item on the character model (`CharacterModelFrame:TryOn`) and switches the GameTooltip to that row's stats; leaving the row reverts to the live equipment.
5. Clicking a row equips the item, if it's in bags. If it's a cached bank item, a Blizzard-style toast (`UIErrorsFrame:AddMessage`) prompts the player to withdraw it first.

Items the player's class cannot use are filtered out. Cosmetic slots (shirt, tabard) are excluded. The character pane's existing tooltip is reused as the "currently equipped" reference, anchored above the popout.

## 2. UX decisions (resolved during brainstorming)

| Decision | Choice |
|---|---|
| Best-item scoring | Pawn (hard dependency) |
| Bank items | Cached on visit, always visible, divider above bank rows |
| Row content | Icon + name + Pawn score delta |
| Trigger | Hover with 150ms delay |
| Slot scope | All 17 gear slots; skip shirt and tabard |
| Usability filter | Hide items the class cannot use |
| "Currently equipped" presentation | Standard GameTooltip above the popout (locked while popout is open) |
| Anchor | Popout placed below the locked tooltip; for empty slots (no tooltip) anchored to the slot frame directly |
| Architecture | Ace3-based, embedded libs, modular |

## 3. Architecture overview

The runtime has four conceptual layers:

1. **Inventory layer** (`BagIndex.lua`) — keeps an in-memory index of every equippable item in bags plus a SavedVariables-backed bank snapshot. Refreshes reactively.
2. **Pawn adapter** (`PawnAdapter.lua`) — the only module that touches Pawn's globals. Exposes `Score(itemLink)`, `BestForSlot(invType)`, `IsReady()`, `ScaleName()`. Owns a retry queue for items not yet in the WoW client cache.
3. **Slot popout UI** (`Popout.lua`) — a non-secure `Frame` containing a pool of `SecureActionButtonTemplate` rows. Hooks `OnEnter`/`OnLeave` on the 17 gear slot frames with a 150ms delay, anchors below GameTooltip, drives the model preview.
4. **Combat guard** (`CombatGuard.lua`) — wraps any operation touching secure buttons. `RunSafe(fn)` runs immediately if out of combat, queues for `PLAYER_REGEN_ENABLED` otherwise.

Plus three thin support modules: `Core.lua` (AceAddon scaffold, slash command), `DB.lua` (AceDB schema), `Config.lua` (AceConfig options table).

## 4. File layout

```
SlotPeek/
├── SlotPeek.toc                 # interface 20505, deps: Pawn; loads Libs first
├── Libs/                        # embedded Ace3 libraries
│   └── Libs.xml                 # <Include> manifest
├── Core.lua                     # AceAddon scaffold, OnInitialize/OnEnable, /slotpeek
├── DB.lua                       # AceDB defaults + saved-vars schema
├── BagIndex.lua                 # bag scan, bank cache, slot-candidates resolver
├── PawnAdapter.lua              # Score(link), BestForSlot(invType), retry queue
├── Popout.lua                   # popout Frame, button pool, model preview, hover logic
├── CombatGuard.lua              # InCombatLockdown wrapper + deferred-refresh queue
├── Config.lua                   # AceConfig options table
├── DESIGN.md                    # this document
└── TESTING.md                   # manual smoke matrix
```

LibStub will arbitrate to the highest version of each Ace3 library available in the client at load time, so embedding does not conflict with a standalone Ace3 addon.

## 5. Modules

### 5.1 Core.lua

```lua
SlotPeek = LibStub("AceAddon-3.0"):NewAddon("SlotPeek", "AceEvent-3.0", "AceConsole-3.0")
```

Owns no state. `OnInitialize` registers the AceDB and Config. `OnEnable` boots the other modules in order: `DB → PawnAdapter → BagIndex → CombatGuard → Popout`. Registers `/slotpeek` slash command with subcommands `config`, `refresh`, `test`, `debug`.

### 5.2 DB.lua

AceDB-3.0 with these defaults:

```lua
defaults = {
  profile = {
    enabled    = true,
    hoverDelay = 0.15,
    scaleName  = nil,        -- nil = auto-pick first visible Pawn scale
    debug      = false,
    dbVersion  = 1,
  },
  char = {
    bankCache = {},          -- [bagId] = { [slot] = itemLink }
  },
}
```

On version bump, wipes `char.bankCache` rather than migrating.

### 5.3 BagIndex.lua

**Public:**

- `Refresh()` — full rescan; idempotent; throttled to once per frame via `C_Timer.After(0, …)`.
- `GetCandidates(invSlotID) → { {itemLink, bag, slot, source}, … }` — items that fit the slot and the class can use, sorted by Pawn delta desc. Cached until next `Refresh`.

**Internal:**

- `IsUsable(itemLink)` — checks **class capability** (not item level): the explicit class restriction tooltip line via a hidden tooltip scanner; weapon proficiency by subclassID; and armor proficiency by subclassID against a class-armor table that includes the level at which the class learns each armor type (e.g. warrior plate at 40, paladin plate at 40, hunter mail at 40, shaman mail at 40). An item is "unusable" only if the player will *never* be able to equip it at the current character's level. We do **not** filter on item required level — items above the player's current level still appear (they're aspirational gear). Result keyed by itemID, cached for the session.
- `CacheBank()` — called on `BANKFRAME_OPENED` for the initial snapshot and on `PLAYERBANKSLOTS_CHANGED` for incremental updates. Writes to `DB.char.bankCache`.

**Slot eligibility table:** maps `invSlotID` → list of accepted `INVTYPE_*` strings. INVSLOT 16 (MainHand) accepts `INVTYPE_2HWEAPON`, `INVTYPE_WEAPONMAINHAND`, `INVTYPE_WEAPON`. INVSLOT 17 (OffHand) accepts `INVTYPE_WEAPONOFFHAND`, `INVTYPE_WEAPON`, `INVTYPE_SHIELD`, `INVTYPE_HOLDABLE` — but if the equipped MH is `INVTYPE_2HWEAPON`, GetCandidates returns an empty list with the header note "two-handed weapon equipped." INVSLOT 18 (Ranged) accepts `INVTYPE_RANGED`, `INVTYPE_RANGEDRIGHT`, `INVTYPE_THROWN`, plus `INVTYPE_RELIC` for druid/paladin/shaman.

For Finger and Trinket slots, the candidate list excludes whatever is currently in the *other* finger/trinket slot to avoid showing "swap with itself" rows.

**Dependencies:** `C_Container.GetContainerItemInfo`, `C_Container.GetContainerNumSlots`, `GetItemInfo`, `GetInventorySlotInfo`, `GetInventoryItemLink`, `DB`. No knowledge of Pawn or UI.

### 5.4 PawnAdapter.lua

**Public:**

- `Score(itemLink) → number|nil` — Pawn score for the active scale. `nil` means "not yet cached, retry later."
- `BestForSlot(invType) → itemLink|nil` — wraps `PawnGetBestItemLink(scaleName, invType)`. **Used only as a sanity reference**, not as the popout's gold-border source. The "best" row in the popout is the highest-scoring *candidate that is actually present in bags or cached bank* — see `Popout.Show` for the highlight logic.
- `IsReady() → bool` — wraps `PawnIsReady`.
- `ScaleName() → string|nil` — `DB.profile.scaleName` if set and visible, otherwise the first scale from `PawnGetAllScales()` for which `PawnIsScaleVisible` returns true.

**Internal:** Retry queue. When `PawnGetItemData(link)` returns nil, the link is added to a pending set and a `C_Timer.NewTicker(0.5, …)` ticks until the set is empty. Each tick re-resolves pending items; resolved items fire a `SlotPeek_PAWN_RESOLVED` callback (AceEvent message) that the popout listens to so it can patch row text in place.

**Dependencies:** Pawn globals (`PawnGetItemData`, `PawnGetSingleValueFromItem`, `PawnGetBestItemLink`, `PawnIsReady`, `PawnGetAllScales`, `PawnIsScaleVisible`), `DB`. No bag or UI knowledge.

### 5.5 Popout.lua

The largest module.

**Public:**

- `Attach()` — installs `HookScript("OnEnter")` and `HookScript("OnLeave")` on the 17 gear slot frames in `OnEnable`.
- `Show(slotFrame)` — anchors the popout, populates rows, locks GameTooltip.
- `Hide()` — restores GameTooltip behavior, reverts model preview if active.

**Internal frame structure:**

```
SlotPeekPopout (Frame, non-secure)
├── Header (FontString)              -- "Head — 4 items, 1 in bank"
├── BadgeIcon (Texture, hidden)       -- in-combat or out-of-date indicator
├── Rows[1..30] (SecureActionButtonTemplate Buttons)
│   ├── Icon (Texture)
│   ├── NameText (FontString)
│   ├── DeltaText (FontString)
│   └── BestBorder (Texture, hidden, gold)
├── Divider (Texture, hidden)         -- shown above bank rows
└── EmptyText (FontString, hidden)    -- "No alternatives"
```

The `Frame` itself is a regular `Frame` (`Show`/`Hide` permitted in combat). The row buttons are `SecureActionButtonTemplate` and *are* protected, so their `SetAttribute`/`Show`/`Hide`/anchoring is gated by `CombatGuard.RunSafe`. The pool starts at 20 rows and grows lazily on demand (creating new secure buttons happens only out of combat; the cap is "all candidates that fit in 30 rows," with overflow truncated and a footer line "30+ items — showing top 30 by Pawn delta").

**Combat-time fallback rows.** When the popout is shown for the first time during combat (no pre-configured secure rows for this slot), `Popout.Show` instead populates the popout with non-secure `Frame` "preview rows" — same icon/name/delta layout, same row-hover model preview, but no click-to-equip. A footer line reads "Out of combat to equip." The previously documented combat scenarios (popout already open, hover starts during combat) both resolve to this single behavior: the popout is always visible on hover, the model preview always works, equip clicks only work when the secure rows have current attributes set out of combat. On `PLAYER_REGEN_ENABLED`, queued `RunSafe` callbacks rebuild the secure rows in place of the preview rows.

**Out-of-combat row population:**

```
for i, candidate in ipairs(candidates) do
  local row = pool[i]
  CombatGuard.RunSafe(function()
    row:SetAttribute("type", "item")
    row:SetAttribute("item", candidate.bag .. " " .. candidate.slot)
    row.Icon:SetTexture(candidate.icon)
    row.NameText:SetText(candidate.coloredName)
    row.DeltaText:SetText(formatDelta(candidate.score, equippedScore))
    row:Show()
  end)
end
```

For bank rows, `type` is set to `"button"` with no `item`, the secure click is therefore a no-op, and a non-secure `OnClick` script fires the toast.

**Hover handling:**

- 150ms timer per slot. `OnEnter` starts a `C_Timer.After`; `OnLeave` cancels it. On expiry, `Show(slotFrame)` runs.
- Grace timer on `OnLeave` of slot OR popout (200ms) before `Hide`. Cursor entering the popout cancels the grace.
- Per-row `OnEnter`/`OnLeave` (non-secure) drive `GameTooltip:SetHyperlink` and `CharacterModelFrame:TryOn` / revert.

**GameTooltip lock:** While the popout is open, we override `GameTooltip:SetOwner` (saving the original) so re-anchor attempts are rejected; restored in `Hide()`. A `pcall` wraps `Show` so an error mid-show cannot leave the override permanently in place.

**Model preview revert:** `CharacterModelFrame:Undress()` then `CharacterModelFrame:Dress()` re-applies the live equipment set. Also called on `Popout.Hide()`, on `CharacterFrame`'s `OnHide`, and on `PLAYER_EQUIPMENT_CHANGED`.

**Dependencies:** `BagIndex`, `PawnAdapter`, `CombatGuard`, `DB`.

### 5.6 CombatGuard.lua

Tiny module. Public surface:

- `RunSafe(fn)` — runs `fn()` immediately if `not InCombatLockdown()`, else appends to a queue replayed on `PLAYER_REGEN_ENABLED`.
- `IsLocked() → bool` — wraps `InCombatLockdown`.

Used by `Popout` to gate `SetAttribute`, `SetParent`, and anchor changes on secure rows.

### 5.7 Config.lua

AceConfig-3.0 options table. Fields:

- Enable (toggle)
- Hover delay (slider, 50–500 ms)
- Pawn scale (dropdown, populated from `PawnGetAllScales`)
- Debug (toggle)
- Clear bank cache (button)

Registered with `AceConfigDialog:AddToBlizOptions` and accessible via `/slotpeek config`.

## 6. Data flows

### Flow A — Bag changes → index refresh

`BAG_UPDATE_DELAYED` / `PLAYER_EQUIPMENT_CHANGED` / `PLAYERBANKSLOTS_CHANGED` → `BagIndex.Refresh()` schedules a `C_Timer.After(0, …)` so coalesced events resolve into one rescan. The rescan walks `0..NUM_BAG_SLOTS` and (if `bankOpen`) `BANK_CONTAINER` and `5..10`, then unions in `DB.char.bankCache` for cached bank items not currently visible. If we're in combat, the index data is rebuilt (non-secure), but the popout's secure attributes can't be re-targeted; the popout (if open) shows an "out of date" badge until `PLAYER_REGEN_ENABLED`.

### Flow B — Bank visit → cache update

`BANKFRAME_OPENED` sets `bankOpen = true` and snapshots every `(bag, slot, itemLink)` into `DB.char.bankCache`. `PLAYERBANKSLOTS_CHANGED` updates incrementally while open. `BANKFRAME_CLOSED` clears `bankOpen` but leaves the cache populated.

### Flow C — Hover slot → popout shown

Cursor enters `CharacterChestSlot` → 150ms timer. On expiry: `Popout.Show` → `BagIndex.GetCandidates(INVSLOT_CHEST)` → for each candidate, `PawnAdapter.Score(link)` (nil placeholders queued for retry) → sort desc by score → grab N rows from the pool → `CombatGuard.RunSafe(setAttributesAndShow)`. If GameTooltip is anchored to the slot, read its `:GetBottom()` and place the popout beneath; lock the tooltip's owner. If the slot is empty, anchor `TOPLEFT` of the popout to `TOPRIGHT` of the slot. A 200ms grace timer on cursor leaving the slot OR the popout drives `Hide`; cursor entering the popout cancels.

### Flow D — Hover popout row → model preview

Cursor enters row → non-secure `OnEnter` → `GameTooltip:SetHyperlink(itemLink)` AND `CharacterModelFrame:TryOn(itemLink)`. Cursor leaves row → `CharacterModelFrame:Undress(); CharacterModelFrame:Dress()`. If the popout itself hides while a row is hovered, `Hide` runs the same revert.

### Flow E — Click row → equip (or toast)

Bag rows: real `SecureActionButtonTemplate` clicks with `type="item"` and `item="<bag> <slot>"`; the engine equips. A non-secure `PostClick` runs `Hide` — this is safe in combat because the popout `Frame` itself is non-secure (combat lockdown only blocks `Hide` on protected frames; our parent Frame is not protected). Bank rows: a non-secure `OnClick` fires `UIErrorsFrame:AddMessage("Item is in your bank — withdraw it to equip.", 1.0, 0.82, 0)` and does NOT dismiss the popout.

## 7. Edge cases and error handling

- **Pawn missing or disabled.** TOC `## Dependencies: Pawn` prevents load. If Pawn is loaded but errors, `OnEnable` checks `PawnIsReady`; on failure logs a warning and disables hooks.
- **No Pawn scale configured.** Fallback: no delta column, sort by item level desc. One-time chat prompt and footer text directing the user to `/slotpeek config`.
- **Item not in WoW client cache.** Row shows icon + "Loading…" + "—". Retry queue patches in place via the `SlotPeek_PAWN_RESOLVED` callback. Cap at 6 retries per item.
- **Combat lockdown.** Single behavior across all combat scenarios: the popout always appears on hover (parent Frame is non-secure), and the model preview always works. Equip clicks only succeed when secure rows have current attributes set out of combat. If the popout is shown for the first time in combat (or for a slot whose secure rows aren't current), `Popout.Show` populates non-secure preview rows that look identical to secure rows except they cannot be clicked to equip; a footer reads "Out of combat to equip." On `PLAYER_REGEN_ENABLED`, queued `RunSafe` callbacks rebuild secure rows so subsequent hovers click-equip normally. If the popout is open as combat starts, the existing rows remain (whatever they were pre-combat); a small red "in combat" badge appears in the header to signal that bag changes since combat-start are not yet reflected.
- **Bank cache stale.** Click on a bank row only ever toasts; never destructive. Refreshed on next `BANKFRAME_OPENED`.
- **Schema migration.** `dbVersion` bump wipes `char.bankCache`.
- **Class restrictions.** Cached tooltip scan for `ITEM_CLASSES_ALLOWED` (localized constant) at first sighting, keyed by itemID.
- **Armor proficiency.** Class-armor table maps each class to its highest learnable armor type; level threshold (40) gates plate/mail. Items above current level are shown — only permanent class incompatibility filters.
- **2H weapon swap.** Engine clears OH automatically; `BAG_UPDATE_DELAYED` / `PLAYER_EQUIPMENT_CHANGED` refresh the index for the next hover.
- **Model preview leak.** `CharacterFrame:HookScript("OnHide")` calls `Popout.Hide`. Revert also fires on `PLAYER_EQUIPMENT_CHANGED`.
- **Tooltip-lock leak.** `pcall`-wrapped show/hide; restoration on `OnDisable` and on every `Hide`.
- **Slot button retheming by other addons (ElvUI, etc.).** `HookScript`, not `SetScript` — layers cleanly.
- **Empty popout.** Single italic row "No alternatives" with no buttons.
- **Pawn upgrade arrows.** Pawn injects via `hooksecurefunc("ContainerFrame_Update")` which doesn't see our popout. No conflict. Out-of-scope for v1: registering with `PawnRegisterThirdPartyBag`.
- **`/reload` mid-equip.** Engine completes the secure click before unload; benign.

## 8. Testing

### Static checks (pre-reload)

- `luac -p` syntax check on every `.lua`.
- `tools/lint.lua` greps for forbidden patterns: bare `print(`, missing `local`, `EquipItemByName` from non-secure code, `SetAttribute` not wrapped in `CombatGuard.RunSafe`.

### `/slotpeek test` — in-game assertions

Each assertion returns `(pass, message)`; results posted to chat.

1. `BagIndex.GetCandidates(INVSLOT_HEAD)` returns items whose equipLoc matches head-compatible types.
2. Every candidate is reachable via `C_Container.GetContainerItemInfo(bag, slot)` (no phantom items).
3. `PawnAdapter.Score(equippedHelmLink)` returns a non-nil number.
4. Programmatic hover of each of the 17 slot frames shows a popout without erroring.
5. `Popout.Show` followed by `Popout.Hide` leaves `GameTooltip:GetOwner()` equal to its pre-show value.
6. After `TryOn` + `Undress`/`Dress`, the model's displayed item set matches `GetInventoryItemLink` for every slot.
7. Bank cache populated after simulated `BANKFRAME_OPENED`.

### Manual smoke matrix (`TESTING.md`)

| Scenario | Expected |
|---|---|
| Hover Head with multiple helms in bags | Popout below tooltip, best highlighted, scores in delta column |
| Hover Finger0 while Finger1 has a ring | Finger1's ring excluded |
| Hover MainHand while a 2H is equipped | OH popout shows "two-handed weapon equipped" header |
| Click a bag-resident row | Item equipped, popout dismisses, no errors |
| Click a bank-resident row | Toast appears, popout stays open |
| Hover row → cursor leaves | Model reverts to live equipment |
| Open popout, enter combat | Header shows "in combat" badge, model preview still works, clicks function with pre-combat attributes |
| Hover an empty slot | Popout anchors to slot, shows alternatives |
| Disable Pawn, `/reload` | SlotPeek refuses to load |
| Pawn loaded, no scale visible | No delta column, footer prompt |

### Combat lockdown stress test

Pull a low-level mob, hover slots during the fight, swap items via popout, end fight. Verify no taint errors, no Blizzard "interface action failed because of an addon" red text.

### Performance sanity

With ~150 items in bags + bank cache, `BagIndex.Refresh` plus `GetCandidates` for all 17 slots should complete in under 50ms. Measured with `debugprofilestop()` in `/slotpeek test`.

## 9. Out of scope for v1

- Registering with `PawnRegisterThirdPartyBag` for upgrade-arrow integration.
- Cross-character bank caching (only the current character sees its own cache).
- Drag-from-popout to bag for repositioning items.
- Multi-slot comparison (e.g. evaluating ring + ring as a pair).
- Configurable popout themes / `LibSharedMedia` integration.
- Localized strings (English-only first; the only user-visible strings live in `Config.lua` and one or two places in `Popout.lua`).

## 10. Open questions / future work

- Whether to surface "best item available" upgrade hints proactively (e.g. on `PLAYER_LEVEL_UP` or after looting an item). Currently passive — only reveals on hover. Could later add an opt-in chat notice.
- Whether cached bank items should auto-expire after N days without a bank visit, to avoid showing items the player long since destroyed at a different machine.
- Engineer enchants and weapon enchants — `TryOn` ignores them; preview will not show enchant glow. Probably acceptable.
