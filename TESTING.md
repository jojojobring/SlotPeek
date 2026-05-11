# SlotPeek Smoke Test Matrix

Manual checks for verifying SlotPeek behavior end-to-end before tagging a release. Run them in order; a regression in an earlier row often invalidates later rows.

## Setup

- Pawn loaded with at least one visible scale.
- Ace3 loaded.
- A character with mixed bag inventory (multiple slots have alternatives) and at least one item in the bank.

## 1. Boot

| Step | Expectation |
|---|---|
| Load WoW with SlotPeek enabled | `SlotPeek: loaded (v0.1.0)` in chat. No script errors. |
| `/slotpeek` | Prints command list including `test \| config \| refresh \| debug`. |
| `/slotpeek test` | Assertion harness reports all pass. |

## 2. Hover — basic display

| Step | Expectation |
|---|---|
| Open character pane (`C`). Hover Head slot. | After ~150ms, popout opens to the right of the slot (or below the slot tooltip if one is showing). Shows N candidates from bags. |
| Hover Neck. | Popout updates for Neck candidates. |
| Hover a slot with no candidates. | Popout shows `0 items` header, no rows. |
| Move cursor off popout. | Popout dismisses after ~200ms. |

## 3. Hover — visuals

| Step | Expectation |
|---|---|
| Look at row order. | Highest Pawn score first; gold border around the best row. |
| Look at icon borders. | Rarity color (green/blue/purple) matches item quality. |
| Look at deltas. | `±X.X%` vs equipped, green/red colored. Items Pawn doesn't value show `—`. Unresolved items briefly show `…` then update. |
| Hover a row. | Equipped tooltip persists on the slot; candidate tooltip appears to the right of the popout. 3D model previews the item. |
| Mouse off the row. | Candidate tooltip hides; model reverts. |

## 4. Equipping (out of combat)

| Step | Expectation |
|---|---|
| Click row 1 on Head popout. | Item equips; popout dismisses. |
| Re-hover Head; click row 1 again. | New row 1 (likely the just-swapped-out piece) equips. |
| Rapid 3–5 swaps. | Each click lands; no "several seconds" stuck state. |

## 5. Filters

| Step | Expectation |
|---|---|
| Hover Finger1 with two rings equipped. | Other-finger ring not shown as a candidate. |
| Hover Finger2 with two rings equipped. | Other-finger ring not shown as a candidate. |
| Same for Trinket1 / Trinket2. | Each excludes the item in the paired slot. |
| Equip a 2H weapon, hover Off-Hand slot. | Popout shows 0 items (no off-hand candidates while 2H equipped). |
| Hover a slot with items you cannot use (wrong armor class / class-restricted). | Those items are not listed. |

## 6. Bank

| Step | Expectation |
|---|---|
| Visit the bank. Open it. | Banked candidates appear in popouts on next hover, below a horizontal divider. |
| Click a bank row. | UIErrorsFrame shows "Item is in your bank — withdraw it to equip." Popout stays open or dismisses gracefully (no equip). |
| Close bank, walk away. | Bank rows persist (cached); they don't re-equip via click. |
| Add/remove items at the bank, close it. | `/slotpeek refresh` updates cache if needed. |

## 7. Combat

| Step | Expectation |
|---|---|
| Pull a low-level mob. Hover Head while in combat. | Popout appears with red `[combat]` badge. 3D model preview disabled on row hover (no model swap). |
| Click a row in combat. | No equip. No "Interface action failed" red error. Popout may close. |
| Leave combat. | `[combat]` badge clears on next hover. Click-to-equip resumes. |

## 8. Config

| Step | Expectation |
|---|---|
| `/slotpeek config` | AceConfig panel opens with Enabled / Hover delay / Pawn scale / Debug. |
| Toggle Enabled off. | Hovering slots no longer opens the popout. |
| Toggle back on. | Popout returns. |
| Adjust Hover delay to 0.5s. | Next hover waits ~0.5s before opening. |
| Switch Pawn scale (if multiple defined). | Re-hover; deltas reflect the new scale. |
| Toggle Debug on. | Subsequent hovers print `[dbg]` breadcrumbs to chat. |

## 9. Edge cases

| Step | Expectation |
|---|---|
| Open character pane, hover slot, close pane via `C` while popout is showing. | Popout dismisses; no stale frames. |
| Hover slot → quickly slide cursor into popout → out of popout. | Popout dismisses cleanly; tooltips don't stick. |
| Hover slot A → mouse over to slot B without exiting the character pane. | Popout reflows to slot B's candidates without flicker. |
| `/reload` while popout is open. | No errors. Popout state cleared. |

## 10. Bank cache (deferred from Task 17)

| Step | Expectation |
|---|---|
| Visit bank with a known item. Note its hyperlink. Close bank. | Bank cache snapshot includes that item. |
| Hover the matching slot. | Banked item appears as a row, marked as bank source. |
| `/reload` without revisiting bank. | Banked item still appears (`SlotPeekDB.char.bankCache` persisted). |
| Move the item out of bank externally (e.g., another session). Visit bank again. | Stale entry removed from popout. |
