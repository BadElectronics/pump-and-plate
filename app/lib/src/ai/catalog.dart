/// The on-device AI models and which one suits this phone.
/// No Flutter imports: unit-tested.
library;

/// The three downloadable models, plus Apple's model built into newer
/// iPhones (iOS 26 and later, with Apple Intelligence on).
enum AiTier { light, medium, high, apple }

extension AiTierLabel on AiTier {
  String get label => switch (this) {
        AiTier.light => 'Light',
        AiTier.medium => 'Medium',
        AiTier.high => 'High',
        AiTier.apple => 'Apple Intelligence',
      };
}

/// The models that are downloaded (or imported) into the app.
const downloadTiers = [AiTier.light, AiTier.medium, AiTier.high];

/// One downloadable model. Values come from flutter_gemma's tested model list.
class AiModelInfo {
  const AiModelInfo({
    required this.tier,
    required this.name,
    required this.file,
    required this.url,
    required this.sizeBytes,
    required this.family,
    required this.gpu,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.blurb,
    this.maxTokens = 4096,
  });

  final AiTier tier;
  final String name;

  /// The model file's name, which is also its id once installed.
  final String file;
  final String url;
  final int sizeBytes;

  /// 'qwen3' or 'gemma4': how the engine talks to it.
  final String family;

  /// Runs best on the graphics chip (else the processor).
  final bool gpu;
  final double temperature;
  final int topK;
  final double topP;
  final String blurb;

  /// Context size asked for when the model starts (prompt plus answer).
  /// Smaller needs less memory.
  final int maxTokens;

  /// Built into the phone: nothing to download.
  bool get builtIn => sizeBytes == 0;

  String get sizeLabel => builtIn ? 'built in' : formatBytes(sizeBytes);
}

const aiModels = <AiTier, AiModelInfo>{
  AiTier.light: AiModelInfo(
    tier: AiTier.light,
    name: 'Qwen3 0.6B',
    file: 'Qwen3-0.6B.litertlm',
    url: 'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
    sizeBytes: 586 * 1000 * 1000,
    family: 'qwen3',
    gpu: false,
    temperature: 0.7,
    topK: 40,
    topP: 0.95,
    blurb: 'Small and quick on any phone. Simpler answers.',
    // Half the usual context: roughly 0.45 GB less memory on the phones Light
    // is meant for, and still room for chat, logging and a pasted recipe.
    maxTokens: 2048,
  ),
  AiTier.medium: AiModelInfo(
    tier: AiTier.medium,
    name: 'Gemma 4 E2B',
    file: 'gemma-4-E2B-it.litertlm',
    url: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    sizeBytes: 2583 * 1000 * 1000,
    family: 'gemma4',
    gpu: true,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    blurb: 'Good answers on most phones from the last few years.',
  ),
  AiTier.high: AiModelInfo(
    tier: AiTier.high,
    name: 'Gemma 4 E4B',
    file: 'gemma-4-E4B-it.litertlm',
    url: 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
    sizeBytes: 4300 * 1000 * 1000,
    family: 'gemma4',
    gpu: true,
    temperature: 1.0,
    topK: 64,
    topP: 0.95,
    blurb: 'The smartest. Best on recent flagship phones.',
  ),
  AiTier.apple: AiModelInfo(
    tier: AiTier.apple,
    name: 'Apple\'s on-device model',
    file: 'apple',
    url: '',
    sizeBytes: 0,
    family: 'apple',
    gpu: false,
    temperature: 0.7,
    topK: 40,
    topP: 0.95,
    blurb: 'Built into this iPhone: no download, and it never leaves the phone. '
        'It remembers less of a long chat than the downloaded models.',
  ),
};

AiModelInfo modelFor(AiTier t) => aiModels[t]!;

AiTier? tierByName(String? name) {
  for (final t in AiTier.values) {
    if (t.name == name) return t;
  }
  return null;
}

String formatBytes(int bytes) {
  if (bytes >= 1000 * 1000 * 1000) {
    final gb = bytes / (1000 * 1000 * 1000);
    return '${gb >= 10 ? gb.round() : (gb * 10).round() / 10} GB';
  }
  return '${(bytes / (1000 * 1000)).round()} MB';
}

/// What the phone reports about itself.
class DeviceSpecs {
  const DeviceSpecs({
    required this.totalRam,
    required this.freeStorage,
    this.soc = '',
    this.socMaker = '',
    this.model = '',
    this.brand = '',
    this.abis = const [],
  });

  final int totalRam;
  final int freeStorage;

  /// Chip model, e.g. "SM8650" or "Tensor G3" (older Android: the board name).
  final String soc;
  final String socMaker;
  final String model;
  final String brand;
  final List<String> abis;

  factory DeviceSpecs.fromMap(Map<Object?, Object?> m) {
    int i(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
    String s(Object? v) => v is String ? v : '';
    var model = s(m['model']);
    var soc = s(m['soc']);
    // iPhones report a model code ("iPhone16,1"): show its name and chip.
    final iphone = iPhoneFor(model);
    if (iphone != null) {
      model = iphone.name;
      if (soc.isEmpty) soc = iphone.chip;
    }
    return DeviceSpecs(
      totalRam: i(m['totalRam']),
      freeStorage: i(m['freeStorage']),
      soc: soc,
      socMaker: s(m['socMaker']),
      model: model,
      brand: s(m['brand']),
      abis: [for (final a in (m['abis'] is List ? m['abis'] as List : const [])) '$a'],
    );
  }

  /// The models' engine only runs on 64-bit ARM phones.
  bool get supported => abis.any((a) => a.contains('arm64'));

  /// Memory in GiB, as the phone reports it (an "8 GB" phone shows about 7.3).
  double get ramGiB => totalRam / (1024 * 1024 * 1024);

  String get ramLabel => '${(totalRam / (1000 * 1000 * 1000)).round()} GB';

  /// A friendly chip name when we know it, else what the phone reports.
  String get chipLabel => chipName(soc, socMaker);
}

/// An iPhone's name and chip, from the model code it reports.
class IPhoneInfo {
  const IPhoneInfo(this.name, this.chip);
  final String name;
  final String chip;
}

const _iPhones = <String, IPhoneInfo>{
  'iPhone11,2': IPhoneInfo('iPhone XS', 'Apple A12'),
  'iPhone11,4': IPhoneInfo('iPhone XS Max', 'Apple A12'),
  'iPhone11,6': IPhoneInfo('iPhone XS Max', 'Apple A12'),
  'iPhone11,8': IPhoneInfo('iPhone XR', 'Apple A12'),
  'iPhone12,1': IPhoneInfo('iPhone 11', 'Apple A13'),
  'iPhone12,3': IPhoneInfo('iPhone 11 Pro', 'Apple A13'),
  'iPhone12,5': IPhoneInfo('iPhone 11 Pro Max', 'Apple A13'),
  'iPhone12,8': IPhoneInfo('iPhone SE (2nd generation)', 'Apple A13'),
  'iPhone13,1': IPhoneInfo('iPhone 12 mini', 'Apple A14'),
  'iPhone13,2': IPhoneInfo('iPhone 12', 'Apple A14'),
  'iPhone13,3': IPhoneInfo('iPhone 12 Pro', 'Apple A14'),
  'iPhone13,4': IPhoneInfo('iPhone 12 Pro Max', 'Apple A14'),
  'iPhone14,4': IPhoneInfo('iPhone 13 mini', 'Apple A15'),
  'iPhone14,5': IPhoneInfo('iPhone 13', 'Apple A15'),
  'iPhone14,2': IPhoneInfo('iPhone 13 Pro', 'Apple A15'),
  'iPhone14,3': IPhoneInfo('iPhone 13 Pro Max', 'Apple A15'),
  'iPhone14,6': IPhoneInfo('iPhone SE (3rd generation)', 'Apple A15'),
  'iPhone14,7': IPhoneInfo('iPhone 14', 'Apple A15'),
  'iPhone14,8': IPhoneInfo('iPhone 14 Plus', 'Apple A15'),
  'iPhone15,2': IPhoneInfo('iPhone 14 Pro', 'Apple A16'),
  'iPhone15,3': IPhoneInfo('iPhone 14 Pro Max', 'Apple A16'),
  'iPhone15,4': IPhoneInfo('iPhone 15', 'Apple A16'),
  'iPhone15,5': IPhoneInfo('iPhone 15 Plus', 'Apple A16'),
  'iPhone16,1': IPhoneInfo('iPhone 15 Pro', 'Apple A17 Pro'),
  'iPhone16,2': IPhoneInfo('iPhone 15 Pro Max', 'Apple A17 Pro'),
  'iPhone17,1': IPhoneInfo('iPhone 16 Pro', 'Apple A18 Pro'),
  'iPhone17,2': IPhoneInfo('iPhone 16 Pro Max', 'Apple A18 Pro'),
  'iPhone17,3': IPhoneInfo('iPhone 16', 'Apple A18'),
  'iPhone17,4': IPhoneInfo('iPhone 16 Plus', 'Apple A18'),
  'iPhone17,5': IPhoneInfo('iPhone 16e', 'Apple A18'),
};

/// Null for anything that isn't an iPhone model code. Newer iPhones than
/// the table get a generic name and "A19 or newer" (they're all fast).
IPhoneInfo? iPhoneFor(String code) {
  final known = _iPhones[code];
  if (known != null) return known;
  final m = RegExp(r'^iPhone(\d+),\d+$').firstMatch(code);
  if (m == null) return null;
  final major = int.parse(m.group(1)!);
  if (major >= 18) return IPhoneInfo('iPhone ($code)', 'Apple A19 or newer');
  return IPhoneInfo('iPhone ($code)', '');
}

/// Recent flagship chips, by the model codes phones report.
bool isFlagshipChip(String soc) {
  final s = soc.toUpperCase().replaceAll(' ', '');
  // Apple A17 Pro (iPhone 15 Pro) and newer.
  final apple = RegExp(r'^APPLEA(\d+)').firstMatch(s);
  if (apple != null) return int.parse(apple.group(1)!) >= 17;
  // Qualcomm Snapdragon 8 Gen 2 (SM8550) and newer.
  final sm = RegExp(r'^SM8(\d)(\d)0').firstMatch(s);
  if (sm != null && int.parse(sm.group(1)! + sm.group(2)!) >= 55) return true;
  // Google Tensor G3 and newer.
  final tensor = RegExp(r'^TENSORG(\d+)').firstMatch(s);
  if (tensor != null && int.parse(tensor.group(1)!) >= 3) return true;
  // MediaTek Dimensity 9200 (MT6985) and newer.
  final mt = RegExp(r'^MT(\d{4})').firstMatch(s);
  if (mt != null) {
    final n = int.parse(mt.group(1)!);
    if (n >= 6985 && n < 7000) return true;
  }
  // Samsung Exynos 2400 (s5e9945) and newer.
  final ex = RegExp(r'^S5E99(\d)(\d)').firstMatch(s);
  if (ex != null && int.parse(ex.group(1)!) >= 4) return true;
  return false;
}

String chipName(String soc, String maker) {
  final s = soc.toUpperCase().replaceAll(' ', '');
  const qualcomm = {
    'SM8450': 'Snapdragon 8 Gen 1',
    'SM8475': 'Snapdragon 8+ Gen 1',
    'SM8550': 'Snapdragon 8 Gen 2',
    'SM8650': 'Snapdragon 8 Gen 3',
    'SM8750': 'Snapdragon 8 Elite',
    'SM8850': 'Snapdragon 8 Elite Gen 5',
  };
  if (qualcomm.containsKey(s)) return qualcomm[s]!;
  if (s.startsWith('TENSORG')) return 'Tensor G${s.substring(7)}';
  if (soc.isEmpty) return 'unknown chip';
  return maker.isEmpty || soc.toLowerCase().contains(maker.toLowerCase()) ? soc : '$maker $soc';
}

class TierAdvice {
  const TierAdvice({required this.tier, required this.reason});

  /// Null when the phone can't run any of them.
  final AiTier? tier;
  final String reason;
}

/// Picks a tier from memory first, then the chip.
TierAdvice recommendTier(DeviceSpecs d) {
  if (!d.supported) {
    return const TierAdvice(
      tier: null,
      reason: 'On-device AI needs a 64-bit phone, and this one is 32-bit.',
    );
  }
  final gib = d.ramGiB;
  // iPhones let one app use less of their memory than Android phones do.
  if (gib < 5.0 || (d.brand == 'Apple' && gib < 7.0)) {
    return TierAdvice(tier: AiTier.light, reason: 'Best fit for ${d.ramLabel} of memory.');
  }
  if (gib >= 10.0 && (isFlagshipChip(d.soc) || gib >= 14.0)) {
    return TierAdvice(tier: AiTier.high, reason: '${d.ramLabel} of memory and a fast chip.');
  }
  return TierAdvice(tier: AiTier.medium, reason: 'Best fit for ${d.ramLabel} of memory.');
}

/// Room needed to download and unpack a model, with some spare.
int spaceNeeded(AiModelInfo m) => (m.sizeBytes * 1.1).round() + 500 * 1000 * 1000;

/// A warning for picking [t] on this phone, or null if it should be fine.
String? tierWarning(AiTier t, DeviceSpecs d) {
  if (!d.supported) return 'Not supported on this phone.';
  final m = modelFor(t);
  if (d.freeStorage > 0 && d.freeStorage < spaceNeeded(m)) {
    return 'Needs about ${formatBytes(spaceNeeded(m))} free; this phone has ${formatBytes(d.freeStorage)}.';
  }
  final rec = recommendTier(d).tier;
  if (rec != null && t.index > rec.index) return 'Likely slow on this phone.';
  return null;
}
