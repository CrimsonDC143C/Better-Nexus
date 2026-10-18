# UI appearance

Presentation only. Nothing in this document changes rolling, Orb spending,
locking, saving, activation or any server request.

## Style and colour are two separate choices

`ui/Theme.lua` keeps two independent, presentation-only settings:

- **Style (structure)**: how windows and buttons are drawn.
- **Colour (palette)**: the accent colours the style draws with (borders,
  hover, glow and selection accents). Text colours belong to the style, so a
  palette choice never lowers text contrast.

A choice is read through `Store.Settings()` (`uiStyle`, `uiPalette`) and is
written only when the player picks one. Reading never rewrites a missing,
unknown or future saved value.

### Styles

| Style | Status | Default palette |
| --- | --- | --- |
| Nexus Vista | Default for a player who never chose. A deep, quiet backdrop with a soft accent edge and glow. | Nexus Amethyst |
| Nexus Slate | The earlier shared dark style of the imported 1.19.3 source and test.9094. Its colours and shapes use exactly the test.9094 literals. An explicit Slate choice stays Slate. | Nexus Graphite |

One difference from test.9094 applies to every style, Slate included: the Orb
run, history, copy and Continue windows used stock buttons and a flat backdrop
in test.9094. They now use the shared style too.

No other style ships. **Chronicle** is an optional proposal only: it is not
implemented, and no "Classic" or legacy style is offered or implied.

### Palettes

Six separate named palettes, each with a hue label shown beside its name:

| Palette | Hue label |
| --- | --- |
| Nexus Sapphire | blue |
| Nexus Emerald | green |
| Nexus Amethyst | purple |
| Nexus Ember | orange |
| Nexus Auric | gold |
| Nexus Graphite | gray (exactly the test.9094 accent set) |

The colour menu shows the style's own palette once, as **Default (name,
hue)**, for example "Default (Nexus Amethyst, purple)" under Nexus Vista.
A palette that paints the same colours as the style's own (compared by its
border, window border, hover, accent and disabled-border colours, not by
name) is not listed again; every other palette keeps its row. Default is
checked when no colour is saved and when the saved palette paints those same
colours; a saved colour this build does not know checks nothing and is named
as kept. Opening the menu writes nothing: a saved explicit palette, including
one equal to the default, stays saved and keeps applying when the style
changes. Choosing Default clears the saved colour.

Styling keeps native-looking controls without the bright red stock 3.3.5
`UIPanelButton` artwork.

## Protected difficulty / Soul Ash card

The replacement difficulty / Soul Ash card is an exempt tree. No style or
palette ever paints it.

## Orb history

The Orb history is a page of the Orb window (`NexusOrbRunLog` under
`NexusOrbPanel`), not a second window. Moving between "Run controls" and "Run
history" only shows and hides frames: it spends, starts, confirms and cancels
nothing. History rows use a subtle separator, a small Echo icon on the left,
clear text and a short result. Selecting a row only changes what is displayed.

Recorded names, reasons and notes are shortened only on a character
boundary, never inside a multi-byte letter. Pipes are escaped after the cut,
so an escaped pipe is never split, and a shortened value ends in "...". An
Echo name cell shows at most 30 letters and a reason cell at most 40 bytes.
The row tooltip and the details show the complete recorded name, reason and
note. The header's
Wishlist name is limited to 48 bytes; its tooltip shows the complete name.
In the copy report, operation lines use the bounded Echo display labels and
mark shortened names with "...". Wishlist and technical offer lines retain
the recorded names.

## Build Progress (Journal tab "Nexus Progress")

The tab inside the Echo Journal is headed **Build Progress**. It only reads:
opening it, refreshing it or expanding its details never rolls, spends Orbs,
locks Echoes, or saves or activates a Saved Build.

- **Intro**: one short line, "Assigned Wishlist vs active Saved Build.
  Read-only." The full purpose and notes are in the intro tooltip and under
  Show details.
- **Takeaway**: what is still missing, read from the Journal data's own Target
  and Pending sections. A Wishlist that requests no Echo family says so ("This
  Wishlist requests no Echo families, so there is no family progress to
  show.") and claims no coverage.
- **Family coverage, not copies**: a family is *represented* once one copy is
  known. It may still need more of the requested copies. "No requested Echo
  family is missing" never means the build is complete. This page does not
  list missing copies.
- **Unknown stays unknown**: the counts are used only when the Target line has
  its exact known form, exactly one Pending list matches its own count and the
  Target count, and the off-Wishlist list does not contradict the Target. A
  missing, unreadable or contradictory Pending list, counts that do not add
  up, or a changed Target wording all show "Family progress is unknown" with
  the raw Target line. Data that could not be read, or no data, is stated as
  such.
- **Counts**: "Represented N of T" and "Missing N", then the off-Wishlist
  families. The Journal data lists these only from an active Saved Build
  whose contents are confirmed, and it sends an empty list when none was
  compared, without a flag that tells the two apart. So a listed count is
  shown as supplied ("Off Wishlist N"), an empty list is "Off Wishlist: none
  listed" and never 0, and a missing or unreadable list is "Off Wishlist:
  unavailable". The counts line has a tooltip that explains these words.
  Represented families arrive as a count only, so no represented-family list
  is shown.
- **Echo rows** (display only): one row per supplied missing family and per
  off-Wishlist family line. Each row has a 24 px icon tile, the family text, a
  short status word ("Missing" or "Off Wishlist") and a tooltip with the
  complete name and, for an off-Wishlist row, the source text with its
  explanation. The name and the status each keep one line at the 26 px row
  height (no word wrap, 20 px high), so a long name is shortened on its line
  and never grows into the next row. Rows are pooled and reused; obsolete
  rows are hidden.
- **Plain words**: the page and its tooltips avoid implementation terms. The
  original lines stay unchanged under Show details.
- **Icons**: an icon is shown only when the row text is exactly one catalog
  family's name. The texture comes from a member spell linked back to that
  family (`familyName`, `familyMembers`, `familyOf`, `rows`, then
  `GetSpellInfo`). A shared, unknown or unlinked name gets the neutral
  question-mark tile. A known off-Wishlist explanation is never treated as
  part of a family name. The name index is built once per catalog table.
- **Estimate**: shown as "Estimate, not a prediction: ..." and based only on
  what is known to be missing; no future offer is assumed. When there is
  nothing to estimate (no requested family, or no result), it is shown as
  "Estimate: unavailable."
- **Show details**: the full page notes and every section as received,
  unchanged: Target, Pending, extra copies, Echo availability controls (Tome
  levers), Notes, estimate and version.
- **No Wishlist**: a short fallback plus "Assign in My Builds", which closes the
  page onto the Journal's own assignment controls. Assigning by itself does
  not change any Saved Build.

## Verification status

Offline prototype tests cover these behaviours with synthetic frames and data:
`ui_theme_appearance`, `orb_history_embedded`, `advisor_build_progress` and
`advisor_build_progress_runtime` (run through `tools/run_prototype_tests.py`).
`advisor_build_progress_runtime` renders what the real Journal data callback
writes in a synthetic runtime, and records the rows' no-wrap calls.

Native in-game checks are **NOT_RUN**: native font rendering, pixel fit,
icon textures on the live client, tooltip placement, and keyboard or other
accessibility behaviour have not been verified in the game client.
