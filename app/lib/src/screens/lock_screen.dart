import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/unlocker.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Covers the app until the PIN or a fingerprint unlocks it.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.unlocker, required this.onUnlocked});

  final Unlocker unlocker;
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _message;
  int _wrong = 0;
  DateTime? _waitUntil;
  bool _biometric = false;
  bool _asking = false;
  bool _forgot = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setUp());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _setUp() async {
    final s = AppScope.of(context);
    if (!s.settings.lockBiometric) return;
    final ok = await widget.unlocker.available();
    if (!mounted) return;
    setState(() => _biometric = ok);
    if (ok) _fingerprint();
  }

  Future<void> _fingerprint() async {
    if (_asking) return;
    _asking = true;
    final ok = await widget.unlocker.authenticate();
    _asking = false;
    if (ok && mounted) widget.onUnlocked();
  }

  bool get _waiting {
    final w = _waitUntil;
    return w != null && DateTime.now().isBefore(w);
  }

  void _press(String key) {
    if (_waiting) return;
    HapticFeedback.selectionClick();
    setState(() {
      _message = null;
      if (key == 'del') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 8) {
        _pin += key;
      }
    });
  }

  void _submit() {
    if (_waiting || _pin.length < 4) return;
    final s = AppScope.of(context);
    if (s.checkPin(_pin, hashPin)) {
      HapticFeedback.mediumImpact();
      widget.onUnlocked();
      return;
    }
    HapticFeedback.heavyImpact();
    _wrong++;
    setState(() {
      _pin = '';
      if (_wrong >= 5) {
        _waitUntil = DateTime.now().add(const Duration(seconds: 30));
        _wrong = 0;
        _message = 'Too many tries. Wait 30 seconds.';
        _tick?.cancel();
        _tick = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) return;
          if (!_waiting) {
            t.cancel();
            setState(() => _message = null);
          } else {
            setState(() {});
          }
        });
      } else {
        _message = 'Wrong PIN';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'bio', '0', 'del'];
    final left = _waiting ? _waitUntil!.difference(DateTime.now()).inSeconds + 1 : 0;

    return Material(
      color: c.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 36, color: c.accent),
                  const SizedBox(height: 12),
                  Text('Pump and Plate is locked', style: AppText.title(c).copyWith(fontSize: 24)),
                  const SizedBox(height: 6),
                  Text(
                    _waiting ? 'Try again in $left s' : (_message ?? 'Enter your PIN'),
                    style: AppText.quiet(c).copyWith(
                      color: _message != null ? c.protein : c.muted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < (_pin.length < 4 ? 4 : _pin.length); i++)
                        Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _pin.length ? c.text : Colors.transparent,
                            border: Border.all(color: c.text, width: 1.5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.5,
                    children: [
                      for (final k in keys)
                        if (k == 'bio' && !_biometric)
                          const SizedBox.shrink()
                        else
                          Semantics(
                            button: true,
                            label: k == 'del'
                                ? 'Delete'
                                : (k == 'bio' ? 'Use fingerprint' : k),
                            child: GestureDetector(
                              onTap: () => k == 'bio' ? _fingerprint() : _press(k),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: k == 'del'
                                    ? Icon(Icons.backspace_outlined, color: c.text)
                                    : (k == 'bio'
                                        ? Icon(Icons.fingerprint_rounded, color: c.accent, size: 30)
                                        : Text(
                                            k,
                                            style: AppText.body(c).copyWith(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          )),
                              ),
                            ),
                          ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _pin.length >= 4 && !_waiting ? _submit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: c.onAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Unlock', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_forgot)
                    Text(
                      'The PIN can\'t be recovered, since only a scrambled code of it '
                      'is stored. To get back in, uninstall and reinstall Pump and Plate, '
                      'then restore your latest backup from Settings > Your data.',
                      textAlign: TextAlign.center,
                      style: AppText.quiet(c),
                    )
                  else
                    TextButton(
                      onPressed: () => setState(() => _forgot = true),
                      style: TextButton.styleFrom(foregroundColor: c.muted),
                      child: const Text('Forgot PIN?'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
