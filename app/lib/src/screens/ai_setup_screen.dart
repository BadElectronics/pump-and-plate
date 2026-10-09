import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../ai/catalog.dart';
import '../data/store.dart';
import '../services/ai_apple.dart';
import '../services/ai_engine.dart';
import '../services/device_probe.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// A download or import in progress. Kept outside the screen, so leaving and
/// coming back still shows it (and can't start a second copy).
class _AiJob {
  _AiJob(this.tier, this.label, this.cancel);
  final AiTier tier;
  final String label;
  final AiCancel? cancel;
  final progress = ValueNotifier<int>(0);
}

final _job = ValueNotifier<_AiJob?>(null);

/// Pick, download, switch or remove the on-device AI model. Nothing downloads
/// until the user taps Download.
class AiSetupView extends StatefulWidget {
  const AiSetupView({super.key, this.onSkip, this.onReady});

  /// Shown as "Skip for now" (Chat's first visit), when set.
  final VoidCallback? onSkip;

  /// Called once a model is ready to use.
  final VoidCallback? onReady;

  @override
  State<AiSetupView> createState() => _AiSetupViewState();
}

class _AiSetupViewState extends State<AiSetupView> {
  DeviceSpecs? _device;
  bool _loading = true;
  final _installed = <AiTier>{};

  /// Apple's built-in model, on iPhones that have (or could turn on) it.
  AppleAiStatus? _apple;

  /// The model being downloaded or imported, if any.
  AiTier? get _busy => _job.value?.tier;

  @override
  void initState() {
    super.initState();
    _job.addListener(_onJob);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _job.removeListener(_onJob);
    super.dispose();
  }

  void _onJob() {
    if (!mounted) return;
    setState(() {});
    if (_job.value == null) _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final services = ServicesScope.of(context);
    final device = await services.device.specs();
    final installed = <AiTier>{};
    final ai = services.ai;
    final apple = ai is AppleAiInfo ? await (ai as AppleAiInfo).refreshAppleStatus() : null;
    final downloads = ai is AppleAiInfo ? (ai as AppleAiInfo).downloadsAvailable : true;
    for (final t in downloadTiers) {
      if (downloads && await ai.isInstalled(modelFor(t))) installed.add(t);
    }
    if (apple == AppleAiStatus.available) installed.add(AiTier.apple);
    if (!mounted) return;
    setState(() {
      _apple = apple;
      _device = device;
      _installed
        ..clear()
        ..addAll(installed);
      _loading = false;
    });
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<bool> _confirm(String title, String body, String yes, {String no = 'Cancel'}) async {
    final c = AppColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: Text(no),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: Text(yes),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Makes [t] the model Chat uses. Others stay downloaded until removed.
  /// Works even if the user has left this screen meanwhile.
  Future<void> _activate(AiTier t, AppState s, AiEngine ai) async {
    s.setSettings(s.settings.copyWith(aiTier: t.name));
    if (!mounted) return;
    await _refresh();
    widget.onReady?.call();
  }

  Future<void> _use(AiTier t) => _activate(t, AppScope.of(context), ServicesScope.of(context).ai);

  Future<void> _download(AiTier t) async {
    if (_job.value != null) return;
    final services = ServicesScope.of(context);
    final appState = AppScope.of(context);
    final m = modelFor(t);
    final device = _device;
    if (device != null && device.freeStorage > 0 && device.freeStorage < spaceNeeded(m)) {
      await _confirm(
        'Not enough space',
        '${t.label} needs about ${formatBytes(spaceNeeded(m))} free, and this phone has '
            '${formatBytes(device.freeStorage)}. Free some space, or pick a smaller model.',
        'OK',
        no: 'Close',
      );
      return;
    }
    final others = _installed.isEmpty ? '' : ' Models you already have stay too, so you can switch any time.';
    if (!await _confirm(
      'Download ${t.label}?',
      '${m.name}, ${m.sizeLabel}. Once it\'s downloaded it works with no internet, and nothing you type '
          'or log ever leaves your phone.$others',
      'Download',
    )) {
      return;
    }
    final net = await services.device.network();
    if (!mounted) return;
    if (net == NetworkKind.none) {
      _snack('No internet connection. Connect to Wi-Fi and try again.');
      return;
    }
    if (net == NetworkKind.metered &&
        !await _confirm(
          'You\'re on mobile data',
          'This download is ${m.sizeLabel}. Use mobile data now, or wait until you\'re on Wi-Fi?',
          'Use mobile data',
          no: 'Wait for Wi-Fi',
        )) {
      return;
    }
    final cancel = AiCancel();
    final job = _AiJob(t, 'Downloading ${t.label}', cancel);
    _job.value = job;
    try {
      await services.ai.download(m, onProgress: (p) => job.progress.value = p.clamp(0, 100), cancel: cancel);
      _job.value = null;
      await _activate(t, appState, services.ai);
      if (mounted) _snack('${t.label} is ready.');
    } on AiDownloadCancelled {
      if (mounted) _snack('Download canceled.');
    } on AiFailure catch (e) {
      if (mounted) await _confirm('The download stopped', _friendly(e.message), 'OK', no: 'Close');
    } finally {
      if (identical(_job.value, job)) _job.value = null;
    }
  }

  Future<void> _remove(AiTier t) async {
    final m = modelFor(t);
    if (!await _confirm('Remove ${t.label}?', 'Frees ${m.sizeLabel}. You can download it again later.', 'Remove')) {
      return;
    }
    if (!mounted) return;
    final s = AppScope.of(context);
    await ServicesScope.of(context).ai.remove(m);
    if (s.settings.aiTier == t.name) s.setSettings(s.settings.copyWith(aiTier: null));
    await _refresh();
  }

  Future<void> _import() async {
    if (_job.value != null) return;
    final c = AppColors.of(context);
    final appState = AppScope.of(context);
    final ai = ServicesScope.of(context).ai;
    final t = await showDialog<AiTier>(
      context: context,
      builder: (d) => SimpleDialog(
        backgroundColor: c.surface,
        title: const Text('Which model is the file?'),
        children: [
          for (final t in downloadTiers)
            SimpleDialogOption(
              onPressed: () => Navigator.of(d).pop(t),
              child: Text('${t.label}: ${modelFor(t).file}'),
            ),
        ],
      ),
    );
    if (t == null || !mounted) return;
    final m = modelFor(t);
    final picked = await FilePicker.pickFile();
    if (picked == null || !mounted) return;
    final String? path = picked.path;
    if (path == null || path.isEmpty) {
      _snack('Couldn\'t open that file.');
      return;
    }
    final name = path.split(RegExp(r'[\\/]')).last;
    if (name.toLowerCase() != m.file.toLowerCase()) {
      await _confirm(
        'That\'s not the ${t.label} file',
        'The file should be named ${m.file}. Download it on your computer from the address '
            'in the setup notes, copy it to the phone, then try again.',
        'OK',
        no: 'Close',
      );
      return;
    }
    final job = _AiJob(t, 'Copying ${t.label} into the app', null);
    _job.value = job;
    try {
      // Kept in the app's own storage: the picker's copy can be cleared by Android.
      final dest = File('${(await aiImportDir()).path}/${m.file}');
      final src = File(path);
      final total = await src.length();
      var done = 0;
      final sink = dest.openWrite();
      await for (final chunk in src.openRead()) {
        sink.add(chunk);
        done += chunk.length;
        // A ValueNotifier only redraws when the percentage actually changes.
        job.progress.value = total > 0 ? (done * 100 ~/ total).clamp(0, 100) : 0;
      }
      await sink.close();
      // The file picker leaves its own copy in the app's cache: remove it.
      if (path.contains('/cache/') && path != dest.path) {
        try {
          await src.delete();
        } catch (_) {}
      }
      await ai.importFile(m, dest.path);
      _job.value = null;
      await _activate(t, appState, ai);
      if (mounted) _snack('${t.label} is ready.');
    } on AiFailure catch (e) {
      if (mounted) await _confirm('Couldn\'t import it', _friendly(e.message), 'OK', no: 'Close');
    } catch (e) {
      if (mounted) await _confirm('Couldn\'t import it', _friendly('$e'), 'OK', no: 'Close');
    } finally {
      if (identical(_job.value, job)) _job.value = null;
    }
  }

  /// Out-of-space errors in plain words.
  String _friendly(String message) => isStorageFull(message)
      ? 'Your phone is full. Delete things you don\'t need, like old photos, videos or apps, then try again.'
      : message;

  Widget _tierCard(AppColors c, AiTier t, AiTier? recommended, AiTier? current) {
    final m = modelFor(t);
    final installed = _installed.contains(t);
    final active = installed && current == t;
    final warning = _device == null ? null : tierWarning(t, _device!);
    final job = _job.value;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: active ? c.accent : c.line, width: active ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(t.label, style: AppText.body(c).copyWith(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (t == recommended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(10)),
                  child: Text('Recommended', style: TextStyle(color: c.onAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              const Spacer(),
              Text(m.sizeLabel, style: AppText.quiet(c).copyWith(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 2),
          Text('${m.name} · ${m.blurb}', style: AppText.quiet(c).copyWith(fontSize: 13)),
          if (warning != null && !installed) ...[
            const SizedBox(height: 4),
            Text(warning, style: AppText.body(c).copyWith(fontSize: 13, color: c.protein)),
          ],
          const SizedBox(height: 10),
          if (job != null && job.tier == t) ...[
            ValueListenableBuilder<int>(
              valueListenable: job.progress,
              builder: (context, pct, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${job.label}… $pct%', style: AppText.body(c).copyWith(fontSize: 13)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct == 0 ? null : pct / 100,
                      minHeight: 6,
                      color: c.accent,
                      backgroundColor: c.chip,
                    ),
                  ),
                ],
              ),
            ),
            if (job.cancel != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => job.cancel?.cancel(),
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('Cancel'),
                ),
              ),
          ] else if (active)
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: c.accent, size: 20),
                const SizedBox(width: 6),
                Expanded(child: Text('In use', style: AppText.body(c).copyWith(fontWeight: FontWeight.w600))),
                TextButton(
                  onPressed: _busy == null ? () => _remove(t) : null,
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('Remove'),
                ),
              ],
            )
          else if (installed)
            Row(
              children: [
                Expanded(child: SmallButton(label: 'Use this one', onTap: () => _busy == null ? _use(t) : null)),
                TextButton(
                  onPressed: _busy == null ? () => _remove(t) : null,
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('Remove'),
                ),
              ],
            )
          else
            Opacity(
              opacity: _busy == null && (_device?.supported ?? true) ? 1 : 0.4,
              child: IgnorePointer(
                ignoring: _busy != null || !(_device?.supported ?? true),
                child: SmallButton(
                  key: ValueKey('ai-download-${t.name}'),
                  label: 'Download',
                  quiet: t != recommended,
                  onTap: () => _download(t),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Apple's built-in model: nothing to download, so just "Use this one"
  /// (or what to do first, if it isn't ready).
  Widget _appleCard(AppColors c, AppleAiStatus status, AiTier? current) {
    final m = modelFor(AiTier.apple);
    final active = status == AppleAiStatus.available && current == AiTier.apple;
    final help = status.help;
    return Container(
      key: const ValueKey('ai-apple'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: active ? c.accent : c.line, width: active ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(AiTier.apple.label, style: AppText.body(c).copyWith(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text('No download', style: AppText.quiet(c).copyWith(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 2),
          Text('${m.name} · ${m.blurb}', style: AppText.quiet(c).copyWith(fontSize: 13)),
          if (help != null) ...[
            const SizedBox(height: 6),
            Text(help, style: AppText.body(c).copyWith(fontSize: 13, color: c.protein)),
          ],
          const SizedBox(height: 10),
          if (active)
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: c.accent, size: 20),
                const SizedBox(width: 6),
                Expanded(child: Text('In use', style: AppText.body(c).copyWith(fontWeight: FontWeight.w600))),
              ],
            )
          else if (status == AppleAiStatus.available)
            SmallButton(
              key: const ValueKey('ai-use-apple'),
              label: 'Use this one',
              onTap: () => _busy == null ? _use(AiTier.apple) : null,
            )
          else
            SmallButton(label: 'Check again', quiet: true, onTap: _refresh),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final ai = ServicesScope.of(context).ai;
    final current = tierByName(s.settings.aiTier);
    final device = _device;
    final advice = device == null ? null : recommendTier(device);
    final apple = _apple;
    final offerApple = apple != null && apple.offered;
    final downloads = ai is AppleAiInfo ? (ai as AppleAiInfo).downloadsAvailable : true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text('On-device AI', style: AppText.title(c)),
        const SizedBox(height: 10),
        const AiPrivacyNote(),
        const SizedBox(height: 10),
        Text(
          offerApple && downloads
              ? 'Use Apple\'s model, already on this iPhone, or download one of ours; nothing downloads until '
                  'you tap Download. You can switch any time.'
              : offerApple
                  ? 'This iPhone has Apple\'s model built in: no download needed.'
                  : 'Pick a model to download; nothing downloads until you tap Download. You can keep several and '
                      'switch between them; remove one any time to free space.',
          style: AppText.quiet(c).copyWith(fontSize: 14),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (!ai.available)
            SectionCard(
              child: Text(
                'On-device AI couldn\'t start on this phone. Chat still turns pasted recipes and '
                'workouts into drafts you can save.',
                style: AppText.body(c),
              ),
            )
          else ...[
            if (device != null)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  'Your phone: ${[
                    if (device.model.isNotEmpty) device.model,
                    '${device.ramLabel} memory',
                    device.chipLabel,
                    if (device.freeStorage > 0) '${formatBytes(device.freeStorage)} free',
                  ].join(' · ')}'
                  '${advice == null ? '' : '\n${advice.reason}'}',
                  style: AppText.body(c).copyWith(fontSize: 14),
                ),
              ),
            if (apple != null && apple.offered) _appleCard(c, apple, current),
            if (downloads) ...[
              if (offerApple) ...[
                const SizedBox(height: 6),
                Text('Or download a model', style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
              ],
              for (final t in downloadTiers) _tierCard(c, t, advice?.tier, current),
            ],
            const SizedBox(height: 4),
            SettingRow(
              label: 'Free memory when Chat isn\'t used',
              note: 'Unloads the model after 5 minutes away from Chat, so other apps have more room. '
                  'The next message loads it again (a few seconds).',
              trailing: Toggle(
                key: const ValueKey('ai-idle-unload'),
                label: 'Free memory when Chat isn\'t used',
                value: s.settings.aiIdleUnload,
                onChanged: (v) => s.setSettings(s.settings.copyWith(aiIdleUnload: v)),
              ),
            ),
            if (downloads)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy == null && (device?.supported ?? true) ? _import : null,
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: const Text('Import a model file instead'),
              ),
            ),
          ],
          if (widget.onSkip != null) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                key: const ValueKey('ai-skip'),
                onPressed: widget.onSkip,
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: const Text('Skip for now (paste recipes and workouts without AI)'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// The same, as a page (from Settings or the Chat header).
class AiSetupScreen extends StatelessWidget {
  const AiSetupScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const AiSetupScreen());

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, elevation: 0, foregroundColor: c.text),
      body: const SafeArea(top: false, child: AiSetupView()),
    );
  }
}

/// The privacy promise, shown when setting up and in Chat.
class AiPrivacyNote extends StatelessWidget {
  const AiPrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: c.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: AppText.body(c).copyWith(fontSize: 14, height: 1.35))),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: c.accent.withAlpha(24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.accent.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(Icons.wifi_off_rounded, 'No internet needed once a model is downloaded.'),
          line(Icons.lock_outline_rounded, 'Everything stays on this phone: the AI never sends what you type or log anywhere.'),
        ],
      ),
    );
  }
}
