# 360° Calibration System - Flutter Android App

This is a responsive, touch-friendly Flutter mobile and tablet application that replicates the full feature set of the desktop PySide6 app.

## Features

1. **Responsive Viewport Layouts**:
   - **Tablets/Landscape**: Displays a professional side-by-side layout (viewing canvas on the left, controls sidebar on the right).
   - **Phones/Portrait**: Adapts to a vertical stacked layout to maximize stream screen area and keep touch control sliders and logs easily accessible.
2. **Built-in Rotating Floor Simulator**: Full offline virtual simulation mirroring the coordinate calibration grid and features.
3. **Low-Latency Live RTSP Feed**: Uses VLC player backend for smooth, hardware-accelerated video decoding.
4. **Draggable Calibration Canvas**: Drag coordinates, tap to place markers, and scroll to yaw-rotate the view.

---

## Codebase Directory Structure

All application source code is contained within the following files:
* [pubspec.yaml](pubspec.yaml) - Declarations for app metadata, assets, and dependency libraries (`flutter_vlc_player`).
* [lib/main.dart](lib/main.dart) - Application initialization, theme configurations, responsive layouts, sidebar controls, and video stream connection management.
* [lib/calibration_canvas.dart](lib/calibration_canvas.dart) - Custom painted interactive viewport that maps screen coordinates to world coordinates.
* [lib/calibration_system.dart](lib/calibration_system.dart) - Calibration calculation algorithms ported from Python to Dart.
* [lib/rotating_floor_simulator.dart](lib/rotating_floor_simulator.dart) - Mathematical model projecting rotational reference features.
* [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml) - Manifest with necessary internet permissions declared.

---

## Setup & Running Guide

### 1. Prerequisite Installations

To run, compile, or debug the Flutter app, ensure you have the following installed on your machine:
* **Flutter SDK**: [Download & install instructions](https://docs.flutter.dev/get-started/install)
* **Android Studio**: Install Android Studio and set up the **Android SDK**, **Android NDK**, and an **Android Virtual Device (AVD)** emulator (or connect a physical Android device).

### 2. Project Setup

Open your terminal, navigate to the `android_app` directory, and run the following command to download all dependencies:

```bash
flutter pub get
```

### 3. Running the App

To run the application in development mode:

1. Launch your Android Emulator (e.g. tablet device simulation) or connect a physical Android tablet/phone via USB Debugging.
2. Verify that Flutter detects your device:
   ```bash
   flutter devices
   ```
3. Run the application:
   ```bash
   flutter run
   ```

### 4. Compiling the Standalone Android App (APK)

To compile a final release bundle (`.apk`) that can be installed directly on any Android tablet/phone:

```bash
flutter build apk --release
```

The compiled installer will be saved at:
`build/app/outputs/flutter-apk/app-release.apk`
