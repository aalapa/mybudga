import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_lock_provider.dart';

// ---------------------------------------------------------------------------
// Lock screen — shown as a full-screen overlay when app is locked
// ---------------------------------------------------------------------------

class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  static const _len = 6;
  final _digits = <int>[];
  bool _error   = false;
  bool _bioWait = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBio());
  }

  Future<void> _tryBio() async {
    if (_bioWait) return;
    setState(() => _bioWait = true);
    await ref.read(appLockProvider.notifier).tryBiometric();
    if (mounted) setState(() => _bioWait = false);
  }

  void _tap(int d) {
    if (_digits.length >= _len) return;
    setState(() { _digits.add(d); _error = false; });
    if (_digits.length == _len) _submit();
  }

  void _del() {
    if (_digits.isEmpty) return;
    setState(() => _digits.removeLast());
  }

  Future<void> _submit() async {
    final ok = await ref.read(appLockProvider.notifier).tryPin(_digits.join());
    if (!ok && mounted) {
      HapticFeedback.heavyImpact();
      setState(() { _digits.clear(); _error = true; });
    }
  }

  Future<void> _signOut() async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Signing out will clear your PIN. You can set it up again after signing back in.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(appLockProvider.notifier).disableLock();
      await Supabase.instance.client.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final lock = ref.watch(appLockProvider);
    final hasBio = lock.biometricAvailable && lock.biometricEnabled;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            const Spacer(flex: 2),
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.lock_rounded, size: 32, color: cs.primary),
            ),
            const SizedBox(height: 16),
            Text('MyBudga',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _error ? 'Incorrect PIN — try again' : 'Enter your PIN',
                key: ValueKey(_error),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: _error ? cs.error : cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 28),

            // ── PIN dots ─────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_len, (i) {
                final filled = i < _digits.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? (_error ? cs.error : cs.primary)
                        : cs.onSurface.withValues(alpha: 0.18),
                    border: filled
                        ? null
                        : Border.all(
                            color: cs.onSurface.withValues(alpha: 0.25)),
                  ),
                );
              }),
            ),

            const Spacer(flex: 3),

            // ── Number pad ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in [
                    [1, 2, 3],
                    [4, 5, 6],
                    [7, 8, 9],
                  ]) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: row
                          .map((d) => _DigitKey(d, onTap: () => _tap(d)))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Bottom row: bio | 0 | backspace
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      hasBio
                          ? _IconKey(
                              Icons.fingerprint_rounded,
                              onTap: _tryBio,
                            )
                          : const SizedBox(width: 72, height: 72),
                      _DigitKey(0, onTap: () => _tap(0)),
                      _IconKey(
                        Icons.backspace_outlined,
                        onTap: _del,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(flex: 1),

            // ── Footer ───────────────────────────────────────────────────
            TextButton(
              onPressed: _signOut,
              child: Text(
                'Forgot PIN? Sign out',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Key widgets
// ---------------------------------------------------------------------------

class _DigitKey extends StatelessWidget {
  final int digit;
  final VoidCallback onTap;
  const _DigitKey(this.digit, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 72, height: 72,
          child: Center(
            child: Text(
              '$digit',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w400,
                  color: cs.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconKey extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconKey(this.icon, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 72, height: 72,
        child: Icon(icon, size: 26, color: cs.onSurfaceVariant),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PIN setup / change sheet  (called from Settings)
// ---------------------------------------------------------------------------

enum _PinSetupMode { setup, change }

void showPinSetupSheet(BuildContext context, WidgetRef ref,
    {bool isChange = false}) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    useSafeArea:        true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _PinSetupSheet(
      mode: isChange ? _PinSetupMode.change : _PinSetupMode.setup,
      widgetRef: ref,
    ),
  );
}

class _PinSetupSheet extends ConsumerStatefulWidget {
  final _PinSetupMode mode;
  final WidgetRef widgetRef;
  const _PinSetupSheet({required this.mode, required this.widgetRef});

  @override
  ConsumerState<_PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends ConsumerState<_PinSetupSheet> {
  static const _len = 6;
  final _first  = <int>[];
  final _second = <int>[];
  bool _confirming = false;
  bool _mismatch   = false;
  bool _saving     = false;

  List<int> get _active => _confirming ? _second : _first;

  void _tap(int d) {
    if (_active.length >= _len) return;
    setState(() { _active.add(d); _mismatch = false; });
    if (_active.length == _len) {
      if (!_confirming) {
        setState(() => _confirming = true);
      } else {
        _save();
      }
    }
  }

  void _del() {
    if (_active.isEmpty) {
      if (_confirming) setState(() { _confirming = false; _second.clear(); });
      return;
    }
    setState(() => _active.removeLast());
  }

  Future<void> _save() async {
    if (_first.join() != _second.join()) {
      HapticFeedback.heavyImpact();
      setState(() { _confirming = false; _first.clear(); _second.clear(); _mismatch = true; });
      return;
    }
    setState(() => _saving = true);
    final pin = _first.join();
    final notifier = ref.read(appLockProvider.notifier);
    if (widget.mode == _PinSetupMode.setup) {
      await notifier.enableLock(pin);
    } else {
      await notifier.changePin(pin);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dots = _active;

    final title = _confirming
        ? 'Confirm your PIN'
        : widget.mode == _PinSetupMode.change
            ? 'Enter new PIN'
            : 'Set a 6-digit PIN';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _mismatch ? 'PINs didn\'t match — try again' : title,
              key: ValueKey('$_confirming$_mismatch'),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _mismatch ? cs.error : cs.onSurface),
            ),
          ),
          const SizedBox(height: 24),

          // Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_len, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 14, height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < dots.length
                    ? (_mismatch ? cs.error : cs.primary)
                    : cs.onSurface.withValues(alpha: 0.18),
                border: i < dots.length
                    ? null
                    : Border.all(color: cs.onSurface.withValues(alpha: 0.25)),
              ),
            )),
          ),
          const SizedBox(height: 28),

          // Number pad
          for (final row in [[1,2,3],[4,5,6],[7,8,9]]) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((d) => _DigitKey(d, onTap: () => _tap(d))).toList(),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 72, height: 72),
              _DigitKey(0, onTap: () => _tap(0)),
              _IconKey(Icons.backspace_outlined, onTap: _del),
            ],
          ),
        ],
      ),
    );
  }
}
