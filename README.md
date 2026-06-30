# YLTool - أداة YallaLite

Theos tweak for YallaLite with account management features.

## Features

- **Name Badges** - Display account names as styled badges
- **Run/Stop Toggle** - تشغيل / إيقاف control
- **Speed Control** - MS delay slider (0.00 - 0.05 seconds)
- **Merge Accounts** - دمج الحسابات with mutual follow
- **Collapsible UI** - Hide/show panel with arrow button

## Requirements

- iOS 13.0+
- jailbroken device
- Theos installed

## Build

```bash
make
make package
```

## Install

```bash
make install
```

Or copy `YLTool.dylib` to `/Library/MobileSubstrate/DynamicLibraries/` and add a plist.

## Customize Hooks

Edit `Tweak.xm` and uncomment the `%hook` blocks at the bottom. Replace with actual YallaLite class/method names found via `class-dump` or `nm`.
