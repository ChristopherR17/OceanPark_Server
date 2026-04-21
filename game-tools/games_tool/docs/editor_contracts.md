# Editor Contracts

This document defines the non-negotiable contracts for editor mutations.

## C1. Single Source of Truth
- Runtime editor data must live in `AppData.gameData`.
- UI widgets must not keep authoritative copies of project data.
- Derived UI state is allowed, but persisted state changes must flow through `AppData`.

## C2. Canonical Mutation Path
- Persisted mutations must use `AppData.runProjectMutation`.
- `runProjectMutation` provides:
  - optional validation gate,
  - undo checkpoint,
  - UI refresh,
  - autosave.

## C3. Undo and Autosave
- Persisted data changes must be undoable by default.
- Persisted data changes must be autosaved by default.
- UI-only selection changes are excluded from this rule.

## C4. Validation Before Persist
- Validation must run before mutating data when constraints exist.
- Validation failures should provide a user-visible status message.

## C5. Standard Form Behavior
- Add and Edit forms should share consistent lifecycle:
  - open with project-backed values,
  - validate consistently,
  - mutate through the canonical path.

## C6. Autosave Reliability
- Persisted edits should enqueue autosave writes, not fire immediate writes per field change.
- Autosave writes should be coalesced and serialized through one queue.
- Navigation and explicit close actions should flush pending autosave writes.
- Autosave failures should surface as non-blocking UI feedback and retry automatically.

## C7. Undo/Redo Granularity
- Live edit mutations should use grouped undo checkpoints.
- Rapid changes in the same edit session should collapse into a single checkpoint window.
- Major operations (delete, reorder, explicit type apply/update) should remain ungrouped and create distinct checkpoints.

## Adoption Status
- Implemented in this iteration:
  - Zones section persisted mutations.
  - Media section persisted mutations.
  - Autosave queue with coalescing, flush, and retry in `AppData`.
  - Inline autosave warning message in top bar.
  - Grouped undo checkpoints for live edit sessions.
- Pending migration:
  - Full consolidation of all remaining direct mutations through one canonical pathway.
