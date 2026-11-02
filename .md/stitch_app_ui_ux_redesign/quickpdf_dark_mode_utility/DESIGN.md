---
name: QuickPDF Dark Mode Utility
colors:
  surface: '#121316'
  surface-dim: '#121316'
  surface-bright: '#38393c'
  surface-container-lowest: '#0d0e11'
  surface-container-low: '#1b1b1f'
  surface-container: '#1f1f23'
  surface-container-high: '#292a2d'
  surface-container-highest: '#343538'
  on-surface: '#e3e2e6'
  on-surface-variant: '#e4beba'
  inverse-surface: '#e3e2e6'
  inverse-on-surface: '#2f3034'
  outline: '#ab8986'
  outline-variant: '#5b403e'
  surface-tint: '#ffb3ad'
  primary: '#ffb3ad'
  on-primary: '#68000a'
  primary-container: '#ff5451'
  on-primary-container: '#5c0008'
  inverse-primary: '#b91a24'
  secondary: '#ffb4ab'
  on-secondary: '#690005'
  secondary-container: '#bb0112'
  on-secondary-container: '#ffc8c1'
  tertiary: '#69d8d4'
  on-tertiary: '#003736'
  tertiary-container: '#24a09d'
  on-tertiary-container: '#00302e'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#ffdad7'
  primary-fixed-dim: '#ffb3ad'
  on-primary-fixed: '#410004'
  on-primary-fixed-variant: '#930013'
  secondary-fixed: '#ffdad6'
  secondary-fixed-dim: '#ffb4ab'
  on-secondary-fixed: '#410002'
  on-secondary-fixed-variant: '#93000b'
  tertiary-fixed: '#87f4f0'
  tertiary-fixed-dim: '#69d8d4'
  on-tertiary-fixed: '#00201f'
  on-tertiary-fixed-variant: '#00504e'
  background: '#121316'
  on-background: '#e3e2e6'
  surface-variant: '#343538'
typography:
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 26px
    fontWeight: '700'
    lineHeight: 34px
  headline-md:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
  headline-sm:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system delivers a dependable, high-efficiency utility interface tailored for rapid document scanning, OCR extraction, and file management on mobile viewports. Designed around the Safe visual archetype, it prioritizes instant spatial orientation, structural clarity, and high-contrast readability in variable lighting environments.

The visual style blends modern technical utility with purposeful minimalism. Deep charcoal and slate surfaces eliminate eye fatigue, while razor-sharp structural outlines provide tangible page boundaries. Energetic crimson accents act as precise operational beacons—guiding scan triggers, page selection, and export actions without overwhelming dense lists or preview viewports.

## Colors

The palette establishes an ergonomic dark hierarchy built on deep neutral slates paired with vivid crimson functional triggers.

- **Canvas & Surface Tiering:**
  - `Base Canvas`: `#121316` serves as the primary viewport backdrop.
  - `Card / Container Surface`: `#1C1E24` establishes elevated interactive zones, list items, and modal bodies.
  - `Raised / Overlay Surface`: `#262930` provides contrast for popovers, floating sheets, and segmented control wells.
  - `Structural Border`: `#2D3139` delivers hairline edge definition across containers, dividers, and framing boundaries.

- **Functional Accents:**
  - `Primary Action`: `#EF4444` functions as the high-visibility accent for camera triggers, primary buttons, batch export actions, and active indicators.
  - `Active / Pressed State`: `#DC2626` handles tapped states, high-priority destructive actions, and active recording boundaries.

- **Content & Scanning Feedback:**
  - `Primary Content`: `#F9FAFB` for maximum legibility of extracted text, metadata headers, and values.
  - `Secondary Content`: `#9CA3AF` for file sizes, timestamps, and placeholder states.
  - `Success / Processed`: `#10B981` indicates completed OCR processes and cloud sync confirmation.

## Typography

Typography relies entirely on Inter to ensure unmatched clarity, neutral authority, and dependable tabular alignments across scan resolutions, page counts, and metadata fields.

All typography scales are tuned for quick handheld scanning:
- Headings maintain a tight vertical cadence with negative tracking on larger display instances to keep titles compact.
- Body sizes are optimized for high-contrast viewing of captured OCR snippets and folder breadcrumbs against dark slate surfaces.
- Labels emphasize medium-to-semibold weights with neutral tracking to support rapid tool recognition within bottom utility bars and badge chips.

## Elevation & Depth

Visual hierarchy does not rely on heavy, diffused shadows; instead, it utilizes a combination of distinct tonal surface layers and crisp low-contrast hairline borders.

- **Level 0 (Base Canvas):** Background tone `#121316`. Used for root app layouts, viewports behind document viewfinders, and outer screen gutters.
- **Level 1 (Card & List Surface):** Tone `#1C1E24` framed with a 1px border of `#2D3139`. Used for document tiles, file metadata strips, and inline form modules.
- **Level 2 (Floating Sheets & Controls):** Tone `#262930` paired with a 1px border of `#2D3139` and a discrete downward ambient shadow (`box-shadow: 0 4px 12px rgba(0, 0, 0, 0.45)`). Used for contextual filter pills, batch action bottom bars, and floating capture controls.
- **Level 3 (Modal Dialogs & Overlays):** Tone `#262930` centered over a 75% black dimming scrim (`rgba(10, 11, 13, 0.75)`), enclosed by a 1px border of `#2D3139`.

## Shapes

The design system implements a roundedness level of `2`, creating a balanced, approachable, yet functional software silhouette.

- **Standard Elements (0.5rem / 8px):** Form inputs, buttons, document list rows, chip elements, and segmented control containers.
- **Medium Panels (`rounded-lg`, 1rem / 16px):** Document thumbnail cards, modal sheets, OCR text preview blocks, and floating action toolbars.
- **Large Panels (`rounded-xl`, 1.5rem / 24px):** Bottom utility sheets, camera capture viewports, and primary dialog trays.
- **Full Circular Radius:** Shutter trigger buttons, circular page selection tags, and badge counters.

## Components

- **Buttons:**
  - *Primary Utility*: Filled with `#EF4444`, label text `#F9FAFB` in `label-lg`, height 48px, radius 8px (`0.5rem`). Active state drops to `#DC2626`.
  - *Secondary / Utility*: Filled with `#262930`, border 1px solid `#2D3139`, text `#F9FAFB`. Pressed state brightens background to `#2D3139`.
  - *Capture Shutter*: Outer ring 72px diameter, 3px border `#EF4444` with a 4px inset gap; inner button 56px solid `#EF4444`.

- **Chips & Filter Pills:**
  - Height 32px, radius 8px, background `#1C1E24`, border 1px solid `#2D3139`.
  - Selected state: Background `rgba(239, 68, 68, 0.15)`, border `#EF4444`, text `#EF4444`.

- **Document Lists & Cards:**
  - *Grid Card*: Container `#1C1E24`, border 1px solid `#2D3139`, radius 16px. Aspect ratio 3:4 preview area capped with a metadata bar at the bottom containing file title and timestamp.
  - *List Row*: Full-width strip `#1C1E24`, 1px border `#2D3139`, 56px height, radius 8px with thumbnail inset left and quick-action menu right.

- **Checkboxes & Multi-Select:**
  - 20px x 20px with radius 4px. Unchecked: 1.5px border `#2D3139`, transparent fill. Checked: solid `#EF4444` background with white glyph checkmark.

- **Input Fields & Search:**
  - Height 44px, background `#1C1E24`, border 1px solid `#2D3139`, radius 8px. Text `#F9FAFB` using `body-md`. Focus state displays an active 1px border of `#EF4444`.

- **Document Edge Viewfinder HUD:**
  - Translucent corner brackets `#EF4444` with edge thickness 3px highlighting document edges over active camera feed.