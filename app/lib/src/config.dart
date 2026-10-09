/// App-wide settings you can safely edit by hand.
library;

const String appName = 'Pump and Plate';

/// Sent with Open Food Facts lookups, as their rules ask ("AppName/Version
/// (contact)"). Put your email here if you'd like them to be able to reach
/// you about your app's traffic; only the barcode number is ever sent.
const String openFoodFactsContact = 'personal app';

/// The build shown in Settings > About.
const String buildLabel = 'Phase 5, build 15';

/// Where "Report a bug" emails go. A placeholder until a real address is
/// chosen: change it here.
const String supportEmail = 'bugs@example.com';

/// "Watch on YouTube" opens this. A placeholder until the channel link is
/// filled in here.
const String youtubeUrl = 'https://www.youtube.com/';

/// Tips: one-time ("consumable") products with these ids must be set up in
/// the Play Console (and App Store Connect), each with its price. Ids not set
/// up there are simply left out of the tip jar.
const List<String> tipProductIds = [
  'tip_1', 'tip_2', 'tip_3', 'tip_5', 'tip_10', 'tip_15', 'tip_20', 'tip_25', 'tip_50', 'tip_100',
];

/// The three tips shown as quick buttons; the rest are under "Other amount".
const List<String> quickTipIds = ['tip_3', 'tip_5', 'tip_10'];
