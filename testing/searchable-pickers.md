# Searchable Pickers - Testing Plan

## Human Testing

Open any piece from the album to get to the detail screen.

### Clay Picker
1. Tap the Clay dropdown - bottom sheet opens with search bar and list
2. Verify "None" is at the top
3. Type "por" in search - only "Porcelain" should show, "None" should disappear
4. Clear search - "None" returns, full list shows
5. Select a clay - picker closes, field updates
6. Verify NO clay pills appear below the dropdown (pills only show when clay is "None")
7. Clear the clay (open picker, tap "None") - recent clay pills should now appear (up to 3)
8. Tap a pill - clay field changes, pills disappear

### Glazes Picker
1. Tap Glazes dropdown - multi-select bottom sheet with checkboxes
2. Search for a glaze - filters correctly, "None" hides
3. Check/uncheck a few glazes
4. Tap Done - field shows comma-separated names
5. Check for recent glaze pills below the field
6. Tap a glaze pill - adds it to selection, pill disappears

### Tags Picker
1. Tap Tags dropdown - multi-select with colored dots next to each tag name
2. Verify dots match tag colors
3. Select/deselect tags, tap Done
4. Check for recent tag pills below field - they should have colored dots
5. Tap a tag pill - adds to selection, pill disappears

### Add New (test on any picker)
1. Open a picker, type a name that doesn't exist (e.g. "MyNewClay")
2. `+ Add "MyNewClay"` should appear at the bottom
3. Tap it - dialog opens with "MyNewClay" pre-filled
4. Tap Create - new item is created and selected
5. Also test the static "+ Add New" button (with empty search) - dialog should open with empty field

### Edge Cases
1. Open a piece with no clay/glazes/tags set - fields should show "None"
2. Select a clay, go back, open a different piece - the clay you just used should appear as a recent pill
3. Select all 3 recent pills one by one - they should each disappear as tapped

---

## Agent Testing (computer-use subagent)

### Prerequisites
- Request Simulator access: `request_access(apps: ["Simulator"])`
- App must be running on iOS simulator (iPhone 16 Pro: `596FA2B9-8F2D-4E57-BEF5-29F2C3DB6A1B`)
- To populate test data, temporarily add seed code in `main.dart` inside `if (kDebugMode)` block — assign different clays/glazes/tags to at least 3 pieces so recent pills appear

### Seed Data Setup
Before agent testing, ensure pieces have diverse materials assigned:
- Piece 1: Clay = Porcelain, Glazes = Clear + Celadon, Tags = Gifts + Practice
- Piece 2: Clay = Stoneware, Glazes = Tenmoku + Shino, Tags = Sale + Commission
- Piece 3: Clay = Earthenware, Glazes = Ash + Copper Red, Tags = Exhibition + Experiment

Remove seed code before committing.

### Test 1: "None" hidden during search
1. Take screenshot to verify app is loaded
2. Tap a piece in the album list
3. Scroll down to metadata form
4. Tap Clay dropdown field
5. Screenshot - verify "None" is visible
6. Type search text (e.g. "stone")
7. Screenshot - verify "None" is NOT visible, only matching items show
8. Clear search text
9. Screenshot - verify "None" returns

### Test 2: Clay pills only when no clay selected
1. Open a piece that has a clay set
2. Scroll to clay field
3. Screenshot - verify NO clay pills appear below the dropdown
4. Open clay picker, select "None" to clear the clay
5. Screenshot - verify recent clay pills now appear (up to 3)

### Test 3: Clay pill tap-to-select + disappear
1. With clay set to "None" and pills visible, tap a clay pill
2. Screenshot - verify clay field updated to tapped value AND all pills disappeared

### Test 4: Glaze pill tap-to-select + disappear
1. Scroll to glazes field
2. If glaze pills are visible, tap one
3. Screenshot - verify glaze was added to selection, pill disappeared

### Test 5: Tag pill colored dots + tap behavior
1. Scroll to tags field
2. Screenshot - verify tag pills have colored dot circles
3. Tap a tag pill
4. Screenshot - verify tag added to selection, pill disappeared

### Test 6: Tag picker colored dots
1. Tap Tags dropdown to open picker
2. Screenshot - verify each tag in the list has a colored dot circle next to its name
3. Close picker

### Test 7: "Add New" with pre-filled name
1. Open any picker
2. Type a non-existent name (e.g. "newtestclay")
3. Screenshot - verify `+ Add "newtestclay"` option appears
4. Tap it
5. Screenshot - verify dialog has the name pre-filled
6. Tap Cancel

### Agent Tips
- Use `key` tool for typing into iOS simulator text fields (the `type` tool may not work reliably)
- Use `scroll` on the simulator to navigate the metadata form
- Take screenshots at verification points to confirm UI state
- The simulator keyboard may interfere with search — dismiss autocomplete suggestions if needed
