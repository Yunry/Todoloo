# Todoloo

A native macOS task app built with SwiftUI and SwiftData. Requires macOS 14 or newer.

## Run

Open `Todoloo.xcodeproj` in Xcode, select the **Todoloo** scheme, and run. No dependencies or account required. Tasks save locally on this Mac; cloud sync is not included.

The interface follows macOS light/dark appearance. Today includes overdue, unfinished tasks. Upcoming starts tomorrow. Completed tasks stay available in Completed and their original list. New tasks inherit the current view: Today, tomorrow for Upcoming, the selected list for Personal, Work, and custom lists, and a priority flag for Important. New tasks in All tasks and list views are unscheduled.

- **⌘N**: focus quick entry (switches to Today when viewing Completed)
- **Return**: add a task
- **⇧⌘N**: create a custom list
- **⌘F**: search titles, notes, and checklist steps in the current view
- **⌥⌘I**: toggle task details
- **⌘Z / ⇧⌘Z**: standard undo / redo
- Click a task title to edit details; right-click for scheduling, list, and deletion actions.
- The selected sort order is remembered between launches. Completed sections can be collapsed in every view; long lists create rows as they come into view.
- Today offers **Day plan** and **List** layouts and remembers your choice. Day plan groups catch-up tasks, a chronological schedule, and flexible tasks. Its workload summary totals estimates for unfinished tasks due today and identifies missing estimates.
- Timed tasks with estimates show their planned finish time (including a next-day marker when needed). Overlap warnings appear in the day plan and task details; consecutive tasks are allowed. Warnings consider unfinished tasks across dates, including plans that cross midnight. Estimates represent elapsed minutes through daylight-saving changes.
- **Calendar** in the sidebar provides Day and Week views for unfinished tasks, with a full 24-hour grid and 15-minute divisions. Week starts follow the Mac’s calendar preferences. Use Today, previous/next, or the date field to navigate; click a day heading to open that day.
- Drag a task to a calendar slot to change its date and start time, snapped to the nearest 15 minutes. The estimate, notes, list, priority, and reminder preference stay intact; reminders reconcile automatically. **⌘Z** undoes a move. Right-click **Reschedule…** offers the same scheduling controls without dragging.
- Dragging moves the event block directly inside the calendar and preserves the point where you grabbed it. A live start/end time label follows the block as it snaps to 15-minute slots across days. Hold near the top or bottom of the grid to scroll. The original slot remains faint until release. Escape or releasing outside a valid target cancels without changing tasks or reminders; the flexible tray removes only the start time. Scrolling and settling respect macOS Reduce Motion.
- Drag a flexible task onto the calendar to give it a time, or drop a calendar task onto **Flexible tasks** to remove its start time and reminder while keeping its date and estimate. The tray includes all unfinished tasks without a valid start time, including tasks outside the displayed week.
- Double-click an empty calendar slot, use **+**, or press **⌘N** in Calendar to add a task. **⌘F** searches calendar titles and notes. Overlapping blocks use separate lanes, and overnight tasks continue into the next day. Tasks without estimates use a 30-minute display placeholder without saving an invented estimate. Clock changes still use the first occurrence of a repeated time; nonexistent times cannot be scheduled.
- Add an optional estimate in task details (15, 30, or 60 minute shortcuts, or a custom 1–1,440 minutes). You can also type `Read a chapter (30mins)` or `Write a draft (1h 30m)` when adding a task. The duration is saved separately and appears beside its date; switch off **Estimated time** to remove it.
- Enable **Start time** to choose a 24-hour time in 15-minute steps, from 00:00 through 23:45. Quick entry also accepts `Study (21:15) (30mins)` in either order. A start time without a date uses today (tomorrow when adding in Upcoming). Sorting by due date includes start times.
- Timed tasks default to a macOS reminder 15 minutes before the start. Allow notifications when prompted; banners and sounds follow System Settings and Focus. Pending reminders update when you edit the title, date, or time, and cancel when you complete/delete the task or turn the reminder off. Native notifications can arrive while the app is closed. If the reminder time has passed, the app explains why it cannot schedule it. **Test reminder** lets you check notification delivery.
- Times use the Mac’s local time zone when scheduled. Reopen Todoloo after changing time zones to update pending reminders if the app was closed. Nonexistent times during the spring daylight-saving change must be changed; repeated autumn start times use the first occurrence. Notification triggers use absolute times to preserve the 15-minute lead through clock changes. A 00:00 start reminds you at 23:45 the previous day.

## Latest polish

- Task details now include a lightweight **Checklist**: add, edit, complete, and remove steps. List rows show step progress; larger calendar blocks do too. Checklists stay attached when rescheduling and save locally with undo support. Completing a task preserves its checklist so reopening it restores the same steps.
- Quick entry accepts `Read tomorrow (09:15) (30mins)` or `Read (today) (30mins) (09:15)`. The relative date, quarter-hour time, and estimate can appear in any trailing order. A preview shows exactly what will be saved. Unsupported tokens remain part of the title. Date words are English; times stay in the existing explicit `(HH:mm)` format.
- Calendar drag previews turn amber and name overlapping tasks in the footer. Conflicts include unfinished plans across midnight, including the 30-minute placeholder used when no estimate is set. Conflicts are advisory; you can intentionally overlap tasks.
- **Now** jumps to the current day and time. Undo/redo and deletion clear outdated move messages. Calendar edge scrolling uses the visible grid bounds; additional list animations respect Reduce Motion. Estimated finish times consistently use the 24-hour clock.

## Product direction

Research checked on 10 November 2026. These are common product patterns, with selection based on Todoloo's simple local macOS workflow:

- [Things](https://culturedcode.com/things/features/) emphasizes quick capture, checklists, clear Today/Upcoming views, and details that stay tucked away. Todoloo now covers these foundations, with a smaller checklist inside each task rather than a project hierarchy.
- [Todoist](https://www.todoist.com/help/todoist/features/set-a-task-duration-L1kYkZv8d) supports duration estimates, natural-language capture, and calendar time blocking. Todoloo already offers estimates and dragging; transparent date/time previews extend capture without introducing a full language parser.
- [Apple Reminders](https://support.apple.com/en-ie/guide/reminders/remn32a9622b/mac) supports subtasks to break complex tasks into manageable steps. Todoloo's checklists serve that purpose without adding separate calendar blocks for each step.
- [TickTick](https://ticktick.com/features?language=en_US) combines reminders, calendars, recurring tasks, and focus tools. Repeating tasks are now available through Gentle routines. Cloud sync, external calendars, global quick capture, tags, and richer projects remain outside this local app's current scope.

## Custom lists

Use **+** beside **MY LISTS**, **File → New List**, or **⇧⌘N** to create a list. Empty lists persist, and new tasks inherit the list you are viewing. All saved lists are available in the task details **List** picker and task context menus under **Move to**. The sidebar scrolls to accommodate longer collections of lists.

Choose from 24 native icons when creating a custom list, or right-click it and choose **Edit list…** to change its name and icon. Icons appear in the sidebar, list header, task rows, and list assignment menus. Icon changes save locally and support ⌘Z. Right-click a custom list to edit or remove it. Renaming updates all tasks in the list, including completed tasks, without changing schedules or reminders. Removing a list moves its tasks to Personal; it never deletes those tasks. List creation, renaming, and removal support ⌘Z. Personal and Work remain as default lists. Names are trimmed, limited to 60 characters, and checked for duplicates without regard to case or accents. List names save locally alongside tasks, including after restarting the app. The task and list metadata stores use separate schema configurations to preserve the existing task database during upgrades.

## Planning tools

- **Find a fit** is in task details and task context menus (including flexible calendar tasks). Choose a starting date, working hours, and duration; select a free slot to preview it, then choose **Schedule task**. Suggestions search seven days, in 15-minute steps, among unfinished Todoloo tasks. Existing estimates reserve their full duration; tasks without estimates reserve the calendar's 30-minute placeholder. The task being moved and completed tasks are ignored. Working hours are remembered. Suggestions do not include events from external calendars. Scheduling saves the chosen duration and supports ⌘Z.
- **Running late** is the clock-arrow button beside calendar navigation. Choose a day and 15, 30, or 60 minutes; tick the tasks to shift and review every old → new start before applying. Mark **Fixed time** in task details or **Keep time fixed** in the calendar context menu to protect a task from this bulk shift. Fixed tasks can still be moved manually. Overlap warnings use the entire resulting schedule, including protected tasks and tasks crossing midnight. The change updates reminders and is one undo group. Ambiguous repeated-hour destinations are rejected rather than silently changing their meaning.
- **Gentle routines** use the **Repeat** picker in task details: daily, weekdays, weekly, one day after completion, or one week after completion. Completing an occurrence advances the same task; **Skip once** advances it without increasing the completion count. Checklist completion resets for the next occurrence while notes, estimate, list, priority, reminder preference, and fixed-time protection stay. There is only one active occurrence; missed dates do not create duplicate overdue tasks. Weekly repeats follow the current planned weekday. Calendar repeats skip missed dates; completion-relative repeats count local calendar days from completion. Nonexistent start times during spring clock changes skip to the next valid occurrence. Undo restores the previous occurrence. Completed occurrences are counted in details rather than saved as separate tasks in Completed; only the next occurrence appears on the calendar and receives its reminder. Turn Repeat to Never to return to an ordinary task.

## Build and test

```sh
xcodebuild -project Todoloo.xcodeproj -scheme Todoloo -configuration Debug -derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGN_ENTITLEMENTS= build
xcodebuild -project Todoloo.xcodeproj -scheme Todoloo -configuration Debug -derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGN_ENTITLEMENTS= test
```

These local development commands ad-hoc sign the app so macOS can identify it for notifications, and retain the existing unsandboxed development data location. Distribution builds should use your Apple signing configuration and the project’s sandbox entitlements.

The test suite also covers free-slot searches, working hours, placeholder and overnight occupancy, protected bulk shifts, final-schedule conflicts, midnight reminder updates, atomic undo, routine completion and skipping, recurrence through daylight-saving changes, and persistence of new settings. It covers date boundaries, overdue/completion rules, list membership, sorting, persistence across store reopen, undoing deletion, duration/time parsing, reminder lead time, midnight, daylight-saving behavior, rescheduling, reminder opt-out, local calendar weeks, quarter-hour drop snapping, overlapping block layout, and undo/redo of a calendar move. Test-host windows use an in-memory store.

The application loads its bundled icon explicitly at launch to refresh stale Dock tiles from earlier development builds. The everyday app can be installed at `~/Applications/Todoloo.app` and kept in the Dock; after rebuilding, update that copy to use the newest version.

For a temporary in-memory demo, quit existing instances first, then run:

```sh
open DerivedData/Build/Products/Debug/Todoloo.app --args --demo
```

Demo tasks are never written to the persistent task store and do not schedule system notifications. Quit and launch normally to return to your own tasks.

`project.yml` is the XcodeGen source (`xcodegen generate`). The checked-in Xcode project works without XcodeGen. `scripts/GenerateAppIcon.swift` regenerates the app icon using AppKit vector drawing.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
