Whereabouts 何处  ·  User Guide

This guide covers both the Mac and iOS (iPhone / iPad) versions. Most
features work the same way — only the interaction differs: where Mac
uses right-click / keyboard shortcuts, iOS uses long-press / swipe
gestures instead. iOS-only details are in "📱 iOS Version" below;
sections marked (macOS) apply to the Mac version only.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📝  Adding Items
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Type a sentence in the top input field, press Return.

Supported phrasings (Chinese NLP):
  · 充电宝 在 卧室抽屉   (item in location)
  · 护照 → 保险箱        (arrow notation)
  · 双立人菜刀是 2024 年在山姆买的   (with purchase info)
  · 书房桌上有 AITO 底座  (location-first phrasing)
  · 床头柜上的钥匙        (possessive phrasing)

Auto-extracted from text: model, color, purchase date, source,
capacity / size.

Add multiple items at once — any of these separators work:
  newline · semicolon · comma · dunhao 、 · "然后" · "以及"
  · 钥匙在玄关,雨伞在门口
  · 3 个 Magic Keyboard keyboards in the study

Quantities are preserved (e.g. "3 个 Magic Keyboard").

Shared location for multiple items:
  Writing "iPhone、AirPods、Apple Watch in the study drawer"
  attaches all three items to "study drawer" — not just the
  first one. Items in the same input that have no location
  automatically inherit the location from the nearest sibling
  that does.

Note: the primary parser is Chinese. If a Chinese parse yields
no result, the app automatically tries an English fallback:
  "X in Y" / "X at Y" / "Y has X" and similar phrasings.

Location autocomplete:
  · Recent-location chips appear below the input — tap one to
    append the location to your draft
  · If your text mentions an existing room, an "Inside <room>"
    chip row appears above, listing that room's sub-locations
  · Matching is case-insensitive and ignores full/half-width
    differences: "hifi" matches "HiFi"

If no AI key is configured, a purple chip below the input
prompts you to set one up. Clicking opens Settings → AI.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✨  AI Re-understanding
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

When the local parser misses an unusual brand name or an
ambiguous location, AI can re-parse the item semantically.

Configure AI (⌘, → AI tab):
  · Provider: Claude or Volcengine — both can be pre-configured
    and switched on demand
  · Model: Haiku 4.5 / Sonnet 4.6 / Sonnet 5 / Opus 4.7 / Opus 4.8
           (Claude) or a Volcengine model name / endpoint ID
  · API key: entered here, stored in app preferences
  · Endpoint: defaults to the official URL; change it to a
    relay or proxy if direct access isn't available
  · "Test connection" verifies the key in about 1 second
  · "View illustrated setup guide (web)" link: a step-by-step
    walkthrough for signing up and topping up a Claude or
    Volcengine account, getting an API key, entering it in the
    app, estimating cost, and troubleshooting errors. Bilingual
    (中/EN), available on both Mac and iOS.

> ✅ v0.2.0: Two new Claude model tiers — Sonnet 5 and Opus 4.8.
> The AI settings section also gained a "View illustrated setup
> guide (web)" link.

Three ways to trigger AI re-understanding:
  1. Check "Use AI to re-understand" in the input area
     The item saves instantly via local parsing, then AI
     refines the fields in the background. The row shows
     ✨ + spinner + "AI is re-understanding…" while running,
     then ✅ "AI re-understood ✓" in green for 4 seconds.

  2. Detail page → ✨ Re-understand with AI button
     Runs immediately for that one item without blocking the UI.

  3. Multi-select → right-click → ✨ Re-understand with AI
     Runs in the background per item — inline ✨ / ✅ indicators
     on each row. You can keep working while the queue runs.

What AI does:
  · Semantically re-parses all text fields (name, location,
    model, color, and more)
  · Uses the original text you typed as the highest-priority
    reference — helpful for multi-item paragraphs or vague
    location descriptions
  · When your input contained multiple items, AI only refines
    the current item — it will not alter the names of siblings
  · Quantity words ("3 个", "2 副", etc.) are kept as-is;
    AI will not strip them from the name
  · Must pick one tag from your existing tag list — AI never
    invents new tags. If nothing fits, it falls back to "Other"
  · AI's tag replaces all current tags on the item (no stacking)
  · Fields AI returns as null keep their existing values

AI location typo tolerance:
  AI receives your full list of existing locations and will
  reuse the closest match rather than creating a new one.
  Tolerance covers: 1-2 character differences, homophones,
  traditional/simplified Chinese, case, full-width/half-width.
  Example: you type "plastic bag drawer" while "plastic drawer"
  already exists → AI uses the existing location.

Reverting an AI change:
  In the detail-page timeline, rows where AI modified the name
  have an ↩ Revert button on the right. Click it to restore
  the name to what it was before AI changed it.

AI usage statistics (Settings → AI):
  The usage section at the top shows three columns: Today /
  This Week / This Month. Each column displays: call count /
  input tokens / output tokens / estimated USD.
  Resets automatically at the start of each month; you can
  also reset manually at any time.
  Note: token counts are taken directly from the usage field
  in each API response — the same figures your Anthropic or
  Volcengine bill is based on.

Volcengine users can fill in two optional fields in the AI tab's
Volcengine section: "Input ¥/M tokens" and "Output ¥/M tokens" (find
your model's unit price on the Volcengine console under the model's
detail page). Once filled in, the usage section shows an extra ¥
estimate row alongside the Claude $ estimate; leave them blank and
only calls / tokens are shown.

Privacy:
  Requests are only sent when you click ✨ — the main entry
  flow is 100% local. Photos and history logs are never sent;
  only the item's current text fields are included.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📍  Item Details
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Click a row to open the inspector on the right.

Top-right buttons:
  ✨ Re-understand with AI  · Calls AI to re-parse fields
                              (requires a configured API key)
  ✏️ Edit                   · Open the full edit form

"Where is it now?" — four actions:
  · Still there      → Confirms it's in place; records history
  · Moved it…        → Edit location inline
                       (with the same autocomplete chips)
                       Clicking a chip replaces the field
                       content — it does not append
  · Put it back      → Marks it as returned to its spot
  · Lost track       → Clears location, keeps full history

Lending an item:
  A purple "Lend to…" button appears at the bottom of the
  detail page. Enter the borrower's name and confirm — the list
  row then shows a purple "Lent to: XX" label, and an orange
  "On loan to XX" badge appears at the top of the detail page.
  To mark it returned, click the badge or use right-click →
  Mark as returned.
  Both lending and returning are recorded as timeline events:
  a purple "Lent · to XX" row and an orange "Returned · ← XX"
  row appear in the history.

You can also search by borrower name directly in the search field,
and the "On Loan" facet in the filter panel lets you see all items
currently out — or only items that are home. See "Search & Filter"
for details.

Related items:
  · Other items in this group are listed as blue links
  · Clicking one swaps the inspector to that item's detail

Bottom timeline: location history and field edits, merged
  · Blue   = local parser
  · Green  = manual edit
  · Purple = AI change / lending event
  · Orange = user revert / return event
  · AI name changes show an ↩ Revert button on the right

Bottom: Delete (goes to Trash, restorable)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✏️  Editing
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Details → ✏️ Edit, or right-click a row → Edit Details…

Four sections:
  · Basic         Name + Notes
  · Optional info Model / Version / Color / Purchase date /
                  Source / Brand (read-only, inferred from name)
  · Photo         Photos library or Finder file
  · Tags          Multi-select + custom color

Related items:
  · Add or manage associations at the bottom of the edit form
    (also available via right-click → "Link to…")


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🔗  Related Items
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Group related items together so they're easy to find as a set.

Linking items:
  · Right-click a row → "Link to…"
  · Detail page / edit form → the Related Items section

Rules:
  · Up to 8 items per group; unlimited groups
  · Bidirectional and transitive: A↔B, then C links A
    → A↔B↔C all in one group
  · Two existing groups merge if their combined size is ≤ 8

Removing a link:
  · Tap × next to an item in the related list to unlink it
  · If the group would drop to a single item, it dissolves
    automatically (no orphan single-item groups)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🏷  Tags
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

14 presets are seeded on first launch:
  Daily · Tech · Kitchen · Tools · Office · Stationery ·
  Beauty · Apparel · Health · Food · Documents ·
  Hobby · Outdoor · Pets

Auto-tag suggestion:
  After recording an item, the app checks its name against
  a keyword dictionary (e.g. "phone" → Tech, "pan" → Kitchen)
  and auto-attaches the matching preset tag.
  A toast "Auto-applied tag: XX  [Undo]" lets you revert.
  Toggle off in Settings → General if you prefer manual tagging.

Managing tags (Settings → Tags tab):
  Each row shows the tag's color, name, item count, and a
  delete button. Click any color swatch to switch color
  instantly; the selected one has a stroke and a check mark.

Deleting a tag: use the Tags tab or right-click a tag row.
  Deletion only unlinks the tag — items are not affected.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🏷  Brand
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Brand is inferred automatically from the item name — you never
need to enter it manually, and it is never stored in the database.

Brand appears in three places:
  · List row chip
  · Detail page field area
  · Edit form "Optional info" section (read-only, updates live
    as you change the name)

Brand is also a filter facet — click a brand chip in the search
area to filter by that brand instantly.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🔍  Search & Filter
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The search field and record bar are pinned to the top at all
times. Expanding the filter panel only compresses the item list
below — the top bar never moves.

The chevron button next to the search field expands or collapses
the filter panel. When the panel is very tall, it caps at 280pt
and scrolls internally — it never pushes the top bar out of view.

Search: fuzzy match across name / location / model / color /
source / borrower name / tag name.

Six facets:
  Room      · Lists root-level locations only (Study, Living Room…)
              Count = all items in that room's entire subtree
              Selecting → shows all items anywhere in that room
  Location  · Lists non-root locations and orphan leaves
              Displays the full path (e.g. "Study > Storage drawer")
              Selecting → shows items at that exact path only
  Source    · Where you bought it (Taobao / Amazon / etc.)
  Year      · Purchase year
  Brand     · Auto-inferred from name (never stored)
  On Loan   · Only appears when at least one item is currently
              lent out. Two chips:
              "Out (N)"  — all items currently away from home
              "Home (M)" — everything that is not on loan

Room and Location can be active at the same time — Room narrows
by subtree, Location pins to an exact node.
Click a chip to toggle it. "Clear all" resets everything.

Active filter chips stay visible even when the filter panel is
collapsed, so you always know what filters are in effect.

Automatic data maintenance:
  On every launch the app quietly checks for two types of legacy
  data and cleans them up automatically —
  ① Locations whose names contain path separators (e.g. "Study >
    Drawer" stored as a single root — a rare AI artifact)
  ② Duplicate room roots with the same name but different casing
    (e.g. two separate "Study" entries)
  When cleanup runs, a toast at the bottom reports how many
  records were affected. Clean libraries see no toast at all.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📋  List & Multi-select
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

macOS list selection:
  · Click           Select one; inspector opens on the right
  · ⌘ + click       Add/remove from selection
  · ⇧ + click       Range select

With 2+ items selected (right-click or toolbar "Batch Edit"):
  · Add / remove tags (tri-state: ✓ all / — mixed / ○ none;
    clicking cycles through)
  · Set location (with autocomplete chips; clicking a chip
    replaces the field instead of appending)
  · Set purchase source
  · Mark all as just seen
  · Mark all as can't find
  · Re-understand all with AI (background, non-blocking)

Deleting:
  · Multi-select → Backspace or fn+Delete → confirm dialog
  · Right-click a single row → Delete
  · Detail page → Delete

All deletes go to Trash and can be restored.

Sort menu (top-right ↕):
  · Recently modified  (default)
  · Recently seen      Put-back / moved / can't find
  · Recently added
  · By name            Localized (pinyin for Chinese)
  · By location        No-location items go to the bottom

Quick right-click actions on a single item (no edit form needed):
  · Edit Details…
  · Set Tags…
  · Set Location…
  · Set Source…
  · Link to…
  · Pin (periodic reminder notification)
  · Lend to… / Mark as returned (shown based on current loan state)
  · Delete


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🗄  Trash
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Open via the Trash icon in the top-right toolbar.

Deleted items live here — hidden from the main list,
search, and stats.

Right-click → Restore (back to main list) or Delete permanently.
Toolbar → Empty Trash (permanent, confirmation required).

Items in Trash never expire. They stay until you purge them.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📦  Menu Bar (macOS)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Click the icon in the menu bar: type one line → Return →
saved instantly.

Skips duplicate detection and update-intent dialogs
(fire-and-forget). Shows the 5 most recent items.
"Open window" brings the main view forward.

To hide the icon: ⌘, → General → Menu Bar → turn off.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📱  iOS Version (iPhone / iPad)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Requires iOS 17 or later.

Three tabs:
  · Items    List + search + room filter chips + stat tiles
  · Record   Natural-language entry — same parsing rules,
             duplicate detection, and disambiguation prompts
             as the Mac version
  · Settings General / Input Behavior / Notifications / AI /
             Data / About
             Each option matches its Mac counterpart (see the
             sections above); they're just regrouped for a
             phone-sized screen

List gestures:
  · Swipe left      Pin
  · Swipe right     Delete or Edit
  · Long-press      Opens a menu: Pin / Edit / Lend to… /
                     Mark as returned / ✨ Re-understand with AI /
                     Delete

Detail page:
  · A location breadcrumb at the top, down to the root location
  · "Where is it now?" — five quick-action buttons: four for
    location status (Still there / Put it back / Moved it… /
    Lost track) plus a full-width purple "Lend to…". To mark a
    return, tap "Return" on the orange "Lent to XX" badge at the
    top (or long-press the list row and choose Mark as returned)
  · Location changes and field edits merge into a single
    timeline (same as the Mac version)
  · Related items are listed as blue links; tapping one jumps
    straight to that item's detail
  · Photos support full-screen viewing with pinch-to-zoom

Data storage:
  The iOS and Mac versions each keep their own data locally —
  there is no automatic sync between them. To move data between
  devices, use the JSON export / import under Settings → Data:
  export on one device, transfer the file, then import on the
  other (see the next section).


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  💾  Export & Import
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Export: top-right ⬆ button
  A confirmation dialog appears first, describing what the
  export contains: photos (base64) / locations / history /
  tags / loan status / pins / related-item links.
  Confirm to choose a save path and generate the JSON file.
  Note: API keys and other sensitive data are never included.

Import: ⌘, → Data tab → Import from JSON…
  A confirmation dialog explains that items will be appended
  to your existing library.
  "Skip duplicate items on import" toggle (on by default):
    · On:  Items with identical name + location are skipped.
    · Off: All items are imported, including duplicates —
           turn this off with care, as duplicate items are
           difficult to bulk-delete after the fact.

Clear all: ⌘, → Data tab → Clear all data
           Destructive, two-step confirm (export first)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚙️  Settings  (⌘,)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

General tab:
  · Language        Follow System / Chinese / English
                    (SwiftUI text updates instantly; some strings
                     need a restart to fully apply)
  · Appearance      Follow System / Light / Dark
  · Menu Bar        Show / hide the menu bar icon
  · Input           Detect duplicates toggle
                    Detect update phrases toggle
                    Both off = entries go straight in, no dialogs
  · Auto-tag        Toggle auto tag suggestion on/off
  · Global shortcut Default ⌥⌘N — click the button to enter
                    capture mode and press any modifier-key combo
                    to rebind. Works system-wide, from any app.
  · QuickEntry      Toggle on/off (disabling also disables the
                    global shortcut)

Tags tab:
  · View all tags with item counts
  · Inline color picker, rename, delete

AI tab:
  · Usage           Three columns: Today / This Week / This Month
                    Each shows: calls / input tokens / output
                    tokens / estimated USD (or ¥ for Volcengine)
                    Reset manually or wait for auto-reset at
                    month start
  · Provider: Claude / Volcengine (configured independently)
  · Model, API key, Endpoint (relay URLs accepted)
  · Volcengine section: optional "Input ¥/M tokens" and
    "Output ¥/M tokens" price fields (new in v0.1.7)
  · Custom system prompt with reset-to-default option
  · "Test connection" button
  · "View illustrated setup guide (web)" link (new in v0.2.0):
    opens the step-by-step web tutorial

Notifications tab:
  · Frequency       Daily / Weekly / 1st of each month
  · Day of week     Appears when "Weekly" is selected — pick any
                    day from Monday to Sunday (default: Monday)
  · Time            Time picker (default: 12:00 daily)
  · Content         Notification template — %@ is replaced with
                    the item name

Tapping a notification banner fills the main window's search field
with that item's name and brings the window forward; notifications
also appear as banners while the app is in the foreground.

Locations tab:
  · Tree view of all locations; root nodes split into two
    sections:
    🏠 Rooms (roots matching the room-word dictionary, e.g.
       bedroom / living room / study / kitchen)
    Standalone locations (all other roots)
  · Rename any row — the full path of every descendant updates
    automatically
  · "Merge into…" menu per row: moves the location, all its
    children, and all their items under another root
  · Delete is always available, even for non-empty nodes —
    items are promoted to the parent so no data is lost
  · Select multiple rows to get "Batch delete" and
    "Merge all into…" buttons at the top

Data tab:
  · Import from JSON
  · Clear all data (destructive)


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⌨️  Keyboard Shortcuts (macOS)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ⌘,              Settings
  ⌘?              This help
  ⌘N              Focus the top input field
  ⌘F              Expand search and focus the search field
  ⌘Q              Quit
  ⌥⌘N             Global shortcut: open QuickEntry from any app
                  (customizable in Settings → General)
  ⌘ + click       Add/remove from list selection
  ⇧ + click       Range-select rows
  Backspace /     Delete selected items (confirmation dialog)
  fn+Delete
  Return          Input bar: submit; alert: confirm
  Esc             Close photo viewer / sheet

QuickEntry (summoned via ⌥⌘N or your custom shortcut):
  A segmented picker at the top switches between two modes:
  · Record one    Type a sentence and press Return to save
                  instantly. A shortcut hint appears in the
                  top-right corner.
  · Search        Type keywords — results appear in the main
                  window's search field in real time.
  The selected mode is remembered between invocations.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📊  Bottom Status Bar (macOS)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

X items · in Y rooms · active for Z days

AI status (shown only when an API key is configured):
  · Green "AI ready · today N · week M · month K"
    Connection is tested automatically on launch; call counts
    for all three windows are shown when the test passes.
  · Red "AI connection failed — check your API settings in
    Whereabouts Preferences" with a "Retry" button on the right.
  · No AI row is shown when no API key has been set up.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ℹ️  About
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Author: Bam Cope
  Email:  pluginexpert2@gmail.com
  Built with: Claude Code

Menu bar  Whereabouts → About Whereabouts.


Version: 0.2.0 (build 1)
