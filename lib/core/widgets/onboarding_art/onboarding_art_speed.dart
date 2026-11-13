/// How fast each animation plays, as a multiple of the authored HTML speed
/// (1.0 = exactly the HTML). The clock multiplies real elapsed seconds by this
/// in one place, `OnboardingArtController.advance`; no curve, delay or spring
/// constant inside the painters is changed, so the shape of the animation is
/// the authored one, only played faster.
///
/// Intro and loop speed up equally: the loop length in real seconds is the
/// script period divided by the speed. The reduced-motion still frame uses
/// script time and ignores these.
///
/// To promote into the main onboarding: keep this file with `OnboardingArt`
/// (the widget reads it through `OnboardingArtKind.speed`).
const double kShieldSpeed = 1.25;
const double kNetworkSpeed = 1.25;
const double kBuildingsSpeed = 1.25;

/// Real seconds one loop takes at [speed] (script period / speed).
double loopSeconds(double scriptPeriod, double speed) => scriptPeriod / speed;
