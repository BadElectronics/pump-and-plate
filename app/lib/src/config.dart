/// App-wide settings you can safely edit by hand.
library;

const String appName = 'Pump and Plate';

/// Sent with Open Food Facts lookups, as their rules ask ("AppName/Version
/// (contact)"), so they can reach us about the app's traffic. Only the
/// barcode number or search words are ever sent, never anything about you.
const String openFoodFactsContact = 'support@luchelectronics.com';

/// The build shown in Settings > About.
const String buildLabel = 'Phase 5, build 16';

/// The privacy policy, on the website (Settings > Support links to it).
const String privacyPolicyUrl = 'https://luchelectronics.com/privacy.html';

/// Where "Report a bug" emails go (Luch Electronics LLC, on Proton).
const String supportEmail = 'support@luchelectronics.com';

/// "Watch on YouTube" opens this. Empty hides the button everywhere; put the
/// channel link here to show it.
const String youtubeUrl = '';

/// Tips: one-time ("consumable") products with these ids must be set up in
/// the Play Console (and App Store Connect), each with its price. Ids not set
/// up there are simply left out of the tip jar.
const List<String> tipProductIds = [
  'tip_1', 'tip_2', 'tip_3', 'tip_5', 'tip_10', 'tip_15', 'tip_20', 'tip_25', 'tip_50', 'tip_100',
];

/// The three tips shown as quick buttons; the rest are under "Other amount".
const List<String> quickTipIds = ['tip_3', 'tip_5', 'tip_10'];
