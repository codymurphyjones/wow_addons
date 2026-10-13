# Wally

**Learns your junk so you don't have to.**

Wally is a smart junk seller. It sells your junk at any merchant in one click, and it learns what *you* treat as junk by watching what you sell by hand. Before it sells anything it checks that the item isn't a possible gear upgrade, one of your most valuable stacks, or something you've told it to keep. It also sorts your bags and bank exactly the way you set it up, repairs your gear, keeps a history of every sale, and, with Auctionator installed, posts your regular auction items from its own auction house tab.

- Works on Classic Era, The Burning Crusade Classic, Mists of Pandaria Classic and Retail.
- **Auctionator is optional.** Wally uses its prices to value items, and needs it for the auction features.
- Lists, rules, learning and settings are shared by all your characters. Window position, minimap button, merchant button position and bags left out of sorting are saved per character.

---

## Quick start

1. Install Wally and log in. Type **`/wally`** (or **`/junk`**) to open the junk manager.
2. Open a merchant. A **Wally button** appears on the merchant window with a count of the junk in your bags. **Left-click it** to sell.
3. Keep playing as normal. When you sell the same item by hand a few times, Wally asks whether it's junk. Say yes and it sells that item for you from then on.
4. Settings are in the game menu under **Options > AddOns > Wally** (or `/wally config`).

---

## How Wally decides what's junk

Every item gets a verdict, and the reason is shown in tooltips and on the **In Bags** tab. Wally checks these in order and stops at the first match:

| # | Check | Result |
|---|-------|--------|
| 1 | Item can't be sold, is a quest item, data is still loading, or the slot is locked | Never sold |
| 2 | On your **Never Sell** list | Kept |
| 3 | Matches a **keep rule** ("name contains...") | Kept |
| 4 | On your **Auction List** | Kept (it's worth more at the auction house) |
| 5 | One of your **protected valuables** | Kept |
| 6 | On your **Junk List** | **Junk** |
| 7 | A grey or white piece of gear that's a **possible upgrade** | Kept |
| 8 | **Soulbound gear your character can never use** (wrong class, armor type or weapon skill) | **Junk**, except that enchanters keep green and better items to disenchant |
| 9 | Matches a **junk rule** ("name contains...") | **Junk** |
| 10 | Poor quality (grey) | **Junk** |

Because Never Sell, keep rules, the Auction List and valuables are checked first, they always win over everything below them.

---

## Selling at a merchant

### The Wally merchant button
The Wally button sits next to the merchant window's own sell-junk button (or at the top right of the window).

- **Left-click:** sell junk.
- **Right-click:** open the junk manager.
- **Drop an item on it:** adds that item to the Junk List, or removes it if it's already there.
- **Shift-drag:** move the button. `/wally resetbutton` puts it back.
- The number on the button is how many junk items you're carrying, and the tooltip shows their total value. The icon turns grey when there's nothing to sell.

### Selling options
- **Sell junk automatically:** sells as soon as you open a merchant.
- **Safe sell (12 at a time):** sells no more than 12 items per click, so everything Wally just sold is still in the merchant's buyback tab. It sells the cheapest junk first, and you can click again to sell the next 12.
- **Repair gear automatically:** repairs everything at any vendor who can repair. Guild bank funds are used first when you're allowed to use them and they cover the cost.

Wally prints the total after each sale (turn off **Chat messages** to keep it quiet). Selling stops by itself if you close the merchant or the vendor refuses an item.

---

## Learning from your selling

Wally watches what you sell to merchants **by hand** (right-clicking items in your bags at a vendor).

- Every item has a **habit score** from 0% to 100%. Each sale raises it. A full stack raises it far more than a single item, so a non-stacking item needs a few sales and a full stack needs fewer.
- **Buying an item back lowers its score twice as hard** as a sale raises it.
- When the score reaches your threshold (default **50%**, adjustable from **20% to 95%** in settings), Wally asks:
  - **Yes, it's junk:** adds it to the Junk List.
  - **Ask later:** lowers the score and doesn't ask again for 24 hours.
  - **Never sell:** adds it to Never Sell.
- If you buy back something that's on your Junk List, Wally asks whether to **never sell** it, **keep it as junk**, or **remove it from the list**.
- Turn on **Add learned items silently** to skip the question and add straight to the Junk List.
- Items Wally sells itself, and items already on a list, don't count toward learning.
- Popups never appear during combat. They wait until combat ends.

The **Learning** tab shows every item Wally is tracking, with a score bar, a marker at your threshold, how often you sold and bought it back, and how much it earned. From there you can **Forget** an item, or send it straight to **Junk** or **Never** sell. **Forget everything** resets all learning but keeps your lists.

---

## Lists and rules

### Junk List and Never Sell
- **Junk List:** items always sold at merchants.
- **Never Sell:** items never sold, whatever other rules say.
- An item can only be on one of the two. Adding it to one removes it from the other.

### Adding items
On either list's tab you can:
- **Drag an item** from your bags onto the tab.
- **Shift-click an item** into the add box.
- **Type an item name or item ID** and press Enter or click **Add item**.
- Use `/wally add <item>` or `/wally never <item>`.

Items are matched by name, so every copy of an item is covered.

### Rules ("name contains")
Type text in the add box and click **Add rule** to cover every item whose name contains it. For example, a junk rule of `linen` covers Linen Cloth, Linen Belt and so on. Keep rules on the Never Sell tab work the same way. You can also use `/wally rule <text>` and `/wally keeprule <text>`.

### Managing entries
- **Search** filters the list.
- The **source filter** shows everything, only items you added, items Wally learned, or imported items.
- **Right-click** an entry to remove it. **Shift+right-click** moves it to the other list.
- **Remove all** clears the list's items but keeps its rules.

### Import and export
Under **Options > AddOns > Wally** there's an import/export box. **Export** fills it with your lists and rules (press Ctrl+C to copy). **Import** adds every line in the box. Nothing is removed. One entry per line:

```
J:Linen Cloth      <- Junk List item
N:Hearthstone      <- Never Sell item
J*:linen           <- junk rule (name contains)
N*:potion          <- keep rule (name contains)
```

---

## Gear upgrade protection

With **Protect possible upgrades** on, Wally won't sell a grey or white weapon or armor piece that might beat what you're wearing:

- An item for an **empty slot** is always kept.
- Any extra stat (Strength, Stamina, ...) beats a piece with **only armor**.
- Between two pieces with only armor, **higher armor wins**. For weapons, **higher DPS wins**.
- When both pieces have extra stats, Wally doesn't try to judge and doesn't protect the item.
- Rings, trinkets and one-handers (if you can dual wield) count as upgrades if they beat the **weaker** of your two equipped items. Off-hand items aren't protected while you wield a two-hander.
- Items your character can't use are never "upgrades". **Level requirements are ignored**, because you'll grow into the item.

The check updates whenever you change gear, level up or learn new skills.

---

## Protected valuables

Wally ranks every stack in your bags by worth and protects the most valuable ones. They're **never sold as junk** and they **sort first** (right after pinned items).

- **Protect the top N stacks:** default **10**, from 0 (off) to 40.
- **Rare and better are always protected:** blue and purple items are protected whatever their rank.
- **Worth** comes from Auctionator's auction price when available. Otherwise Wally estimates it from rarity, item level and kind of item, with gems and enchanting, elemental and jewelcrafting materials valued higher. The vendor price is the minimum.
- Greys and soulbound gear you can't use are never counted as valuables.

---

## The junk manager window

Open it with `/wally`, `/junk`, the minimap button, the AddOn compartment or a right-click on the merchant button. Drag the window to move it, and press Escape to close it.

| Tab | What it's for |
|-----|---------------|
| **Junk List** | Items and rules that are always sold. |
| **Never Sell** | Items and keep rules that are never sold. |
| **Learning** | What Wally has learned from your selling (see above). |
| **In Bags** | Every junk item, possible upgrade and kept item in your bags, with Wally's reason and total junk value. Tick **Show every item** to see everything. Buttons: **Sell junk now** (at a merchant), **Sort bags**, **Sort options**. Right-click an item to mark it as junk, or to never sell it. |
| **History** | Your last 200 merchant sales and buybacks, marked *by Wally* or *by hand*. Each entry has **Never** and **Junk** buttons. |
| **Auctions** | Auction List, Never Auction and auction learning (only with Auctionator and the modern auction house). |
| **Settings** | Opens Options > AddOns > Wally. |

---

## Bag and bank sorting

Wally has its own bag sorter that you can set up exactly how you like. Sort with:
- the **sort button** Wally adds to your backpack (left or right of the search box) and bank window, which replaces Blizzard's button. **Left-click** sorts, **right-click** opens the sort options.
- `/wally sort` and `/wally sortbank`,
- **shift-right-click** on the minimap button,
- the **Sort bags** button on the In Bags tab.

Settings are under **Options > AddOns > Wally > Bag Sorting** (or `/wally sort config`).

### Sort order
Tick the rules you want and use the arrows to put them in order. The top rule decides first. Each rule can be flipped:

| Rule | Directions |
|------|-----------|
| Group | In order / Reversed (uses your group order) |
| Quality | Low first / Best first |
| Item level | Low first / High first |
| Required level | Low first / High first |
| Equip slot | Head to feet / Feet to head |
| Name | A to Z / Z to A |
| Worth | Low first / High first (Auctionator price or Wally's estimate, whole stack) |
| Sell value | Cheap first / Pricey first (vendor price, whole stack) |
| Stack size | Small first / Big first |

**Presets:**
- **Blizzard:** group, quality, worth, item level, name.
- **Quality:** quality, worth, group, name.
- **Type:** group, equip slot, item level, name.
- **A to Z:** name only.

### Group order
Arrange the groups used by the Group rule: Hearthstone & keys, Consumables, Quest items, Weapons & armor, Trade goods & reagents, Recipes, Bags & quivers, Ammo, Everything else.

### Options
- **Junk goes last:** everything Wally would sell ends up together at the end.
- **Fill from the end of the last bag:** like Blizzard's sort. When off, sorting starts at the backpack.
- **Sort button on bags and bank**, and whether it sits **left or right of the search box**.
- **Sort after Wally sells junk:** closes the gaps that selling leaves.
- **Sort when you close a merchant.**
- **Order reagents by worth:** the most valuable trade goods come first.
- **Don't move items in:** tick any bag or bank bag that sorting should leave alone.

### Pinned first
Pin items (your hearthstone, for example) and they always take the first slots, in the order you set. Drag an item onto the box, shift-click it in, or type its name. Use Up/Down to reorder and right-click to unpin.

### How sorting behaves
- Partial stacks are merged first.
- Special bags (quivers, ammo pouches, soul bags, profession bags) are filled with items that fit them.
- Sorting stops safely if you enter combat, close the bank, pick up an item, or if it takes more than 30 seconds. Click Sort again to carry on.
- Sorting can't run during combat, while you hold an item, or while Wally is selling.

---

## Auctions (with Auctionator)

These features appear when **Auctionator** is installed and your client has the modern auction house.

### The Wally tab at the auction house
Wally adds a **Wally** tab to the auction house window.

**Left side:** switch between **History** (every auction you've created), **Auction List**, and **Learning**.

**Right side, "Ready to Post":** every Auction List item in your bags, priced and ready.
- **Add items** by dropping them on the drop zone or list, or by **right-clicking them in your bags** while the tab is open.
- Each item has a **green check** (will post) or a **red circle** (skipped this visit). Click it to switch. **Nothing posts until you approve it**, and approvals reset every visit. **Approve all** and **Unapprove all** do the whole list.
- The **Next up** card shows exactly what the next click will post: item, quantity, unit and total price, Auctionator's price, your undercut, how long ago the price was seen, and the duration.
- **Post** posts the Next up item. The game requires one click for every post, so you click once per item (once per stack for commodities). The button turns red while the auction house cools down and green when it's ready again.
- The footer shows the approved total and estimated deposit, and has quick controls for the Undercut toggle (with amount and percent/copper when it is on) and default duration.
- Right-click an item to never auction it. Shift+right-click removes it from the Auction List.

### Pricing
- By default Wally **price matches**: it posts 1 below Auctionator's price (1 copper, which rounds down to 1 silver, the smallest step the auction house takes). Tick **Undercut** to go lower instead, by a percentage (default **5%**, up to 90%) or a fixed copper amount. Set it on the tab, in settings, or with `/wally auction undercut 5%`, `/wally auction undercut 100` or `/wally auction undercut off`.
- Prices round down to whole silver.
- **An item is never listed below its vendor price.** If it's worth more at a vendor, Wally says so and skips it.
- Items without an Auctionator price are skipped until you scan them with Auctionator.
- Wally runs Auctionator's full scan the first time you open its tab, at most once every **4 hours** per realm (it remembers across reloads, logins and alts). Any full scan counts, including Auctionator's own.
- Prices older than **Stale price after** (default 3 days) are shown in yellow.

### Duration
Wally uses your **default duration** (12, 24 or 48 hours; default 24h) until you post an item by hand. From then on it uses whatever duration you picked for that item.

### Taking items off the list
If you remove an item from the Auction List while it has auctions up, Wally asks whether to **cancel those auctions too** (deposits aren't refunded). If you say yes, the cancels go first, one Post click each.

### Active auctions
The **Active** button on the auction house tab lists every auction you have up right now, soonest to expire first, with its price, time left and whether it's on your Auction List. Click **Cancel** on a row to cancel that auction (one click each; deposits aren't refunded). Cancels you make anywhere, in Wally, the Blizzard UI or Auctionator, drop off the list right away and are logged in **History** as *Cancelled*. Cancelling by hand, including from the Active list, lowers that item's learned score.

### Auction List and Never Auction
- Items on the **Auction List** are **never sold to a vendor**. An item can't be on both the Junk List and the Auction List.
- Items on **Never Auction** are never suggested for the Auction List.
- Manage both lists from the **Auctions** tab in the junk manager, the auction house tab, or `/wally auction add|never|remove <item>`.
- Items in the reagent bag are only posted if you added them by hand on the Wally tab. Soulbound items are never posted.

### Auction learning
Wally watches every auction you create, whether through Auctionator, Blizzard's UI or its own tab. Posting by hand raises an item's auction score, and cancelling lowers it twice as hard. At your threshold, Wally asks: **Yes, auction it** / **Ask later** / **Never auction**. Turn on **Add learned items silently** in the auction settings to skip the question. Wally's own posts don't count.

---

## Tooltips

With **Item tooltip lines** on, item tooltips show:
- **Wally's verdict** and reason: junk (red), kept (green) or possible upgrade (blue).
- **Worth per item** for trade goods, reagents and gems (auction price or estimate).
- **Learning progress**: "learning 40% (sold 2, bought back 0)".
- **Auction learning progress** for items you've been posting.

---

## Minimap button and AddOn compartment

- **Left-click:** open the junk manager.
- **Right-click:** open the In Bags tab.
- **Shift-right-click:** sort your bags.
- **Drag:** move it around the minimap.
- The tooltip shows how much junk you're carrying and what it's worth.
- Until you move it yourself, Wally finds a free spot so it doesn't overlap other addons' minimap buttons.
- Hide or show it in settings or with `/wally minimap`. Wally is also in the AddOn compartment on clients that have one.

---

## Sale History

Everything Wally sells for you is saved **per login session** under **Options > AddOns > Wally > History** (or `/wally history`).

- The session list on the left shows each session's date, item count and gold.
- The right side lists every sale in the selected session with the time and price. Sales you bought back are flagged, and the totals subtract them.
- **Keep last N sessions:** default 30, from 5 to 100. Older sessions are deleted.
- **Clear all** deletes the whole archive.

---

## Settings reference

**Options > AddOns > Wally**

| Setting | Default | What it does |
|---------|---------|--------------|
| Sell junk automatically | Off | Sell as soon as you open a merchant. |
| Safe sell (12 at a time) | On | Never sell more than you can buy back. |
| Grey items are junk | On | Every poor-quality item counts as junk. |
| Protect possible upgrades | On | Keep grey/white gear that may beat what you wear. |
| Sell unusable soulbound gear | On | Sell bound gear you can't use. Enchanters keep greens and better. |
| Repair gear automatically | On | Repair at any vendor, using guild funds first if allowed. |
| Learn from my selling | On | Watch what you sell by hand and buy back. |
| Add learned items silently | Off | Skip the question and add straight to the Junk List. |
| Item tooltip lines | On | Show Wally's verdict on item tooltips. |
| Chat messages | On | Print sale totals and other notices. |
| Minimap button | On | Show the minimap button. |
| Ask after this habit score | 50% | How sure Wally must be before asking (20–95%). The slider shows about how many sales that takes. |

The panel also has the import/export box, **Open junk manager**, **Forget learning**, and buttons for **Bag Sorting**, **History** and **Auctions**.

**Bag Sorting defaults:** sort order Blizzard preset, junk goes last on, fill from end off, sort button on (left of search), sort after selling off, sort on merchant close off, protect top 10 stacks, rare and better protected on, reagents by worth on.

**Auction defaults:** learn from my auctions on, add learned items silently off, undercut off (price match, 1 below Auctionator; 5% when turned on), default duration 24 hours, stale price after 3 days, hide unused auction tabs off (when on, only Shopping, Selling, Wally and Cart stay on the auction house).

---

## Slash commands

`/wally` and `/junk` work the same way.

| Command | What it does |
|---------|--------------|
| `/wally` | Open or close the junk manager. |
| `/wally config` | Open Options > AddOns > Wally (also `settings`, `options`). |
| `/wally history` | Open the Sale History. |
| `/wally add <item>` | Add an item to the Junk List. |
| `/wally never <item>` | Add an item to Never Sell. |
| `/wally remove <item>` | Remove an item from both lists. |
| `/wally rule <text>` | Add a junk rule: names containing the text are junk. |
| `/wally keeprule <text>` | Add a keep rule: names containing the text are never sold. |
| `/wally sell` | Sell junk now (at a merchant). |
| `/wally sort` | Sort your bags. |
| `/wally sortbank` | Sort your bank (also `/wally sort bank`; the bank must be open). |
| `/wally sort config` | Open the Bag Sorting settings. |
| `/wally forget <item>` | Reset what Wally learned about an item. |
| `/wally list` | Print the Junk List and junk rules in chat. |
| `/wally minimap` | Show or hide the minimap button. |
| `/wally resetbutton` | Put the merchant button back in its default spot. |
| `/wally auction` | Open Wally's auction house tab (or the Auctions page when you're away from it). Also `/wally ah`. |
| `/wally auction add <item>` | Add an item to the Auction List. |
| `/wally auction never <item>` | Add an item to Never Auction. |
| `/wally auction remove <item>` | Remove an item from both auction lists. |
| `/wally auction forget <item>` | Reset what Wally learned about auctioning an item. |
| `/wally auction undercut <n>[%]` or `off` | Set the undercut, e.g. `5%` or `100` (copper), which turns undercutting on; `off` goes back to price matching. |

`<item>` can be an item link (shift-click it in), an item name, or an item ID.

---

## FAQ

**Will Wally ever sell something I care about?**
Anything on Never Sell, covered by a keep rule, on your Auction List, or among your protected valuables is never sold. Safe sell (on by default) sells at most 12 items per click so you can always buy them back, and Wally asks whether to stop selling anything you buy back.

**Why do I have to click Post for every auction?**
The game only lets an addon post or cancel an auction in response to a click. Wally makes each click count by showing exactly what it will post next.

**Do I need Auctionator?**
No. Selling, learning, sorting and history all work without it. Auctionator adds real auction prices for worth and valuables, and turns on the auction features.

**Wally sold something it shouldn't have.**
Buy it back from the merchant's buyback tab and pick **Never sell** in the popup, or drag it onto the Never Sell tab.
