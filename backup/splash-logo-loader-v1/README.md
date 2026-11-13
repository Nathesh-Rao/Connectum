# Splash backup: LogoLoader splash v1

Snapshot of the splash that plays the LogoLoader animation, plus the native splash assets, taken before the LogoIntro splash work. Originals were left untouched. `.dart.bak` files are ignored by the analyzer and tests.

## Files (backup path, relative to this folder -> original path, relative to repo root)

- `android/app/src/main/res/drawable-hdpi/splash_logo.png` -> `android/app/src/main/res/drawable-hdpi/splash_logo.png`
- `android/app/src/main/res/drawable-mdpi/splash_logo.png` -> `android/app/src/main/res/drawable-mdpi/splash_logo.png`
- `android/app/src/main/res/drawable-v21/launch_background.xml` -> `android/app/src/main/res/drawable-v21/launch_background.xml`
- `android/app/src/main/res/drawable-xhdpi/splash_logo.png` -> `android/app/src/main/res/drawable-xhdpi/splash_logo.png`
- `android/app/src/main/res/drawable-xxhdpi/splash_logo.png` -> `android/app/src/main/res/drawable-xxhdpi/splash_logo.png`
- `android/app/src/main/res/drawable-xxxhdpi/splash_logo.png` -> `android/app/src/main/res/drawable-xxxhdpi/splash_logo.png`
- `android/app/src/main/res/drawable/launch_background.xml` -> `android/app/src/main/res/drawable/launch_background.xml`
- `android/app/src/main/res/values-v31/styles.xml` -> `android/app/src/main/res/values-v31/styles.xml`
- `android/app/src/main/res/values/splash_colors.xml` -> `android/app/src/main/res/values/splash_colors.xml`
- `android/app/src/main/res/values/styles.xml` -> `android/app/src/main/res/values/styles.xml`
- `design/brand/connectum_logo_blue.svg` -> `design/brand/connectum_logo_blue.svg`
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json` -> `ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json`
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png` -> `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png`
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png` -> `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png`
- `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png` -> `ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png`
- `ios/Runner/Base.lproj/LaunchScreen.storyboard` -> `ios/Runner/Base.lproj/LaunchScreen.storyboard`
- `lib/core/widgets/logo_loader/logo_data.dart.bak` -> `lib/core/widgets/logo_loader/logo_data.dart`
- `lib/core/widgets/logo_loader/logo_loader.dart.bak` -> `lib/core/widgets/logo_loader/logo_loader.dart`
- `lib/features/splash/splash_binding.dart.bak` -> `lib/features/splash/splash_binding.dart`
- `lib/features/splash/splash_controller.dart.bak` -> `lib/features/splash/splash_controller.dart`
- `lib/features/splash/splash_view.dart.bak` -> `lib/features/splash/splash_view.dart`
- `test/core/logo_loader_controller_test.dart.bak` -> `test/core/logo_loader_controller_test.dart`
- `test/splash/splash_controller_test.dart.bak` -> `test/splash/splash_controller_test.dart`
- `tool/logo/recolor_logo_data.py` -> `tool/logo/recolor_logo_data.py`

`lib/core/widgets/logo_loader/` also stays in `lib/` (the LogoIntro work does not remove it). `tool/logo/` and `design/brand/connectum_logo_blue.svg` are only copied; later work may add files next to them.

The Android 12+ splash had no dedicated icon (`values-v31/styles.xml` sets no `windowSplashScreenAnimatedIcon`), so the system used the launcher icon. Nothing else to back up for it.

## Restore

From the repo root:

1. Copy every file back, dropping `.bak` on Dart files:
   ```sh
   B=backup/splash-logo-loader-v1
   (cd $B && find . -type f ! -name README.md) | while read p; do
     o="${p#./}"; o="${o%.bak}"; mkdir -p "$(dirname "$o")"; cp "$B/${p#./}" "$o"
   done
   ```
2. Restoring `splash_controller.dart` / `splash_view.dart` brings back the LogoLoader flow. Alternative without restoring: set `kSplashUsesLogoIntro = false`.
3. Delete files added later that nothing else uses (`lib/core/widgets/logo_intro/`, `tool/splash/`, the `/debug/logo-intro` route) and the `logo_intro_data.dart` line in `test/core/color_allowlist.txt`.
4. `flutter analyze`, then `git status` to review.
