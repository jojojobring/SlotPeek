# SlotPeek

Hover an equipment slot in the character pane to see every matching item in your bags (and bank), scored by [Pawn](https://www.curseforge.com/wow/addons/pawn) and ranked best-first. Click a row to equip from bags; bank items show a toast telling you to withdraw them.

Built for **Burning Crusade Classic Anniversary (2.5.5)**. Should also work on retail Classic Era / BCC, but only tested on Anniversary.

## Features

- **Live popout on hover.** Anchored next to the character slot, below the slot's tooltip when one is open.
- **Pawn-ranked candidates.** Best item highlighted with a gold border; deltas shown as `±X.X%` against the currently equipped piece.
- **3D model preview.** Hovering a row dresses your character model with that item.
- **Side-by-side tooltips.** The equipped item's tooltip stays anchored to the slot; the candidate's tooltip floats to the right of the popout so you can compare stats at a glance.
- **Bag + bank.** Bag items are live; bank items are cached at last bank visit and shown below a divider. Bank rows display a toast on click ("withdraw to equip").
- **Combat-aware.** Popout still appears in combat (read-only) with a `[combat]` badge; clicks are inert until you leave combat. No "Interface action failed" errors.
- **Smart filters.** Unusable items hidden (class restrictions, armor proficiency). 2H equipped means no off-hand candidates. Finger/trinket pairs exclude the item already in the other slot.

## Install

1. Install [Pawn](https://www.curseforge.com/wow/addons/pawn) and configure at least one scale.
2. Install [Ace3](https://www.curseforge.com/wow/addons/ace3) as a standalone library bundle.
3. Drop `SlotPeek/` into `World of Warcraft/_anniversary_/Interface/AddOns/`.

## Usage

- Open the character pane (`C`).
- Hover any equipment slot. The popout appears after a short delay (~150ms by default).
- Hover rows to preview the item on your 3D model and compare stats.
- Click a row to equip from bags.
- Mouse off the popout to dismiss.

## Slash commands

| Command              | Effect                                                                 |
| -------------------- | ---------------------------------------------------------------------- |
| `/slotpeek`          | Print command list.                                                    |
| `/slotpeek config`   | Open the AceConfig options panel.                                      |
| `/slotpeek refresh`  | Clear bag/bank caches; useful if a snapshot got out of sync.           |
| `/slotpeek debug`    | Toggle diagnostic chat output.                                         |
| `/slotpeek test`     | Run internal assertion harness (development only).                     |

The options panel is also reachable via **Interface → AddOns → SlotPeek**.

## Configuration

- **Enabled** — global on/off switch for the popout.
- **Hover delay** — 0–500ms. How long the cursor must rest on a slot before the popout appears.
- **Pawn scale** — which Pawn scale to use for scoring. Defaults to the first visible scale Pawn reports.
- **Debug** — print breadcrumbs to chat. Useful when reporting a bug.

## Limitations

- Bank-item scoring uses cached snapshots from your last bank visit — items added/removed since then won't show until you open the bank again.
- The 3D model preview overlay is a separate DressUpModel rendered on top of the slot's PlayerModel; switching between them on hover can occasionally flicker. (BCC's `CharacterModelFrame` lacks `TryOn`, hence the overlay.)

## License

MIT.
