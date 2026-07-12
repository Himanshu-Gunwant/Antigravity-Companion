# Antigravity Companion - Mobile App

The mobile client for the Antigravity Companion system, built with Flutter.

## Setup Instructions

1. **Prerequisites**: Ensure you have [Flutter](https://flutter.dev/docs/get-started/install) installed and configured on your machine.
2. **Dependencies**: Run the following command to fetch dependencies:
   ```bash
   flutter pub get
   ```

## Build Instructions

### Running Locally
To run the app on a connected device or emulator in debug mode:
```bash
flutter run
```

### Release Build
To build a production APK for Android:
```bash
flutter build apk --release
```

To build a production iOS app (requires macOS and Xcode):
```bash
flutter build ios --release
```

## Release Instructions
Before publishing, ensure all settings point to the production relay server. Update the version number and build number in `pubspec.yaml` prior to cutting a new release.
