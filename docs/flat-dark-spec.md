# Notchless "Flat dark tinted" — implementation spec

Source of truth: `~/Downloads/notch-ui-liquid-glass-redesign/project/Notchless Liquid Glass.dc.html`
(Claude Design project `3fb18656-8e07-4a5e-a87a-41793df16f65`).
Two screens: **Turn 2 — Flat dark tinted** (notch UI, `#2a`) and **Turn 3 — Settings flat dark** (`#3a`).

Design thesis: no glass, no glow, no gradients. One opaque tinted-dark surface, a 0.5px
hairline, white monochrome content. Colour only where it carries meaning (charge, alert,
done). Mockup pixels are 1:1 with macOS points — the mock notch cutout is 196x32, matching
the real MacBook notch — so every number below is a point value.

## 1. Tokens

### Surface tint (user-selectable, applies to every notch state)
| Name | Hex |
|---|---|
| Graphite (default) | `#171A22` |
| Blue | `#141B2E` |
| Purple | `#1D1530` |
| Green | `#122019` |
| Black | `#0B0B0E` |

### Notch surface
- background: the selected tint, fully opaque
- border: `0 0 0 0.5px rgba(255,255,255,0.08)` — a 0.5pt hairline, no shadow, no blur
- corner radius: bottom corners only, top corners square. Radius varies by state (see §3)
- foreground: `#F2F3F5`

### Text on notch
| Role | Colour |
|---|---|
| primary | `#F2F3F5` |
| secondary | `rgba(235,238,245,0.55)` |
| tertiary / de-emphasised | `rgba(235,238,245,0.45)` |
| bright secondary | `rgba(235,238,245,0.75)` |

### Fills on notch
| Role | Colour |
|---|---|
| track (progress/slider unfilled) | `rgba(255,255,255,0.16)` |
| fill (progress/slider filled) | `#FFFFFF` |
| chip / control button | `rgba(255,255,255,0.09)` |
| inset row / list item | `rgba(255,255,255,0.06)` |
| artwork placeholder | `#3A3D45` |
| ring track | `rgba(255,255,255,0.14)` |
| divider (vertical, duo) | `rgba(255,255,255,0.10)` |

### Semantic colour (the only colour allowed)
| Meaning | Colour |
|---|---|
| charge / done / on track | `#30D158` |
| recording / destructive | `#FF453A` |
| destructive text | `#FF6961` |
| warning / mic-in-use | `#FF9F0A` |
| bluetooth / link | `#0A84FF` |
| focus | `#BF5AF2` |

### Settings window
| Role | Colour |
|---|---|
| window body | `#1B1D24` |
| sidebar | `#14161C` |
| sidebar border-right | `rgba(255,255,255,0.06)` |
| window border | `0 0 0 0.5px rgba(255,255,255,0.1)` |
| window shadow | `0 24px 60px rgba(0,0,0,0.35)` |
| card / grouped section | `rgba(255,255,255,0.05)` |
| card divider | `rgba(255,255,255,0.07)` |
| control chip (picker/button) | `rgba(255,255,255,0.08)` |
| button (secondary) | `rgba(255,255,255,0.09)` |
| inset field | `rgba(255,255,255,0.07)` |
| icon chip (pane header) | `rgba(255,255,255,0.08)` |
| selected sidebar row | `rgba(255,255,255,0.10)` |
| switch ON | `#30D158` |
| switch OFF | `rgba(255,255,255,0.14)` |
| switch knob ON | `#FFFFFF` |
| switch knob OFF | `rgba(255,255,255,0.85)` |
| destructive button bg | `rgba(255,69,58,0.14)` |
| selected segment / primary button | bg `#F2F3F5`, fg `#171A22` |

### Typography
System font (`-apple-system` / SF). All numeric readouts use tabular figures.

| Use | Size / weight |
|---|---|
| notch compact value | 13 semibold |
| notch title (notification) | 13 semibold |
| notch subtitle | 11 regular |
| notch big value (battery/timer) | 24 bold |
| notch section label | 11-12 semibold, secondary colour |
| notch wing battery % | 10 medium, secondary |
| calendar day number (expanded) | 40 semibold |
| settings pane title | 17 bold |
| settings pane subtitle | 12, `rgba(235,238,245,0.55)` |
| settings section header | 10 semibold, uppercase, letter-spacing 0.06em, `rgba(235,238,245,0.45)` |
| settings row | 13 |
| settings footnote | 11, line-height 1.5, `rgba(235,238,245,0.45)` |
| sidebar row | 12 medium |
| sidebar section header | 10 semibold, uppercase, letter-spacing 0.05em, `rgba(235,238,245,0.5)` |

## 2. Wings tab strip (expanded panels)

Every expanded panel reserves the top 32pt — the row beside the physical notch cutout.
- container: full width, height 32, horizontal padding 14, `zIndex 1`
- LEFT wing: the activity glyphs, 12x12, `gap 12`, `align center`
  - inactive glyph: `opacity 0.35`
  - active glyph: full opacity, plus a 3x3 dot centred 2pt below it (`currentColor`, circular)
- RIGHT wing: battery percentage, 10 medium, `rgba(235,238,245,0.55)`, tabular
- Panel content below starts at `padding-top: 42`.

Interaction: position dot under the active glyph; hover shows the page label; tapping a
neighbouring glyph slides by one.

## 3. Notch states — exact geometry

Width x height, bottom-corner radius. Top corners square. Cutout overlay is 196x32,
radius `0 0 9px 9px`, pure black, centred.

### Compact / idle (height 34, radius 11, content padding `0 18`, space-between)
| State | Width | Content |
|---|---|---|
| Bare notch | — | no surface, just the 196x32 cutout |
| Idle · Now Playing | 324 | 20x20 rounded-6 `#3A3D45` art chip w/ 10x10 note glyph · 5-bar dancing visualiser, bars 3.5w, 15h, radius 2, white |
| Idle · Battery | 346 | 22x12 battery glyph in `#30D158` · `87%` 13 semibold |
| Idle · Todos | 324 | green check + count (`#30D158`) · open circle + count (`#F2F3F5`) |
| Idle · Calendar | 292 | day number 15 bold · 13x13 calendar glyph opacity 0.85 |
| Idle · Timer | 334 | 14x14 timer glyph opacity 0.9 · `12:43` 13 semibold |
| Idle · Duo | 346 | art chip · day number 13 bold |
| Idle · Stats | 346 | 13x13 chip glyph opacity 0.9 · `38%` 13 semibold |
| Idle · Clipboard | 292 | 12x12 clipboard glyph opacity 0.9 · count 13 semibold |
| Idle · Goals | 386 | 16x16 progress ring (`#30D158` on `rgba(255,255,255,0.16)`, width 2.5) + `32%` · `$3.2k` |
| Idle · Claude usage | 350 | 14x14 clock glyph opacity 0.9 · `$12.40` 13 semibold |
| Idle · Privacy | 326 | two 8x8 pulsing dots (`#30D158`, `#FF9F0A`, 1.6s, second offset -0.8s) · camera glyph `#30D158` + mic glyph `#FF9F0A` |
| Idle · Meeting recording | 324 | 8x8 pulsing `#FF453A` dot · elapsed `12:04` 13 semibold, `rgba(235,238,245,0.75)` |
| Idle · Dictation | 324 | 22x22 circular `rgba(255,255,255,0.09)` mic button · 5 static bars (3w, heights 4/7/10/6/4, radius 1.5) at opacity 0.55 |
| File Tray · Compact | 292 | 13x13 tray glyph opacity 0.9 · count 13 semibold |

### HUD (height 68, radius 18, content `align-items:flex-end`, padding `0 26 15`, gap 8)
| State | Width | Content |
|---|---|---|
| HUD · Volume | 490 | speaker glyph 16x14 · `Volume` 13 bold · spacer · 120x6 bar radius 3 (`rgba(255,255,255,0.16)` track, `#FFFFFF` fill, bottom margin 3) · `65%` 12 semibold |
| HUD · Brightness | 490 | sun glyph 15x15 · `Brightness` 13 bold · spacer · same 120x6 bar · `72%` 12 semibold |

### Notification banners (height 70, radius 20, `align-items:flex-end`, padding `0 24 14`, gap 12)
Layout: 30x30 rounded-8 icon chip tinted at 16% of the semantic colour, glyph in that
colour · title 13 semibold + subtitle 11 regular secondary · spacer · trailing.

| State | Width | Chip tint | Title / subtitle | Trailing |
|---|---|---|---|---|
| Charging | 496 | `rgba(48,209,88,0.16)` | `Charging` / `MacBook Pro — 2:14 until full` | `87%` 15 semibold `#30D158` |
| Bluetooth | 496 | `rgba(10,132,255,0.16)` | `AirPods Pro` / `Connected` | `72%` 15 semibold `#0A84FF` |
| Focus | 496 | `rgba(191,90,242,0.16)` | `Do Not Disturb` / `Focus on until 6:00 PM` | 11x11 close glyph opacity 0.4 |
| No Internet | 496 | `rgba(255,159,10,0.16)` | `No Internet` / `Wi-Fi is connected without internet` | 11x11 close glyph opacity 0.4 |

### Expanded panels (radius 24 unless noted, content padding-top 42, wings strip on top)
| State | W x H | Layout |
|---|---|---|
| Expanded · Battery | 360 x 110 | padding `42 30 16`, gap 16. 48x48 ring (r 28.5, width 7, track `rgba(255,255,255,0.14)`, fill `#30D158`) · `Battery · Charging` 11 semibold secondary / `87%` 24 bold / `2:14 until full` 11 secondary |
| Expanded · Now Playing | 480 x 178 | padding `42 19 14`, gap 10. Row: 44x44 rounded-8 `#3A3D45` art · title 14 semibold / artist 12 secondary · 5-bar visualiser (3.5w, 18h). Scrubber row: `1:24` 10 medium (w 34) · 5pt bar radius 2.5 · `-1:57` (w 40). Transport row: centred, gap 26 — prev 17x14 opacity 0.85, 34x34 circular `rgba(255,255,255,0.09)` play/pause, next 17x14 |
| Expanded · Todos | 420 x 210 | padding `42 16 14`, gap 9. Header `Tasks` 12 semibold secondary · spacer · `Clear done` · `3 left` (both 11 medium secondary). Rows: 15x15 circle (done = `#30D158` ring + check, open = `currentColor` opacity 0.6) + 13 regular label; done row is secondary + strikethrough; optional `1/3` 11 semibold secondary. Footer: `+ Add a task…` 13 secondary in `rgba(255,255,255,0.06)` rounded-8, padding `7 10` |
| Expanded · Stats | 420 x 140 | padding `42 19 16`, gap 10. Rows: 56pt label 12 medium secondary · 5pt bar radius 2.5 · 62pt right-aligned value 11 medium. Network row: label · spacer · `↓ 2.4 MB/s` · `↑ 184 KB/s` (11 medium, `rgba(235,238,245,0.75)`) |
| Expanded · Timer | 380 x 128 | padding `42 24 16`, gap 18. 52x52 ring (r 26, width 6, fill `#FFFFFF`) with clock glyph inside · `12:43` 24 bold · three 32x32 circular `rgba(255,255,255,0.09)` buttons (pause / restart / cancel), gap 10 |
| Expanded · Goals | 420 x 200 | padding `42 16 14`, gap 8. Header `Goals` 12 semibold secondary · `2 active` 11 secondary. Card: `rgba(255,255,255,0.06)` rounded-8 padding 10, gap 6 — name 12 semibold + `32%` 11 semibold · 4pt bar radius 2 · `$3,200 / $10,000` 10 secondary + `On track · need $850/mo` 10 medium `#30D158`. Footer row: `rgba(255,255,255,0.06)` rounded-8 padding `7 10` — 13x13 plus glyph opacity 0.75 + `Log contribution` 12 medium `rgba(235,238,245,0.7)` |
| Expanded · Clipboard | 420 x 200 | padding `42 16 14`, gap 8. Header `Clipboard` 12 semibold secondary · spacer · `Pick colour` 11 medium w/ 11x11 eyedropper · close glyph. Rows: `rgba(255,255,255,0.06)` rounded-8 padding `7 10`, 12 regular, truncating. Copied row shows `Copied` 10 semibold `#30D158` + check. Colour row shows a 10x10 rounded-3 swatch + hex |
| Expanded · Calendar | 470 x 196 | padding `42 19 16`, gap 16, top-aligned. Left col w 150: weekday 11 bold secondary letter-spacing 0.06em · day 40 semibold · `72° Sunny` 12 medium `rgba(235,238,245,0.75)` (top margin 8) · next event 12 semibold. Right col w 190, padding-top 14: month label 10 bold secondary top-right · 7-col MTWTFSS header 9 semibold secondary · 7-col grid gap 3, cells 16pt, today = filled `#F2F3F5` circle with `#171A22` text, weekend opacity 0.4, out-of-month 0.18, in-month 0.85 |
| Expanded · Privacy | 360 x 120 | padding `42 24 16`, gap 10. Rows: 8x8 pulsing dot (`#30D158` camera, `#FF9F0A` mic) · label 13 medium · owning app 11 secondary |
| Expanded · Claude usage | 470 x 196 | padding `42 24 16`, gap 20. 76x76 three-segment donut (r 30, width 10) in white at 0.9 / 0.45 / 0.2 · legend rows: 8x8 rounded-2 swatch · `Input` / `Output` / `Cache` 11 regular `rgba(235,238,245,0.75)` · value 11 medium tabular. Footer row (top margin 4): `Today $12.40` · `Week $41.20` 11 secondary |
| Expanded · Meeting | 380 x 128 | padding `42 24 16`, gap 12. 9x9 pulsing `#FF453A` dot · `Recording meeting` 13 semibold / `Transcribing on-device` 11 secondary · `12:04` 15 semibold · 32x32 circular `rgba(255,255,255,0.09)` stop button with a 10x10 rounded-2 `#FF453A` square |
| Expanded · Duo | 540 x 158 | padding `42 24 16`, gap 20. Left (flex): 36x36 art chip + title 13 semibold / artist 11 secondary; transport row gap 20 — prev 15x12, 32x32 circular play/pause, next 15x12. 1pt full-height `rgba(255,255,255,0.10)` divider. Right col w 190: `FRI 24` 10 bold secondary letter-spacing 0.06em · `Design review` 13 semibold · `2:00 – 2:45 PM · Zoom` 11 secondary |
| Expanded · Mode quick-pick | 480 x 106 | padding `42 22 14`, gap 9. `Dictation mode` 11 semibold secondary. Chips gap 8, padding `5 12`, radius 12 — selected `#F2F3F5` on `#171A22` 12 semibold, rest `rgba(255,255,255,0.09)` 12 medium |
| Camera mirror | 360 x 250 | feed inset `40 12 12 12`, radius 14. Close glyph 11x11 opacity 0.6 at top 38, right 16 |

### Dictation states
| State | W x H | Radius | Layout |
|---|---|---|---|
| Entry sliver | 260 x 54 | 16 | padding `0 20 8`, bottom-aligned. 26-bar waveform, bars 2w radius 1, `currentColor` opacity 0.85, height 14, space-between, edge-faded with a horizontal mask `transparent → opaque 12% → opaque 88% → transparent` |
| Recording | 420 x 128 | 22 | padding `42 22 12`, gap 8. 44-bar waveform, height 24, same mask · transcript 13 medium centred opacity 0.95 · footer row: `Notes` 11 semibold · `·` · app name 11 secondary · spacer · `0:23` 11 medium secondary · `esc` 9 semibold in `rgba(255,255,255,0.09)` rounded-4 padding `3 5` · `Cancel` 11 secondary |
| Transcribing | 400 x 106 | 22 | padding `42 22 12`, gap 8. 4pt shimmer bar radius 2 on `rgba(255,255,255,0.12)` — a 40%-wide white-0.55 gradient sweeping left→right, 1.1s linear infinite · transcript 13 medium centred · `Transcribing…` 11 secondary |
| Completed | 320 x 72 | 20 | padding `0 22 12`, bottom-aligned, gap 10. 17x17 `#30D158` check ring · `Inserted` 13 semibold / transcript 11 secondary truncating (max 230) |
| Error | 320 x 72 | 20 | padding `0 22 12`, bottom-aligned, gap 10. 17x17 `#FF9F0A` warning triangle · `Couldn't transcribe` 13 semibold / reason 11 secondary |

### File Tray (expanded)
420 x 130, radius 24, padding `42 24 12`, gap 8. Header `File Tray` 11 semibold secondary ·
spacer · close glyph. Tiles gap 10: 70pt wide, `rgba(255,255,255,0.06)` rounded-8,
padding `8 6`, gap 4 — 20x24 file glyph `rgba(255,255,255,0.75)` + filename 9 regular
secondary, truncating at 60pt.

## 4. Interaction spec (verbatim from the design)

| | |
|---|---|
| HUD bar | drag to set volume/brightness — knob appears on hover, fill spring 0.35/0.8, haptic tick on release |
| Meeting stop | hold-to-stop 600 ms — ring fills around the button while held; releasing early cancels |
| Clipboard row | click copies; row flashes the green "Copied" check for 900 ms, then fades |
| Tab strip | position dot under the active glyph; hover shows the page label; tap a neighbour to slide by one |
| Number ticks | battery %, timer, counts roll digits (numericText) with the fill spring |
| Check-off | circle → green pop, micro spring 0.18/0.7, strikethrough wipes in 150 ms |
| Reduce Motion | every spring collapses to a 0.18 s ease; pulsing dots hold steady |

## 5. Settings window

### Chrome
880 x 620, radius 12, body `#1B1D24`, 0.5pt `rgba(255,255,255,0.1)` border,
shadow `0 24px 60px rgba(0,0,0,0.35)`, base font 13, foreground `#F2F3F5`.

### Sidebar
Width 212, background `#14161C`, right border `rgba(255,255,255,0.06)`, padding `12 8`.
Traffic lights at top: three 11pt circles gap 7, padding `4 8 12` — `#FF5F57`, `#FEBC2E`, `#28C840`.

Rows: padding `3 8`, radius 6, gap 8, 12 medium, with a 13x13 stroked glyph
(stroke-width 1.7, round caps/joins).
- selected: background `rgba(255,255,255,0.10)`, foreground `#F2F3F5`
- unselected: background transparent, foreground `rgba(235,238,245,0.62)`
- **No colored icon chips.** Selection is the only highlight.

Section headers: 10 semibold uppercase, letter-spacing 0.05em, `rgba(235,238,245,0.5)`,
padding `10 8 3`.

Nav order, exactly:
1. General
2. *(header)* NOTIFICATIONS — Battery, Connectivity, Focus, Display, Sound
3. *(header)* LIVE ACTIVITIES — Now Playing, Calendar, File Tray, Dictation, System Stats, Claude Usage, Timer, Clipboard, Tasks, Privacy, Goals, Meetings
4. *(header)* NOTCHLESS — Permissions, About

### Pane body
`flex: 1`, padding `22 26`, vertical gap 13 (12 for card-stack panes).

Pane header: 34x34 rounded-9 `rgba(255,255,255,0.08)` icon chip with a 16x16 stroked glyph,
gap 11 · title 17 bold · subtitle 12 `rgba(235,238,245,0.55)`.

Section header: 10 semibold uppercase letter-spacing 0.06em `rgba(235,238,245,0.45)`.

Card: `rgba(255,255,255,0.05)`, radius 12, padding `12 14`, vertical gap 9 (10 where noted).
Rows inside a card are separated by a 1pt `rgba(255,255,255,0.07)` divider.

Row: `space-between`, gap 10, label 13 on the left, control on the right.

### Controls
- **Switch** — 34x20, radius 10. ON `#30D158` with a 16pt white knob inset 2 from the right;
  OFF `rgba(255,255,255,0.14)` with a `rgba(255,255,255,0.85)` knob inset 2 from the left.
- **Slider** — 130x4 track radius 2, `rgba(255,255,255,0.14)`; fill `#F2F3F5`; 13pt white
  knob centred on the fill edge; trailing value label 12 `rgba(235,238,245,0.6)` in a
  38pt right-aligned column.
- **Menu picker** — inline chip, padding `4 10`, radius 8, `rgba(255,255,255,0.08)`,
  label 12 `rgba(235,238,245,0.8)`, trailing 8x8 chevron-up-down (stroke-width 2.4).
- **Chip grid picker** — 5-column grid gap 8; chips padding `9 4`, radius 10, centred,
  selected `#F2F3F5` bg with `#171A22` 11 semibold text, unselected `rgba(255,255,255,0.05)`
  with `rgba(235,238,245,0.6)` 11 regular text.
- **Segmented control** — container padding 3, radius 9, `rgba(255,255,255,0.05)`, gap 4,
  self-start; segments padding `4 14`, radius 8; selected `#F2F3F5` bg / `#171A22` 12 semibold,
  unselected `rgba(235,238,245,0.6)` 12 regular.
- **Secondary button** — padding `5 12`, radius 8, `rgba(255,255,255,0.09)`, 12 medium.
- **Primary button** — same metrics, `#F2F3F5` bg, `#171A22` fg, 12 semibold.
- **Destructive button** — `rgba(255,69,58,0.14)` bg, `#FF6961` fg.
- **Text field** — padding `6 10` (or `5 10`), radius 8, `rgba(255,255,255,0.07)`,
  placeholder 12 `rgba(235,238,245,0.4)`.
- **Status dot** — 7pt circle: granted `#30D158`, denied `#FF453A`, not set `rgba(255,255,255,0.3)`.
- **Footnote** — 11, line-height 1.5, `rgba(235,238,245,0.45)`.

### New control — Theme (General pane)
Section `THEME`, card with a `Notch surface tint` row. Five swatches, gap 10, each a
40x26 rounded-8 fill of the tint colour with a 0.5pt `rgba(255,255,255,0.2)` inner border;
the selected one adds a 2pt `#1B1D24` gap ring then a 3.5pt `#F2F3F5` ring. Caption below
each: 10, selected `rgba(235,238,245,0.7)`, unselected `rgba(235,238,245,0.45)`.
Footnote: "Tints the notch surface across every state."

### Pane content (as designed)
- **General** — card: Launch at login (on), Sync settings via iCloud (on), Hide in fullscreen (off), Collapse activities in fullscreen (on), Hide in mission control (on), Hide from screen capture (off), Force simulated notch (off). `IDLE ACTIVITY` — Most Recent (on) + 5-col chip grid: Auto (selected), None, Playing, Calendar, Duo, Battery, Stats, Timer, Tasks, Goals. `THEME` — the tint picker above. `BEHAVIOUR` — Progressive blur (on), Haptic feedback (on).
- **Battery** — `NOTCH`: Show battery activity, Show percentage. `ALERTS`: Low battery at (slider, 20%), Notify when fully charged (off).
- **Sound** — Volume HUD (on). `APPEARANCE`: Show mute as empty, Show percentage label, Show output device (off). `BEHAVIOR`: Hide HUD after (slider 2.0s), Show on external volume change, Position (menu "Top (notch)"), Show on all displays (off), Play a sound on volume change (off). `SYSTEM OSD`: Replace the system volume HUD (on) + footnote.
- **Display** — Brightness HUD (on) + footnote. `BEHAVIOR`: Position (menu). `EXTERNAL DISPLAYS`: Control external displays via BetterDisplay/Lunar (off) + footnote.
- **Now Playing** — `VISUALIZER`: Album art colour glow (off), Live audio visualizer (on) + footnote. `GESTURES`: Swipe to seek (on) + footnote, Show tab bar in expanded view (on). `SOURCE`: Show media from (menu "All apps"). `TRANSPORT`: Show shuffle button (off), Show 15-second skip buttons (off).
- **Connectivity / Focus / Calendar / File Tray / Timer / Privacy** — single-card panes, each its own sidebar destination, each a toggle plus footnote.
- **Dictation** — segmented control: Settings / Modes / History / Style. `GENERAL`: Enable dictation, Hotkey (menu "Right ⌘"), Language (menu), Max recording length (slider 120s). `TRANSCRIPTION ENGINE`: Engine (menu "Parakeet (on-device)") + green check "Model ready". `AI CLEANUP`: Polish transcript (menu "Smart"), Backend (menu "On-device Gemma"), Voice commands, Smart formatting.
- **System Stats + Claude Usage** — stats card: master toggle, CPU, Memory, Network, Update every (slider 2s). `CLAUDE USAGE`: Show Claude usage in the notch, Compact notch shows (menu), Session (5-hour), Usage chart, Chart window (menu "14 days") + footnote.
- **Tasks + Goals** — tasks card: master toggle, "Add a task…" field, task rows (disclosure chevron, label, optional `1/3` count, remove glyph), `Clear all tasks` 11 `#FF6961`. `GOALS`: Enable Goals, Currency (two chips). Goal card: name 13 semibold + red pin glyph + trash glyph · `$3,200 / $10,000 · 32%` 12 secondary · 4pt progress bar · date chips `Jan 1, 2026` → `Dec 31, 2026` + `5 mo left` · `Save $850/mo to finish on time` 11 medium `#FF9F0A` · contribution row: Amount field (80pt) + Label field + `Log` button.
- **Meetings** — segmented: Meetings / Settings. `RECORDING`: Enable meeting capture, Delete audio after processing + footnote. `AI SUMMARY`: Summarize via (menu "Claude subscription") + green-check footnote, Model (menu "Sonnet (balanced)").
- **Permissions + About** — `PERMISSIONS` card rows: name + grey reason suffix · status dot · 60pt status word · trailing button (secondary `Settings`, or primary `Enable` when not set). Rows: Accessibility, Microphone, Speech Recognition, Camera, Audio Recording, Calendar. Footnote below. `ABOUT`: 38x38 rounded-10 `rgba(255,255,255,0.08)` chip containing a 20x7 notch mark · `Notchless` 14 bold / `Version 1.6.0` 11 secondary · tagline footnote · buttons `Run setup again` (secondary) and `Uninstall & delete all data` (destructive).

## 6. Verification

Build with `-skipMacroValidation`. Run the app, capture each notch state and each settings
pane, and compare against the geometry and colours above. Iterate until they match.
