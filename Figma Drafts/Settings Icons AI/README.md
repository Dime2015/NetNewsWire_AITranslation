# Settings category icons — AI raster set v1

Generation mode: built-in ChatGPT image generation.

## Shared prompt

Create one polished monochrome iOS settings icon on a truly transparent background. Warm medium gray (#858585), centered, square canvas, no card, no circle container, no shadow, no gradient, no text unless explicitly requested. Use simple geometric construction, controlled optical curves, consistent visual weight, balanced negative space, symmetry where appropriate, and enough spacing to remain clear at 24 pt. The result should feel restrained and editorial, compatible with a Reeder-inspired native iOS interface. Output only the icon.

Category subjects:

- Accounts & Sync: cloud outline with two small circular sync arrows inside.
- Subscriptions & Discovery: solid RSS dot and two arcs.
- Article List: three round bullets paired with three horizontal rows.
- Reader: symmetrical open book with a clear central gutter.
- Appearance & Language: a perfect circle divided vertically into light and dark halves.
- Notifications: compact symmetrical bell with a small centered clapper.
- Support & Diagnostics: crossed wrench and screwdriver with a shared optical center.

Translation uses the existing Figma vector component and is intentionally reduced to a single centered `译` glyph. The generated translation attempt was rejected because it contained a baked-in checkerboard background.

## Processing

Run `python3 crop_icons.py` to crop by alpha bounds, normalize accepted sources to a 256×256 transparent canvas, make 24 px inspection previews, and regenerate the contact sheet.

The Figma settings home uses the 256 px sources as image fills at a 24 pt display size. The wide Accounts & Sync mark receives a 28 pt optical-size correction.
