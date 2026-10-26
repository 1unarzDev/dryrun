# DryRun

DryRun is a native iPhone app that helps families prepare for emergencies and practice using their own household information and home layout.

- Prepare for home fires, tornadoes, flash floods, freezing weather, extreme heat, and water outages.
- Record family members, assistance needs, medications, equipment, contacts, and supplies.
- Create a home manually or scan with RoomPlan on a supported LiDAR device.
- Find nearby resources and plan meeting places with maps.
- Build a shopping list from supply gaps and track preparation and practice evidence.
- Use Beacon for optional personalized AI assistance.
- Keep family cards and plans locally, export PDFs, and use English, Spanish, or Vietnamese.

## Build

The iOS app requires macOS, Xcode, and XcodeGen:

```sh
cd apps/ios
xcodegen
open DryRun.xcodeproj
```

Shared Swift code lives in `packages/`. Backend services live in `services/`. Provider keys belong on the server, never in the app.
