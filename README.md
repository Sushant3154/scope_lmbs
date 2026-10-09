# scope_lmbs

SCOPE_LMBS_FINAL

Laser Marking / Beam Scope calibration project, containing:

- `android_app/` — Flutter Android application (calibration canvas, main app)
- `main.py`, `simulator.py`, `video_pipeline.py`, `calibration.py` — Python desktop pipeline
- `AIT_LMBS.apk` — prebuilt Android release
- `User_Manual.pdf` — user documentation

## Python side

```bash
pip install -r requirements.txt
python main.py
```

A Windows executable can be built with `build_exe.bat`.

## Flutter side

```bash
cd android_app
flutter pub get
flutter run
```

A few resources if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)
