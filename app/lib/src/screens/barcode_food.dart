import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../calc/barcode.dart';
import '../calc/calc.dart';
import '../data/models.dart';
import '../services/food_lookup.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Scans a package barcode and returns one of your foods for it: one you
/// already have, or a new one you review and save. Null if cancelled.
///
/// New products are looked up in Open Food Facts only if you've allowed it;
/// the app asks the first time.
Future<String?> scanFoodBarcode(BuildContext context, {OpenFoodFactsLookup lookup = const OpenFoodFactsLookup()}) async {
  final s = AppScope.of(context);
  final code = await Navigator.of(context).push<String>(BarcodeScanScreen.route());
  if (code == null || !context.mounted) return null;

  final known = s.foodByBarcode(code);
  if (known != null) return known.id;

  var online = s.settings.barcodeOnline;
  if (online == null) {
    final answer = await _askOnline(context);
    if (answer == null || !context.mounted) return null;
    s.setSettings(s.settings.copyWith(barcodeOnline: answer));
    online = answer;
  }

  ScannedProduct? product;
  String? note;
  if (online) {
    final result = await showDialog<LookupResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LookupDialog(code: code, lookup: lookup),
    );
    if (!context.mounted) return null;
    switch (result?.status) {
      case LookupStatus.found:
        product = result!.product;
      case LookupStatus.notFound:
        note = 'Open Food Facts doesn\'t have this product yet. Add it from the label.';
      case LookupStatus.offline:
        note = 'You\'re offline, so it couldn\'t be looked up. Add it from the label.';
      case LookupStatus.failed:
      case null:
        note = 'The lookup didn\'t work this time. Add it from the label, or scan again later.';
    }
  } else {
    note = 'Online lookups are off (Settings > Groceries). Add it from the label.';
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<String>(ProductReviewScreen.route(code: code, product: product, note: note));
}

Future<bool?> _askOnline(BuildContext context) {
  final c = AppColors.of(context);
  return showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: c.surface,
      title: const Text('Look up new products online?'),
      content: const Text(
        'When you scan something Pump and Plate doesn\'t know yet, it can look it up in Open Food Facts, '
        'a free food database. Only the barcode number is sent, nothing about you. You\'ll check '
        'the result before it\'s saved.\n\nYou can change this later in Settings > Groceries.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          style: TextButton.styleFrom(foregroundColor: c.muted),
          child: const Text('No, I\'ll type it in'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          style: TextButton.styleFrom(foregroundColor: c.accent),
          child: const Text('Look it up'),
        ),
      ],
    ),
  );
}

/// "Looking up..." while the lookup runs; closes itself with the result.
class _LookupDialog extends StatefulWidget {
  const _LookupDialog({required this.code, required this.lookup});

  final String code;
  final OpenFoodFactsLookup lookup;

  @override
  State<_LookupDialog> createState() => _LookupDialogState();
}

class _LookupDialogState extends State<_LookupDialog> {
  @override
  void initState() {
    super.initState();
    widget.lookup.byBarcode(widget.code).then((r) {
      if (mounted) Navigator.of(context).pop(r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      backgroundColor: c.surface,
      content: Row(
        children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.accent)),
          const SizedBox(width: 16),
          const Expanded(child: Text('Looking it up…')),
        ],
      ),
    );
  }
}

/// The camera, with a frame to aim at, a flashlight, and a way to type the
/// number instead. Returns the code's digits.
///
/// Barcodes are read on the phone by ZXing; the camera picture never leaves it.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  static Route<String> route() => MaterialPageRoute<String>(builder: (_) => const BarcodeScanScreen());

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  /// Grocery barcodes only (EAN and UPC).
  static const int _formats = Format.ean13 | Format.ean8 | Format.upca | Format.upce;

  CameraController? _camera;
  bool _cameraFailed = false;
  bool _done = false;
  bool _torch = false;

  void _onCamera(CameraController? controller, Exception? error) {
    if (!mounted) return;
    // A missing flashlight isn't a reason to give up on the camera.
    if (error is CameraException && error.code == 'setFlashModeFailed') return;
    setState(() {
      if (controller != null) _camera = controller;
      _cameraFailed = controller == null && error != null;
    });
  }

  Future<void> _toggleTorch() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    final on = !_torch;
    try {
      await cam.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torch = on);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This phone\'s flashlight can\'t be used here.')),
      );
    }
  }

  void _finish(String digits) {
    if (_done) return;
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(digits);
  }

  void _onScan(Code code) {
    if (!code.isValid) return;
    final d = barcodeDigits(code.text ?? '');
    if (_looksRight(d)) _finish(d);
  }

  /// A grocery code with the right length and a correct check digit.
  static bool _looksRight(String d) {
    if (d.length == 12 || d.length == 13) return validCheckDigit(d);
    if (d.length == 8) {
      final expanded = upcEToUpcA(d);
      return validCheckDigit(d) || (expanded != null && validCheckDigit(expanded));
    }
    return false;
  }

  Future<void> _typeIt() async {
    final c = AppColors.of(context);
    final ctrl = TextEditingController();
    final digits = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Type the barcode number'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 14,
          decoration: const InputDecoration(hintText: 'The digits under the bars', counterText: ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(ctrl.text),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Use it'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 500), ctrl.dispose);
    if (digits == null || !mounted) return;
    final d = barcodeDigits(digits);
    final expanded = d.length == 8 ? upcEToUpcA(d) : null;
    final ok = validCheckDigit(d) || (expanded != null && validCheckDigit(expanded));
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That number doesn\'t look right. Check the digits and try again.')),
      );
      return;
    }
    _finish(d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _cameraFailed
                ? _CameraProblem(onType: _typeIt)
                : ReaderWidget(
                    codeFormat: _formats,
                    onScan: _onScan,
                    onControllerCreated: _onCamera,
                    tryHarder: true,
                    tryRotate: true,
                    // Look often, and over most of the picture, so a barcode
                    // anywhere near the frame is caught.
                    scanDelay: const Duration(milliseconds: 120),
                    cropPercent: 0.9,
                    // This screen draws its own frame and buttons.
                    showScannerOverlay: false,
                    showFlashlight: false,
                    showToggleCamera: false,
                    showGallery: false,
                    allowPinchZoom: true,
                    loading: const ColoredBox(color: Colors.black),
                  ),
          ),
          // The aiming frame.
          Center(
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: _torch ? 'Flashlight off' : 'Flashlight on',
                        onPressed: _toggleTorch,
                        icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Text(
                    'Point at the barcode on the package',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _typeIt,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Type the number instead'),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.onType});

  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          const Text(
            'The camera isn\'t available. If you said no to camera access, you can allow it in your '
            'phone\'s settings for Pump and Plate.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onType,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Type the number instead'),
          ),
        ],
      ),
    );
  }
}

/// Check (or fill in) a scanned product before it joins your foods.
class ProductReviewScreen extends StatefulWidget {
  const ProductReviewScreen({super.key, required this.code, this.product, this.note});

  final String code;

  /// From Open Food Facts, or null to fill everything in by hand.
  final ScannedProduct? product;

  /// Why there's no product (not found, offline...), shown at the top.
  final String? note;

  static Route<String> route({required String code, ScannedProduct? product, String? note}) =>
      MaterialPageRoute<String>(builder: (_) => ProductReviewScreen(code: code, product: product, note: note));

  @override
  State<ProductReviewScreen> createState() => _ProductReviewScreenState();
}

class _ProductReviewScreenState extends State<ProductReviewScreen> {
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late final TextEditingController _serving;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    String n(double? v, {bool whole = false}) =>
        v == null ? '' : (whole ? v.round().toString() : oneDecimal(v));
    final missing = p?.missing ?? const <String>[];
    _name = TextEditingController(text: p?.name ?? '');
    _brand = TextEditingController(text: p?.brand ?? '');
    _kcal = TextEditingController(text: p == null || missing.contains('calories') ? '' : n(p.per100.kcal, whole: true));
    _protein = TextEditingController(text: p == null || missing.contains('protein') ? '' : n(p.per100.protein));
    _carbs = TextEditingController(text: p == null || missing.contains('carbs') ? '' : n(p.per100.carbs));
    _fat = TextEditingController(text: p == null || missing.contains('fat') ? '' : n(p.per100.fat));
    _serving = TextEditingController(text: n(p?.servingGrams, whole: true));
  }

  @override
  void dispose() {
    for (final c in [_name, _brand, _kcal, _protein, _carbs, _fat, _serving]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save(AppState s) {
    final name = _name.text.trim();
    final kcal = parseNumber(_kcal.text);
    if (name.isEmpty || kcal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least a name and the calories per 100 g.')),
      );
      return;
    }
    final serving = parseNumber(_serving.text);
    final brand = _brand.text.trim();
    final f = Food(
      id: newId('f'),
      name: name,
      brand: brand.isEmpty ? null : brand,
      per100: Macros(
        kcal: kcal,
        protein: parseNumber(_protein.text) ?? 0,
        carbs: parseNumber(_carbs.text) ?? 0,
        fat: parseNumber(_fat.text) ?? 0,
      ),
      servingGrams: serving != null && serving > 0 ? serving : null,
      barcode: barcodeVariants(widget.code).first,
      custom: true,
    );
    s.saveFood(f);
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(f.id);
  }

  Widget _field(AppColors c, String label, TextEditingController ctrl, {String? suffix, bool number = false, Key? key}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(label),
          number
              ? NumberBox(key: key, controller: ctrl, suffix: suffix ?? '', semanticLabel: label, onChanged: (_) {})
              : Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    key: key,
                    controller: ctrl,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: c.accent,
                    style: AppText.body(c).copyWith(fontSize: 16),
                    decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                  ),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final p = widget.product;
    final missing = p?.missing ?? const <String>[];
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 40),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: c.text),
                ),
                Expanded(
                  child: Text(p == null ? 'Add this product' : 'Check this product',
                      style: AppText.title(c).copyWith(fontSize: 22)),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Barcode ${barcodeVariants(widget.code).first}', style: AppText.quiet(c).copyWith(fontSize: 12)),
                  const SizedBox(height: 10),
                  if (widget.note != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(12)),
                      child: Text(widget.note!, style: AppText.body(c).copyWith(fontSize: 14)),
                    ),
                  if (missing.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: c.protein.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        'Not in the database: ${missing.join(', ')}. Fill them in from the label.',
                        style: AppText.body(c).copyWith(fontSize: 14),
                      ),
                    ),
                  _field(c, 'Name', _name, key: const ValueKey('review-name')),
                  _field(c, 'Brand (optional)', _brand),
                  Text('Per 100 g', style: AppText.label(c)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _field(c, 'Calories', _kcal, suffix: 'kcal', number: true, key: const ValueKey('review-kcal'))),
                      const SizedBox(width: 10),
                      Expanded(child: _field(c, 'Protein', _protein, suffix: 'g', number: true)),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _field(c, 'Carbs', _carbs, suffix: 'g', number: true)),
                      const SizedBox(width: 10),
                      Expanded(child: _field(c, 'Fat', _fat, suffix: 'g', number: true)),
                    ],
                  ),
                  _field(c, 'One serving (optional)', _serving, suffix: 'g', number: true),
                  const SizedBox(height: 6),
                  SmallButton(label: 'Save to my foods', onTap: () => _save(s)),
                  if (p != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Product data from Open Food Facts (openfoodfacts.org), shared under the Open '
                      'Database License. It\'s added by volunteers, so check it against the label.',
                      style: AppText.quiet(c).copyWith(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
