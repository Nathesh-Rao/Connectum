# Onboarding Lottie v1 (retired)

The three onboarding slide animations (conversations, enterprises, security) as Lottie, with the 340 x 270 stage widget they ran in. Replaced by the native painters in `lib/core/widgets/onboarding_art/` shown through `lib/core/widgets/onboarding_art_stage.dart`.

Contents (same relative paths as in the app):
- `assets/lottie/onboarding_{network,enterprises,security}.json`: originals (warm colours).
- `assets/lottie/onboarding_{network,enterprises,security}_blue.json`: the blue-only copies the app loaded.
- `lib/core/widgets/onboarding_lottie.dart`: `OnboardingLottie` / `OnboardingLottieFile` (entry once, then idle loop; static frame on reduced motion).
- `lib/core/widgets/onboarding_stage.dart`: `OnboardingStage` (340 x 270 box on the glow band).

To restore:
1. Copy the two `lib/` files and the `assets/lottie/*.json` files back to the same paths (`assets/lottie/` is already a pubspec asset folder).
2. In `lib/features/onboarding/onboarding_view.dart` put the page padding back on the scaffold, and replace `OnboardingArtStage(...)` by `OnboardingStage(slide:, controller:, itemCount: slides.length, onPageChanged:, itemBuilder: (context, i) => OnboardingLottie(file: OnboardingLottieFile.values[i], isActive: c.page.value == i))`.
3. Re-add `lib/core/widgets/onboarding_stage.dart` to `test/core/color_allowlist.txt` (black and transparent alpha mask stops of a ShaderMask) and the three `_blue` assets to `DebugAssetsController.lottieAssets`.
4. `tool/lottie/recolor_lottie.py` still holds `BLUE_ONLY_RULES` for the three files; run it to rebuild the `_blue` copies from the originals.
