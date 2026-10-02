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

When a location is ambiguous:
  If the location you typed is a single segment (such as "top
  drawer") and several locations with that name already exist, a
  "Pick a location" prompt lists their full paths. Choose an
  existing one, or create a new top-level location.
  When several items in one entry are ambiguous, you're asked about
  each in turn and every item can be saved. If you cancel them all,
  your text stays in the input box.
  (macOS) Items that share the same location wording are asked
  about only once. If you cancel just some, the unsaved ones go
  back into the input box with a note.

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
  · API key: entered here. It's stored in this device's system
    Keychain and used only to call the AI provider you chose —
    never synced or uploaded, and the developer can't see it.
  · Endpoint: defaults to the official URL; change it to a
    relay or proxy if direct access isn't available
  · "Test connection" verifies the key in about 1 second
  · "View illustrated setup guide (web)" link: a step-by-step
    walkthrough for signing up and topping up a Claude or
    Volcengine account, getting an API key, entering it in the
    app, estimating cost, and troubleshooting errors. Bilingual
    (中/EN), available on both Mac and iOS.

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
  · Purchase dates keep the precision you gave: "bought in 2024"
    records just the year, and if you name a month it records the
    month — AI never makes up a month or day

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
  On iPhone, right after AI renames an item, its list row also
  shows a small "Undo" button for about 10 seconds.

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
  Your API key stays in this device's Keychain. It is not synced
  through iCloud and never appears in exported JSON files or
  iCloud Drive backups.


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

Tag rows:
  · Right-click (iPhone: long-press or swipe left) a tag that's on
    the item → "Remove from This Item". This only takes the tag off
    this item — the tag itself stays.
  · To delete a tag everywhere, use Settings → Tags
    (iPhone: Settings → General → Manage Tags).

Done and Cancel:
  · Done    Saves your edits.
  · Cancel  Discards this session's edits: fields (name, notes and
            so on), the photo and tags all go back to how they were
            when you opened the form, and tags created here but
            left unused are removed. On Mac, Esc does the same.
  · Related items apply immediately, so Cancel doesn't undo them.
  · iPhone: while the form has unsaved changes it can't be swiped
    down — tap Cancel to discard or Done to save.

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

Deleting a tag: Settings → Tags tab, click the trash button on the
  tag's row (iPhone: Settings → General → Manage Tags).
  Deletion only unlinks the tag — items are not affected. With
  iCloud Sync on, the tag also disappears from your other devices.
  The edit form can only take a tag off the current item; it never
  deletes the tag itself.

Duplicate tags:
  With iCloud Sync on, if two devices each created a tag with the
  same name (the presets, for example), they're merged into one
  automatically and every item keeps its tag.


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
  With iCloud Sync on, neither cleanup runs automatically —
  merging locations could delete sub-locations that haven't
  synced from your other device yet. If you see duplicate
  locations, merge them by hand with "Merge into…" in
  Settings → Locations
  (iPhone: Settings → General → Manage Locations).


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📋  List & Multi-select
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

macOS list selection:
  · Click           Select one; inspector opens on the right
  · ⌘ + click       Add/remove from selection
  · ⇧ + click       Range select

iPhone: tap "Select" at the top left of the Items tab to
multi-select; the batch menu is described under "iOS Version".

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

Mac: open via the Trash icon in the top-right toolbar.
iPhone: on the Items tab, tap ⋯ at the top right → Trash.

Deleted items live here — hidden from the main list,
search, and stats.

Mac: right-click → Restore (back to main list) or Delete
permanently; toolbar → Empty Trash.
iPhone: swipe right to restore, swipe left to delete permanently;
the trash icon at the top right → Empty Trash.
Emptying the Trash is permanent and needs confirmation.

Items in Trash never expire. They stay until you purge them.

With iCloud Sync on, the Trash syncs too:
  · Move an item to the Trash on one device and it goes to the
    Trash on your other devices as well, disappearing from their
    main lists.
  · Items trashed on another device show up in this device's Trash.
  · Restoring or deleting permanently syncs to your other devices
    too.

Note: after updating, items that were deleted on another device
but still showed here are moved to the Trash. Restore any you
want to keep.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📦  Menu Bar (macOS)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Click the icon in the menu bar: type one line → Return →
saved instantly.

Skips duplicate detection and update-intent dialogs
(fire-and-forget). Shows the 5 most recent items.
"Open window" brings the main view forward.

With the main window closed, the menu bar icon, the global
shortcut (⌥⌘N) and clicking a reminder keep working. "Open window"
brings the existing main window forward instead of opening
another one.

To hide the icon: ⌘, → General → Menu Bar → turn off.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📱  iOS Version (iPhone / iPad)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Requires iOS 17 or later.

Three tabs:
  · Items    List + search + stat tiles (the tiles double as
             filters — see below)
  · Record   Natural-language entry — same parsing rules,
             duplicate detection, and disambiguation prompts
             as the Mac version. A microphone button sits to the
             left of "Save it": tap it to dictate — the recognized
             text is added to the input box — and tap again to
             stop. The first time, allow microphone and speech
             recognition access; if recognition is temporarily
             unavailable (for example, offline), you'll see a note
  · Settings AI / General / Input Behavior / Notifications /
             iCloud Sync / Data / About
             Each option matches its Mac counterpart (see the
             sections above); they're just regrouped for a
             phone-sized screen. Manage Tags and Manage Locations
             live under General

Stat tiles (top of the Items tab) double as filters:
  · Items    Tap to clear all filters
  · Rooms, Source, Brand, Year
             Tap to open a menu and pick one; pick the same one
             again to clear it
  · Pinned, Lent
             Tap to show only pinned / lent items; tap again to
             clear
  A selected tile gets an outline and shows the chosen value.
  Source, Brand and Year only appear when you have data for them.

Toolbar on the Items tab:
  · Select    Enter multi-select. Tick items, then tap ⋯ at the top
              right for the "Batch Edit" menu: Add Tags / Set
              Location / Set Source / Mark All as Just Seen /
              Mark All as Can't Find / Re-understand with AI /
              Delete. Multi-select ends when the action finishes
  · New note  Jump straight to the Record tab
  · ☁️        Sync with iCloud now (shown only while iCloud Sync
              is on)
  · ⋯         Sort options and the Trash

List gestures:
  · Swipe right     Pin
  · Swipe left      Delete or Edit
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

Data sync:
  iPhone / iPad and Mac sync automatically through your own
  iCloud, so there's no need to move data by hand. See "iCloud
  Sync" next.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ☁️  iCloud Sync
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Sign in to the same Apple Account on your Mac and your
iPhone / iPad, and your data syncs automatically through your
own iCloud. No sign-up, no third-party server — and the
developer can never see your content.

What syncs:
  Items (with photos), locations, tags, history, and loan /
  pin / related-item status.

Getting started:
  1. Sign in to the same Apple Account on both devices in
     system Settings
  2. Make sure the "iCloud Sync" switch is on (it is by default)
     Mac: Settings → General; iPhone: Settings → iCloud Sync
  3. Add, edit or delete on either device — changes usually show
     up on the other within seconds to a minute or two

When you switch back to the app, it also pulls the latest
changes from your other device.

The badge next to the switch shows the current state:
  · On          iCloud is connected for this launch
  · Local only  iCloud isn't in use this launch (the switch is
                off, or sync couldn't start); your data is still
                saved on this device. If sync couldn't start,
                reopening the app tries again
Changing the switch takes effect the next time you open the app.
With sync off, data stays on this device only — you can still
move it between devices with JSON export / import.

Checking sync status:
  Mac:    Settings → General → iCloud Sync
  iPhone: Settings → iCloud Sync
  · iCloud Account  Signed in (your name shows when available) /
                    Not signed in to iCloud / Restricted (Screen
                    Time or device management) / Temporarily
                    unavailable
  · Account ID      Apple doesn't let apps read your Apple ID
                    email, so a short code is shown instead. If
                    the code matches on two devices, they're on
                    the same iCloud account.
  · Last received   When changes last arrived from iCloud
  · Last sent       When changes were last sent to iCloud
  · Sync errors     When something goes wrong, one plain sentence
                    says why — e.g. "iCloud storage is full — new
                    changes can't be uploaded". Self-recovering
                    hiccups such as a brief network drop stay quiet.
  · Sync Now        Saves your pending changes, waits for the
                    current upload and download round to finish,
                    then reports the result: "Synced with iCloud" /
                    "Not signed in to iCloud — can't sync" /
                    "Sync hit an error — it will retry automatically"
  Last received / sent, errors and Sync Now appear only while sync
  is active.

Sync Now on iPhone:
  Pull down to refresh on the Items tab, or tap the ☁️ button at
  the top right — both work the same as Sync Now in Settings. The
  ☁️ button only appears while iCloud Sync is on.

If you're not signed in to iCloud:
  Settings explains that this device isn't signed in, so your data
  is only on this device for now. Sign in to your Apple Account in
  system Settings (the same one as your other device) and syncing
  starts automatically.

What doesn't sync:
  · Your AI API key lives only in this device's Keychain
  · Settings are per device too — on a new device, set up AI again
  · iCloud Drive backup files don't take part in syncing (see
    "Export & Import")

If something goes wrong:
  · If Settings says "The local database couldn't be opened this
    time… changes won't be saved", or the app shows "Your data
    can't be opened right now": your data file is still there —
    nothing is lost. Quit the app completely and open it again;
    if it keeps happening, contact the author (see "About").


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  💾  Export & Import
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Export: top-right ⬆ button
  A confirmation dialog appears first, describing what the
  export contains: photos (base64) / locations / history /
  tags / loan status / pins / related-item links.
  Confirm to choose a save path and generate the JSON file.
  Note: API keys and other sensitive data are never included.

Import: ⌘, → Data tab → Bulk import from JSON… (iPhone: Settings → Data)
  A confirmation dialog explains that items will be appended
  to your existing library.
  "Skip duplicate items on import" toggle (on by default):
    · On:  Items with identical name + location are skipped.
    · Off: All items are imported, including duplicates —
           turn this off with care, as duplicate items are
           difficult to bulk-delete after the fact.
  With iCloud Sync on, imported items sync to your other devices too.

iCloud Drive Backup: ⌘, → Data tab → iCloud Drive Backup
                     (iPhone: Settings → Data)
  Tap "Back Up Now" to save all your items as one JSON file in
  iCloud Drive › Whereabouts (visible in Finder on Mac and in the
  Files app on iPhone).
  · Each device writes its own file; the file name includes the
    device type and a short device code, e.g.
    whereabouts-backup-iPhone-3F2A.json
  · Backups also run automatically: when you quit the app on Mac,
    and when you leave the app (switch away) on iPhone. If nothing
    has changed, the backup is skipped, and an empty library never
    writes an empty backup
  · It's a visible safety copy and doesn't take part in syncing —
    it never reads or merges other devices' files and never changes
    your items
  · To restore, use "Bulk import from JSON…" above and pick that file
  · If you see "Backup failed", make sure you're signed in to iCloud
    with iCloud Drive turned on
  · Duplicates left behind by the old "Manual Sync" aren't removed
    automatically — delete them by hand

Clear all: ⌘, → Data tab → Clear all data (iPhone: Settings → Data)
           Destructive, two-step confirm (export first)
  Removes all items, locations, history and tags — this can't be
  undone. With iCloud Sync on, the data on your other devices signed
  in to the same Apple Account is erased too.
  If something goes wrong, nothing is deleted and the reason is shown.


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
                    capture mode and press a new combo to rebind.
                    It must include ⌘, ⌥ or ⌃ (⇧ alone doesn't
                    count). Combos already used by the system or
                    by common editing are rejected with an
                    explanation — for example ⌘-only ⌘Q / ⌘C,
                    ⌥-only typing combos, ⌃Space for switching
                    input sources, and screenshot shortcuts. If
                    the new combo can't be registered (another app
                    may be using it), your previous one is kept.
                    Works system-wide, from any app.
  · QuickEntry      Toggle on/off (disabling also disables the
                    global shortcut)
  · iCloud Sync     Toggle on/off (on by default; takes effect the
                    next time you open the app). Below it: your
                    iCloud account, Account ID, last received /
                    last sent times, and a "Sync Now" button (see
                    "iCloud Sync")

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

Notifications (in the General tab):
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
  · Bulk export to JSON…
  · Bulk import from JSON… (with the "Skip duplicate items on
    import" toggle)
  · iCloud Drive Backup: the "Back Up Now" button and the last
    backup time
  · Clear all data (destructive; with iCloud Sync on, your other
    devices are cleared too)


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

  Author: Chengzhu Zhao
  Email:  pluginexpert2@gmail.com
  Built with: Claude Code

Menu bar  Whereabouts → About Whereabouts.


Version: 1.1.1 (build 3)
