# Quartermaster

**Plan your shopping anywhere in the world, then buy it all at the auction house one click at a time, at market price.**

Every adventurer needs supplies: reagents, food, cloth, potions, arrows. Quartermaster keeps your supply lists and does the legwork at the auction house.
- Look up any item Auctionator has priced, from anywhere, with filters that work like the auction house's Browse tab.
- Put what you need on a list.
- Make **prebuilt lists** for things you restock every week, like a Raid Night list. Quartermaster counts what you already have and buys only what's missing.
- At the auction house, open the **Cart** tab and keep clicking **Buy Next**. Quartermaster finds the cheapest fair listing each time.
- It won't pay well over market without asking you first.

---

## Getting started

1. **Install Auctionator.** Quartermaster needs it; all prices come from Auctionator's price data.
2. **Visit the auction house once** and run Auctionator's full scan (Auctionator tab > Full Scan). This gives Quartermaster the items to browse and their market prices.
3. **Type `/qm`** (or click the minimap button) to open Quartermaster.
4. **Browse** for what you need, set a **Qty**, and click **+** or **Add to list**.
5. At the auction house, open the **Cart** tab and click **Start buying**. Then click **Buy Next** once for each purchase.

---

## Features

### Browse: the auction house in your pocket
The Browse page works like the Blizzard auction house's Browse tab. It searches every item Auctionator has priced, so it works anywhere: in town, in a dungeon, on the boat.
- **Name.** Typing searches as you go. Put the name in quotes (`"Linen Cloth"`) for an exact match.
- **Level range.** Filters on the item's required level.
- **Rarity.** Shows that quality and better.
- **Usable.** Hides anything your character can't use, judged the same way the game does: by red requirement lines on the tooltip.
- **Categories.** Weapon, Armor, Container, Consumable, Trade Goods, Projectile, Quiver, Recipe, Reagent and the rest. Click one to filter; click it again to open its sub-types.
- **Sortable columns.** Name, Lvl, iLvl, Market price and Seen (how old the price is). Click a column again to reverse it.
- **Pages of 50**, with Prev and Next.
- **Shift-click** any item link into the Name box to look that item up.

### Advanced search
Click **Advanced** to open a second row of filters, like Auctionator's advanced search:
- **iLvl range**: item level.
- **Price range**, in gold, based on market price.
- **Max age**: only items whose price was seen within this many days.
- **Slot**: head, chest, finger, two-hand and so on.
- **Priced only**: hide items with no market price.
- **Auctionator search string**: paste one in, e.g. `"Linen Cloth";;0;0;0;0;0;0;0;5`, and click **Use** to fill the filters. A quantity in the string goes into the Qty box.

### Shopping lists
- Make **as many lists as you like** ("Leveling Food", "Tailoring 150-200"). One list is **active** at a time, and the Cart buys it. For lists you buy again and again, see **Prebuilt lists** below.
- Browse's **Add to** dropdown chooses which list (or prebuilt list) new items go on.
- Add an item from Browse, **drag an item from your bags** onto a list, or type `/qm add <item> <qty>`.
- Adding an item that's already on the list raises its quantity instead of adding a second row.
- Each row shows how many are bought out of how many wanted, the market price, the most the Cart will pay, a progress bar, and the estimated cost of the rest.
- Use **−**, **+** and **X** on each row to change the amount or remove the item. Click a row to set an exact Qty or a **tolerance for that item only**.
- **Reset bought** starts the list over. **Clear list** empties it. **Save as prebuilt** copies the list into a reusable prebuilt list.
- **Send to Auctionator** copies the list into Auctionator's Shopping tab as "Quartermaster - <list>", with exact searches and the quantities still needed.

### Prebuilt lists: restock to a target
Some shopping happens every week: flasks and food for raid night, reagents for your class, arrows, trade goods for a crafting session. A **prebuilt list** remembers how many of each item you want to *have*. Quartermaster counts what you already have and buys only the difference.

**Example: Raid Night**

| Item | Target | You have | The Cart buys |
|---|---|---|---|
| Flask of the Titans | 2 | 1 | 1 |
| Major Mana Potion | 20 | 6 | 14 |
| Nightfin Soup | 20 | 25 | nothing (stocked) |

Next week, tick Raid Night again and it works out the new shortfall. There's nothing to reset.

**Making one**
- Open the **Prebuilt** tab (`/qm prebuilt`), type a name (e.g. *Raid Night*) and click **New**.
- Add items from **Browse**: set the **Add to** dropdown to your prebuilt list, then use **+** or **Add to**. The Qty raises that item's target.
- You can also **drop items from your bags** onto the list, or turn any shopping list into a prebuilt one with **Save as prebuilt** on the Lists page.
- Click an item to set an exact **Target** and an optional **Tolerance** for that item. **−**, **+** and **X** adjust or remove it.
- Each item shows its target, how many you have (bags, bank, mail), what's still needed, and roughly what that costs. Each list shows the total cost to restock it right now.

**This character or every character**
- New prebuilt lists belong to **this character**.
- **Rename** a prebuilt list with the **Rename** button (type the new name first, or just click to be asked) or from its right-click menu.
- **Right-click** one and choose **Share with account** to make it available to all your characters, so your alts can restock Raid Night too.
- Right-click an account list to **Make character-only** or **Duplicate to this character**. You can also **Duplicate** or **Delete** from the right-click menu.

**Restocking at the auction house**
- In the Cart tab, click **Prebuilt**, then tick one or more lists in the dropdown.
- **Several lists merge into one run.** If an item is on more than one ticked list, its targets add up. For example, Raid Night wants 20 Mana Potions and PvP Night wants 10, so the target is 30.
- Items you already have enough of show as **stocked**. The rest are bought the usual way: one click per purchase, at market price plus tolerance.
- **Recount** counts your stock again. Quartermaster also recounts by itself whenever your bags change while nothing is being bought.

**What counts as "have"**
- **Bags** always count.
- **Bank**, as of your last visit to the bank (this can be turned off in Settings).
- **Mailbox.** Auctions you win are delivered by mail, not straight into your bags. Quartermaster counts everything it bought since you last opened your mailbox, plus whatever was in the mailbox at that time, so it never buys the same items twice (this can be turned off in Settings).

### The Cart tab
Quartermaster adds a **Cart** tab to the auction house, next to Auctionator's tabs.
- At the top, choose **Shopping list** to buy one of your lists, or **Prebuilt** to tick prebuilt lists to restock. The summary shows the estimated cost and the tolerance in use.
- Each item shows its progress and status: pending, searching, the number of listings found, done, skipped, none listed, or how many short it is.
- **One big button.** It always says what the next click will do, for example **"Buy 20x Linen Cloth - 1g 20s"**.
- **One click, one purchase.** The game requires a click for every purchase, so each click buys one stack. Searching between purchases happens on its own.
- When an item is done, the Cart moves to the next one by itself. When the list is done, it prints what it spent and anything still missing.
- **Stop** ends the run at any time. Closing the auction house stops it too.

### Waylaid Supplies crates
Click a **Waylaid Supplies** crate in the Buying tab or the Cart's search, and Quartermaster looks up the crate and the item that fills it, together.
- The crate comes first, then **Filled with:** the filler item's listings, with how many the crate needs (when its tooltip says) and how many you have.
- Click either one to see its listings and buy. **+** on the "Filled with" heading adds the filler to your list.
- **Back** returns to your search.

### Buys at market price, and asks before overpaying
- The **market price** is Auctionator's latest price for the item.
- The Cart buys any stack priced at or below **market + tolerance** per item. Tolerance is 10% by default; change it in Settings, or per item on the Lists page.
- Within that limit it always picks the **cheapest price per item first**.
- **When nothing is within tolerance**, or Auctionator has no price for the item, Quartermaster stops and asks, showing the market price and the cheapest listing:
  - **Buy Cheapest**: buy the cheapest listings for this item anyway, for the rest of this run.
  - **Skip Item**: leave it and move to the next item.
  - **Cancel**: stop the run.
- Your **own auctions** and **bid-only** auctions are ignored.

### Smart stack sizes
Auctions sell whole stacks, so you can't always buy the exact amount. Quartermaster allows a stack to take you over the amount you still need by up to the **Allowed overshoot** (50% by default).
- *Example:* you still need 10. Stacks of up to 15 are fine. A cheaper stack of 20 is passed over for a stack that fits.
- If every stack within tolerance is too big, it buys the smallest one.

### Safety checks
- **Big purchases ask first.** Any single purchase at or above the **Confirm purchases over** amount (50 gold by default) needs a Yes.
- **Not enough gold?** The button says so and won't let you click.
- **Someone else bought it first?** Quartermaster skips that listing and finds the next one.
- **It won't act on old search results.** Quartermaster checks that each auction is still there before offering it, and ignores search results from other addons or the Browse tab.

### Key binding
Bind **Buy next cart item** under **Key Bindings > AddOns > Quartermaster**. Each key press works exactly like clicking Buy Next, so you can buy through a whole list without moving the mouse. There's also a binding to **open or close Quartermaster**.

### Minimap button
- **Left-click**: open or close Quartermaster.
- **Right-click**: open your lists.
- **Drag**: move it around the minimap.
- The tooltip shows your active list and roughly how much it will cost.
- It finds a free spot on the minimap by itself until you place it yourself. Turn it off in Settings or with `/qm minimap`.

---

## Settings

Open the **Settings** tab in the Quartermaster window (`/qm settings`).

| Setting | What it does | Default |
|---|---|---|
| **Market tolerance** | How far over market price the Cart will pay without asking | 10% |
| **Allowed overshoot** | How far a stack may take you over the amount still needed, as a share of that amount | 50% |
| **Confirm purchases over** | Ask before any single purchase at or above this amount (0 = never ask) | 50 gold |
| **Prebuilt lists count items in your bank** | Count bank items as "have" (as of your last bank visit) | On |
| **Prebuilt lists count auction wins waiting in the mailbox** | Count purchases and mailbox items as "have" | On |
| **Print messages in chat** | Quartermaster's chat messages | On |
| **Show minimap button** | Show or hide the minimap button | On |

The Settings tab also shows how many items Auctionator has prices for on your realm.

---

## Commands

| | |
|---|---|
| `/qm` or `/quartermaster` | Open or close Quartermaster |
| `/qm browse <text>` | Open Browse and search for `<text>` |
| `/qm lists` | Open your lists |
| `/qm prebuilt` | Open your prebuilt (restock) lists |
| `/qm cart` | Open the Cart tab (at the auction house) |
| `/qm add <item link or name> [qty]` | Add to the active list, e.g. `/qm add Linen Cloth 40` |
| `/qm reset` | Reset bought progress on the active list |
| `/qm minimap` | Show or hide the minimap button |
| `/qm settings` | Open Settings |

---

## Tips

- **Keep prices fresh.** Every search you make with Auctionator updates those items' prices, and a full scan updates everything. The **Seen** column and the **Max age** filter show how fresh a price is.
- **Per-item tolerance** works well for items whose price jumps around, like rare reagents: give them 25% and leave everything else at 10%.
- **Shopping lists are saved per character.** Prebuilt lists are too, unless you share them with your account.
- The sidebar shows where Browse is adding items right now.
- **Raid prep in one click per stack:** tick *Raid Night* and *Class Reagents* together in the Cart and buy everything in one run.

---

## FAQ

**Browse is empty.**
Auctionator has no prices yet. Open the auction house and run Auctionator's full scan.

**An item says "Loading item data..."**
The game is still fetching that item's details. It fills in by itself within a few seconds.

**Why can't Quartermaster buy everything in one click?**
The game requires a separate click (or key press) for every auction purchase; no addon can get around that. Quartermaster does everything else for you: it searches, picks the best listing, and gets it ready for your click.

**I just bought Flasks, why does the Cart say I have them?**
They're waiting in your mailbox. Quartermaster counts auction wins from the moment you buy them, so it won't buy them again. Turn this off in Settings if you prefer.

**My bank items aren't counted.**
The game only knows what's in your bank after you've visited it. Open your bank once and the counts update.

**The Cart skipped an item as "none listed".**
Nobody is selling it right now. Try again later. Its progress is kept until you reset it.

**The Cart keeps asking me about an item.**
Its listings are all above market + tolerance. Choose **Buy Cheapest** to buy anyway, raise that item's tolerance on the Lists page, or refresh its price with an Auctionator search, since the market price may be out of date.

---

## Notes

- Built for **World of Warcraft: Forever** (Interface 16001) and its classic auction house.
- **Requires Auctionator.** No other libraries are needed.
- Its flat, dark look matches **Wally**.

Bug reports and suggestions are welcome in the comments or on the issue tracker.
