# RhythmX

A private menstrual cycle tracker for iPhone. Log your cycle, tag how you feel, and see your patterns. Everything stays on your device.

**No account. No ads. No tracking. No network access other than Apple's in-app purchase system.**

![iOS 18+](https://img.shields.io/badge/iOS-18%2B-5E264F) ![SwiftUI](https://img.shields.io/badge/SwiftUI-Swift%205-E8A5B8) ![License](https://img.shields.io/badge/license-Apache%202.0-lightgrey)

---

## Features

- **Modes**: switch between Cycle, Planning and Menopause from the top of Insights with one tap. Your history is shared across all three; only the presentation changes. Settings has a default mode on launch.
  - **Planning** shows the fertile window, the likely ovulation day, a basal temperature chart, ovulation test results and a two-week-wait countdown.
  - **Menopause** hides period predictions and shows weekly hot flash, night sweat, sleep and mood counts, and a count toward 12 months without a period.
- **Insights**: a phase ring with today's moon, average cycle and period length, next-period estimate, and charts for phase timing, tags and cervical mucus.
- **Calendar**: a month grid tinted by phase, with a Today card, predicted period days, and a day panel to add or review tags.
- **Tags**: log symptoms, moods and notes by phase, with separate tag categories for Planning and Menopause. Repeatable tags such as Hot Flashes count each time you log them.
- **Tag Patterns**: a tag-by-phase heatmap, a detail screen per tag, and plain-language findings computed on the device. On iOS 26 devices with Apple Intelligence on, an optional summary card is written by the on-device model from those findings only.
- **Cycles**: start a new cycle from a first day and length, and read the Phase Guide.
- **Past Cycles**: archive finished cycles in any mode, filter by mode, search them, edit their tags, and swipe to delete one.
- **Notifications**: optional local reminders for your next period, the fertile window and likely ovulation day, daily and weekly check-ins, and tag reminders. All live in Settings and are off until you turn them on.
- **Backup and restore**: save a `.rhythmx` backup file to Files, with an optional passphrase (AES-256-GCM). Restore with a preview, then Replace or Merge. A copy of your data from before the 2.0 update is kept on the device until you delete it.
- **Apple Health**: optional, per type. Write period days as menstrual flow; read basal body temperature and sleep.
- **Share**: export selected phases as a calendar (`.ics`) file, only when you choose to.
- **Themes**: Blush in light and Plum in dark, with a moon for each phase: new, crescent, full, waning. The four phase colors are the same in every theme.
- **Widgets**: a phase widget for the Home Screen in small, medium and large sizes.
- **Accessibility**: Dynamic Type up to accessibility sizes, VoiceOver labels, Reduce Motion support.

### RhythmX Plus

An optional subscription ($1.99 per month, or $9.99 per year with a 3-day free trial). Everything above stays free.

- **PDFs**: a printable monthly calendar and a one-page Doctor Report, as often as you like. Previews are free. Without Plus, a $0.99 Day Pass unlocks both PDFs until the end of that day.
- **Themes**: Blue Moon, Harvest Moon and Eclipse, each with a light and dark variant.
- **Widgets**: Week Strip, and Quick Log to log a tag without opening the app.
- **Apple Calendar sync**: one way, into a calendar named RhythmX. Period days, predicted period, fertile window and phase starts, with optional discreet titles. Turning sync off removes the events the app created.

If Plus ends, the Plus features switch off and all of your data stays.

## Privacy

- Data lives on the device, in `UserDefaults` and the app's own files, and never leaves the phone unless you share an export or a backup file.
- The only network use is Apple's StoreKit, for purchases and restoring them. RhythmX has no server and no account.
- No third-party SDKs, analytics, ads or tracking.
- Apple Health data is read and written on the device only, and only for the types you turn on.
- Apple Calendar sync writes to a calendar named RhythmX on the device; iCloud may carry it to your other devices if you use iCloud Calendar. It asks for full calendar access because write-only access cannot create a calendar or update or remove events it added. Every read and write is limited to the RhythmX calendar; no other calendar is read or changed.
- The on-device summary in Tag Patterns runs on Apple's on-device model, with no network.
- Ships with a privacy manifest (`PrivacyInfo.xcprivacy`) and is intended for the App Store "Data Not Collected" label.

## Requirements

- iOS 18.0 or newer, iPhone
- Xcode with the iOS 18 SDK or newer (the on-device summary needs the iOS 26 SDK and an iOS 26 device)
- Swift 5, SwiftUI, Swift Charts, StoreKit 2, WidgetKit, App Intents, HealthKit, EventKit

## Build and run

1. Clone this repository.
2. Open `RhythmX.xcodeproj` in Xcode.
3. Select the `RhythmX` scheme and run on an iOS 18+ simulator or device. The scheme uses `RhythmX/Purchases/RhythmX.storekit` for local purchase testing.

First launch shows a three-page onboarding. The last page sets your first cycle and generates its events. You can skip it and start from the **Cycles** tab instead.

## Tests

```sh
xcodebuild test -scheme RhythmX \
  -destination 'platform=iOS Simulator,name=<an installed iOS 18+ simulator>'
```

List installed simulators with `xcrun simctl list devices available`.

## Project layout

```
RhythmX/
  Models/        EventStore, ArchivedDataStore, TrackingMode, TagCategory, persistence
  Services/      CycleGenerator, TagParser, CalendarMonthModel, PhaseGuideContent,
                 NotificationScheduler, HealthSync, CalendarSync
  Services/Backup/    backup file format, encryption, restore, saved copies
  Services/Insights/  PatternFinder, on-device summary, Planning and Menopause insights
  Services/PDF/       calendar and Doctor Report PDFs
  Purchases/     PurchaseStore, Entitlement, StoreKit configuration
  Intents/       App Intents for the Quick Log widget
  Views/         Insights, Calendar, Tags, Cycles, Settings, Onboarding, Paywall
  Views/Components/  MoonPhaseView, WaveBackground, PhaseRingView, PhaseStrip, CardStyle
  DesignSystem.swift  colors, themes, spacing, shared styles
RhythmXWidget/   phase, Week Strip and Quick Log widgets
RhythmXTests/    unit tests
```

## Contributing

Bug reports, ideas and pull requests are welcome.

1. Fork the repo and create a feature branch.
2. Make your change and run the tests.
3. Open a pull request describing what changed and why.

## Reporting issues

Open an issue with the steps to reproduce, your iOS version and device model, and a screenshot if it helps.

## Disclaimer

RhythmX is a tracking tool, not medical advice. Predictions are estimates and are not birth control. Talk to a healthcare professional about health concerns.

## License

Licensed under the [Apache License 2.0](LICENSE).
