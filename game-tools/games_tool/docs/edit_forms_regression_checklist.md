# Edit Forms Regression Checklist

Use this checklist after any change touching add/edit forms or the middle edit toolbar.

## Sections to verify

- Media
- Animations
- Animation rigs
- Levels
- Layers
- Zones
- Sprites
- Paths

## Per-section checks

For each section above:

- `Add`: form opens, validates, confirms, and creates exactly one item.
- `Edit (live)`: changing inputs updates the selected item live from the middle toolbar.
- `Delete`: delete confirmation opens correctly and removes only the selected item.
- `Undo/Redo`: undo reverts add/edit/delete; redo reapplies correctly.
- `Copy/Paste`: copy works with current selection and paste creates expected item count.
- `Selection`: selection state after add/edit/delete/undo remains coherent and deterministic.

## Global checks

- Middle edit toolbar shows/hides correctly by section.
- Add flows clear selection where expected.
- Clipboard chip and clear action render and behave correctly.
- No overflow/assertion errors while opening/hiding edit forms.

## Automated baseline run (2026-03-05)

- `flutter analyze`: pass.
- `flutter test`: pass after stabilizing widget smoke harness.
