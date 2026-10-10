# RhythmX – README

Welcome to **RhythmX**, an iOS app that helps you track menstrual cycle phases, add freeform tags (like moods, dietary notes, etc.), and archive past cycles for future reference. Our goal is to make cycle tracking simpler and more intuitive-helping you spot patterns and stay in tune with your body.

---

## Overview

- **Generate Cycle Events**  
  Pick a start date and cycle length; the app auto-creates events for the menstrual, follicular, ovulation, and luteal phases.

- **Tag Your Days**  
  Add custom notes (e.g., dietary or exercise) to specific dates for more detailed tracking.

- **Calendar View**  
  An interactive month calendar shows icons for each phase or event. Tap any date to see more details.

- **Archive Past Cycles**  
  Save completed cycles in “archives” so you can review them later, then generate fresh events for upcoming cycles.

---

## Tabs

Insights, Calendar, Tags, Cycles, Settings.

## Privacy

All data stays on your device. No account, no ads, no tracking.

## Tests

Run tests with `xcodebuild test -scheme RhythmX -destination 'platform=iOS Simulator,name=<an installed iOS 18+ simulator>'` (list installed simulators with `xcrun simctl list devices available`).

---

## Requirements

- **iOS 18.0 or newer**  
  The calendar is a custom SwiftUI grid; no UIKit calendar view is required.

- **Swift & SwiftUI**  
  Requires SwiftUI and a current Xcode (one that includes the iOS 18 SDK).

---

## Getting Started

1. **Clone or download** this repository.
2. **Open the project in a current Xcode**.
3. **Run** on an iOS 18+ simulator or device.

On first launch, you’ll see the **Onboarding** screen. Follow the steps to learn how to generate cycle events and add tags, or skip straight to the main interface. Once in the app, use the **Cycles** tab to generate your first cycle and dive into all the features.

### Key Features

- **Cycles**  
  Start a new cycle, read the phase guide, and review past cycles.

- **Tags**  
  Review and edit tags by phase.

- **Calendar Integration**  
  Tap any date to see all events or edit them right away.

- **Archiving**  
  When a cycle ends, archive the events to keep a permanent record, then clear the calendar to start anew.

---

## Contributing

We welcome contributions of all kinds-bug reports, feature enhancements, or documentation improvements. Here’s how you can help:

1. **Fork** this repo and create a feature branch.
2. Make your changes.
3. **Open a Pull Request** describing what you’ve done.
4. We’ll review and merge or suggest changes.

---

## Reporting Issues

Encountered a bug or have a suggestion? Please open an **Issue** in this repository. Include:

- Steps to reproduce the problem (if any)
- iOS version and device model
- Logs or screenshots to help illustrate the issue

We’ll do our best to address it quickly.

---

## License

This project is licensed under the [Apache License, Version 2.0](LICENSE). See the [LICENSE](LICENSE) file for details.
