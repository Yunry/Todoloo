# Todoloo

A native macOS task app built with SwiftUI and SwiftData. Requires macOS 14 or newer.

## Run

Open `Todoloo.xcodeproj` in Xcode, select the **Todoloo** scheme, and run. No dependencies or account required. Tasks save locally on this Mac; cloud sync is not included.

The interface follows macOS light/dark appearance. Today includes overdue, unfinished tasks. Upcoming starts tomorrow. Completed tasks stay available in Completed and their original list. New tasks inherit the current view: Today, tomorrow for Upcoming, Work for Work, and a priority flag for Important. New tasks in All tasks and Personal are unscheduled.

- **⌘N**: focus quick entry (switches to Today when viewing Completed)
- **Return**: add a task
- **⌘F**: search titles and notes in the current view
- **⌥⌘I**: toggle task details
- **⌘Z / ⇧⌘Z**: standard undo / redo
- Click a task title to edit details; right-click for scheduling, list, and deletion actions.
- The selected sort order is remembered between launches. Completed sections can be collapsed in every view; long lists create rows as they come into view.
- Add an optional estimate in task details (15, 30, or 60 minute shortcuts, or a custom 1–1,440 minutes). You can also type `Read a chapter (30mins)` or `Write a draft (1h 30m)` when adding a task. The duration is saved separately and appears beside its date; switch off **Estimated time** to remove it.
- Enable **Start time** to choose a 24-hour time in 15-minute steps, from 00:00 through 23:45. Quick entry also accepts `Study (21:15) (30mins)` in either order. A start time without a date uses today (tomorrow when adding in Upcoming). Sorting by due date includes start times.
- Timed tasks default to a macOS reminder 15 minutes before the start. Allow notifications when prompted; banners and sounds follow System Settings and Focus. Pending reminders update when you edit the title, date, or time, and cancel when you complete/delete the task or turn the reminder off. Native notifications can arrive while the app is closed. If the reminder time has passed, the app explains why it cannot schedule it. **Test reminder** lets you check notification delivery.
- Times use the Mac’s local time zone when scheduled. Reopen Todoloo after changing time zones to update pending reminders if the app was closed. Nonexistent times during the spring daylight-saving change must be changed; repeated autumn start times use the first occurrence. Notification triggers use absolute times to preserve the 15-minute lead through clock changes. A 00:00 start reminds you at 23:45 the previous day.

## Build and test

```sh
xcodebuild -project Todoloo.xcodeproj -scheme Todoloo -configuration Debug -derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGN_ENTITLEMENTS= build
xcodebuild -project Todoloo.xcodeproj -scheme Todoloo -configuration Debug -derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGN_ENTITLEMENTS= test
```

These local development commands ad-hoc sign the app so macOS can identify it for notifications, and retain the existing unsandboxed development data location. Distribution builds should use your Apple signing configuration and the project’s sandbox entitlements.

The test suite covers date boundaries, overdue/completion rules, list membership, sorting, persistence across store reopen, undoing deletion, duration/time parsing, reminder lead time, midnight, daylight-saving behavior, rescheduling, and reminder opt-out.

The application loads its bundled icon explicitly at launch to refresh stale Dock tiles from earlier development builds. The everyday app can be installed at `~/Applications/Todoloo.app` and kept in the Dock; after rebuilding, update that copy to use the newest version.

For a temporary in-memory demo, quit existing instances first, then run:

```sh
open DerivedData/Build/Products/Debug/Todoloo.app --args --demo
```

Demo tasks are never written to the persistent task store and do not schedule system notifications. Quit and launch normally to return to your own tasks.

`project.yml` is the XcodeGen source (`xcodegen generate`). The checked-in Xcode project works without XcodeGen. `scripts/GenerateAppIcon.swift` regenerates the app icon using AppKit vector drawing.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
