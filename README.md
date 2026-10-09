# Pump and Plate

A private workout, nutrition and grocery tracker for Android and iPhone. Everything you log stays on your phone: there are no accounts, no ads, no analytics and no servers.

- **Workouts:** plans, a set-by-set logger with rest timers, warm-ups, notes, training blocks, and muscle maps down to individual muscle heads.
- **Food:** a food log with barcode scanning, recipes, planned meals, macro goals and a grocery list.
- **Body:** weigh-ins with a trend line and projection, sleep, water and supplements.
- **On-device AI:** a chat that can log food, plan workouts and answer questions about your data. It runs entirely on the phone: download one of three models (Light, Medium, High), or on newer iPhones use Apple's built-in model. Nothing you type leaves the phone, and the AI only ever prepares cards you confirm.

## What leaves the phone

Only three things ever touch the internet, and none of them carry your data:

1. **Food lookups** go to [Open Food Facts](https://world.openfoodfacts.org): a barcode number, or the words you type when you search online for a branded food.
2. **AI model downloads** come from [Hugging Face](https://huggingface.co/litert-community), once, when you choose to download one.
3. **Tips** go through Google Play or the App Store's own purchase screen.

The app collects no data, and its store listings will say so.

## Building it

### Windows (Android)

1. Put this folder at a short path without spaces, for example `Z:\fitapp`.
2. Run `setup.bat` once. It downloads Git, Java 17, Flutter and the Android SDK into a `tools` folder here, so nothing is installed elsewhere.
3. Run `build.bat`. It runs the tests, then puts the APK in `output\`.

Your signing key is saved to `keys\`. Keep that folder safe and never upload it.

### Cloud builds (Android and iPhone)

Every push to `main` runs [`.github/workflows/build.yml`](.github/workflows/build.yml) on GitHub's computers. It runs the tests, builds an Android debug APK, and builds the iPhone app unsigned on a Mac. The iOS project is generated fresh each time by `flutter create`, then [`scripts/patch-ios.sh`](scripts/patch-ios.sh) applies the app's settings. The iPhone-only native code is in [`app/packages/pump_native`](app/packages/pump_native).

## Layout

| Folder | What's in it |
| --- | --- |
| `app/lib` | The Flutter app (shared by Android and iPhone) |
| `app/test` | Tests (`flutter test`) |
| `app/packages/pump_native` | iPhone native code: device features, backup folder, Apple's on-device AI |
| `scripts/patch-android.ps1` | Android settings, native code and widgets, applied after `flutter create` |
| `scripts/patch-ios.sh` | iPhone settings and icon, applied after `flutter create` |
| `scripts/icons` | App icons for Android and iPhone |
| `store` | Store listing images |

## Reporting bugs

Open an [issue](../../issues) with your phone model, what you did and what happened. Please don't include personal data.

## Licence and third-party content

The code is free software under the [GNU General Public License v3.0](LICENSE). You can read it, build it, change it and share it, as long as anything you share is under the same licence with its source code.

The name **Pump and Plate** and the app icon are not covered by the licence. If you publish your own version, give it a different name and icon.

Some files in this repository belong to others and keep their own terms; the GPL doesn't cover them:

| Files | Owner and terms |
| --- | --- |
| `app/assets/bodyfat/` | Body-fat reference photos from JN Muscle Lab (Jeff Nippard), shared by him for public use as reference images. Credited in the app. If you reuse the code, check his terms before reusing these photos. |
| `app/assets/fonts/` | Geist and Geist Mono (The Geist Project Authors), under the SIL Open Font License 1.1 (`app/assets/fonts/OFL.txt`). |
| `app/assets/foods/` | Food data from the USDA National Nutrient Database (SR28), a US government work in the public domain. |
