# UX rubric

Rubric version: 2

The scorecard (`scripts/ux-score.py`, workflow `.github/workflows/ux-score.yml`) rates every screenshot of the app against this file. The vision judge reads this whole file as its instructions, and the script reads the criterion ids from the headings below. Change a criterion, an anchor or the scale, and you bump the version above: scores from different versions are not comparable, so the delta against the last main run is dropped when the version differs.

Based on Apple's Human Interface Guidelines (Materials, Toolbars, Sidebars, Sheets, Lists and tables, Buttons, Typography, Color, Accessibility, Layout) and the WWDC25 Liquid Glass sessions. The product rules it enforces are in `AGENTS.md` (native first) and `PLAN.md` (D15, D19, D21).

## Scale

Each criterion is scored 0 to 5 for one screenshot. Use `null` when the criterion does not apply to what the screenshot shows.

- 5: matches the guideline, nothing to fix.
- 4: one small, local flaw.
- 3: noticeable flaw, a user would see it but not stumble.
- 2: several flaws, or one that makes the screen feel unfinished.
- 1: a user would stumble or misread.
- 0: broken: the guideline is violated across the screen, or the screen does not render.

A screen total is the mean of its scored criteria times 20, so 0 to 100.

## How a score is made

- **Deterministic scorer.** Exact and repeatable: accessibility audit findings (hit area, contrast, clipped text, Dynamic Type, missing labels), the native-first ratchet count of the files that own the screen, and pixel checks on the PNG (blank capture, theme applied, no dim over the content beside the iPhone drawer, readable chat width on iPad and Mac). A pixel check only reports a failure or a measured value; it never claims the screen looks good.
- **Vision judge.** A model reads the PNG against this rubric and returns a score and a reason per criterion plus the single best fix. It runs twice with temperature 0: once with the criteria listed in this order, once reversed. The score is the mean of the two runs. The spread is the largest gap between the two runs, which is a lower bound on the judge's noise (two identical runs do not prove the judge is stable). A change smaller than the spread is noise, not a regression. The scorecard marks such deltas.
- **Combined.** For a criterion scored by both scorers, the combined score is their mean. Both are shown in `ux-score.json`.

## Criteria

### `native`

Native components, and Liquid Glass only on floating controls.

- 5: system lists, forms, navigation, toolbars, menus, sheets and search; glass only on the floating composer and model pill (system bars adopt glass by themselves); semantic colors and one tint.
- 3: a few hand-made rows, chips or buttons where a system control exists, or glass on a flat control.
- 0: custom nav bar, custom search field, cards instead of grouped rows, glass or blur on content, glass on glass.
- Deterministic part: custom-UI pattern count in the files that own the screen (`scripts/native-ratchet.sh` patterns): 0 hits is 5, up to 2 is 4, up to 5 is 3, up to 10 is 2, up to 20 is 1, more is 0.

### `hierarchy`

Hierarchy and typography.

- 5: one clear primary element, titles larger than body, secondary text visibly secondary, system text styles (Dynamic Type), no text clipped or truncated when it did not need to be; nothing dims the content next to the iPhone drawer (PLAN D19).
- 3: the primary action competes with another element, or one level of type is missing, or one label truncates early.
- 0: no discernible hierarchy, or text is unreadable or cut off.
- Deterministic part: clipped or fixed-size text findings of the accessibility audit, and the drawer dim check.

### `spacing`

Spacing and alignment.

- 5: consistent margins and gaps on the system grid, aligned leading edges, safe areas respected, nothing touching an edge or another control.
- 3: one uneven gap or misaligned item.
- 0: overlapping or colliding elements, content under the home indicator or status bar.

### `tap_targets`

Every tappable control has at least a 44 by 44 pt hit region and enough room around it.

- 5: all controls look at least 44 pt and are not crowded.
- 3: one small or crowded control.
- 0: many small icon-only controls packed together.
- Deterministic part: "hit area too small" findings of the accessibility audit, 5 minus the count.

### `contrast`

Contrast in the shown appearance (light or dark): text 4.5:1, large text and icons 3:1, no gray-on-gray secondary text.

- 5: every text and icon is easy to read, in both appearances.
- 3: one low-contrast label or placeholder.
- 0: large parts unreadable, or the wrong appearance is shown.
- Deterministic part: "contrast failed" findings of the audit, 5 minus the count, and the check that the requested appearance is on screen.

### `clutter`

Clutter: the number of controls in the chrome (toolbar, headers, composer row).

- 5: at most three controls per bar, each with an obvious purpose, nothing decorative.
- 3: four or five controls, or one decorative element.
- 0: six or more controls in a bar, or several competing badges, banners or chips.

### `consistency`

Consistency of icons, logos and patterns: a model is drawn the same way everywhere (`ModelLabel`), same symbol for same action, same row style in similar lists.

- 5: model logos and names look the same in every place on the screen and match the other screens you know of; icons share one weight and style.
- 3: one place draws a model or an action differently, or mixes icon weights.
- 0: several different treatments of the same thing.

### `color`

Color: one tint, semantic colors, color that means something.

- 5: one app tint (black in light, white in dark), system semantic colors for text and surfaces, color only where it carries meaning (a status, a destructive action, a Settings icon tile), the same status in the same color on every screen, nothing relies on color alone.
- 3: a second accent color without a reason, or one status drawn in two colors.
- 0: many unrelated colors, hard-coded colors that break in the other appearance, or color as the only signal.

### `iconography`

Iconography: SF Symbols of one weight and style, the same symbol for the same thing.

- 5: SF Symbols only, one weight and size per context, Settings rows use the same tile style (white symbol on a rounded square of one system color), symbols are recognizable and match their label.
- 3: one icon of a different weight or style, or one symbol that does not match its label.
- 0: mixed icon sets and sizes, symbols that mislead, or icons with no label where the meaning is not obvious.

### `states`

Empty, loading and error states.

- 5: an empty screen says what it is and what to do next, a progress or error state is visible and actionable.
- 3: the state is clear but offers no next step.
- 0: a blank screen, a spinner with no context, or a raw error string.
- Use `null` for a screen that is just full of content.

### `space`

Use of space on iPad and Mac: readable line width (about 720 pt for chat), sidebars where the width allows, no stretched phone layout, no tiny phone layout floating in a large window. On iPhone score the use of the screen: content reaches the safe-area margins, no large dead areas.

- 5: the layout fits the size class: a readable column, a sidebar or split view where wide.
- 3: usable but wasteful or too wide for reading.
- 0: the phone layout stretched edge to edge, or content lost in a large empty area.
- Deterministic part: on iPad and Mac chat screens (portrait, landscape and with a sidebar open), the 90th percentile width of the widest text run in each row, where a sidebar and the chat beside it count as separate runs: up to 780 pt is 5, up to 900 pt is 4, up to 1000 pt is 2, more is 0.

### `semantics` (audit only)

VoiceOver names and traits: every control has a human-readable label, the right trait, and no duplicated or missing description. A screenshot cannot show this, so only the accessibility audit scores it: 5 minus the count of description, label and trait findings.
