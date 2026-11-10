# Changelog

## 0.3.0 — 2026-11-10

- Add persistent custom lists with 24 native icons, list editing, task assignment, and a New List shortcut (⇧⌘N). Removing a list keeps its tasks in Personal.
- Add Find a fit: preview free slots over seven days using task durations and chosen working hours.
- Add Running late: preview shifts of 15, 30, or 60 minutes, protect fixed-time tasks, warn about conflicts, and undo the whole shift.
- Add gentle routines: daily, weekday, weekly, and completion-relative repeats, Skip once, completion counts, and checklist resets. Keep a single active occurrence instead of creating an overdue backlog.
- Add editable checklists, progress indicators, and search within checklist steps.
- Add quick-entry previews and support for trailing today/tomorrow date words alongside existing time and duration tokens.
- Fix calendar drag destinations, preserve the grab point, improve scrolling and conflict feedback, and clean up task-card corners and selection borders.
- Add a Now button, consistent 24-hour finish times, and improved Reduce Motion support.
- Correct native undo routing for model changes and list-editor dialogs. Keep reminders synchronized with rescheduling and routine advancement.
- Preserve existing task data when adding list metadata storage, with regression coverage for repeated store reopening.

Validation: 49 automated tests pass on Apple Silicon. The release app is a universal Apple Silicon/Intel build and requires macOS 14 or newer.
