import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/theme/theme_provider.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _kEnabled   = 'app_lock_enabled';
const _kBiometric = 'app_lock_biometric';
const _kPinKey    = 'app_lock_pin_hash';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum AppLockStatus { disabled, locked, unlocked }

class AppLockState {
  final AppLockStatus status;
  final bool          biometricAvailable;
  final bool          biometricEnabled;

  const AppLockState({
    this.status             = AppLockStatus.disabled,
    this.biometricAvailable = false,
    this.biometricEnabled   = true,
  });

  bool get isEnabled => status != AppLockStatus.disabled;
  bool get isLocked  => status == AppLockStatus.locked;

  AppLockState copyWith({
    AppLockStatus? status,
    bool? biometricAvailable,
    bool? biometricEnabled,
  }) => AppLockState(
        status:             status             ?? this.status,
        biometricAvailable: biometricAvailable ?? this.biometricAvailable,
        biometricEnabled:   biometricEnabled   ?? this.biometricEnabled,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class AppLockNotifier extends StateNotifier<AppLockState> {
  AppLockNotifier(this._prefs) : super(const AppLockState()) {
    _init();
  }

  final dynamic _prefs; // SharedPreferences
  static const _storage = FlutterSecureStorage();
  final _auth           = LocalAuthentication();

  Future<void> _init() async {
    final enabled    = (_prefs.getBool(_kEnabled)   ?? false) as bool;
    final bioEnabled = (_prefs.getBool(_kBiometric) ?? true)  as bool;
    var bioAvail = false;
    try {
      bioAvail = await _auth.canCheckBiometrics ||
                 await _auth.isDeviceSupported();
    } catch (_) {}

    state = AppLockState(
      status:             enabled ? AppLockStatus.locked : AppLockStatus.disabled,
      biometricAvailable: bioAvail,
      biometricEnabled:   bioEnabled,
    );

    if (enabled && bioAvail && bioEnabled) {
      tryBiometric().ignore();
    }
  }

  /// Called when the app returns from background after the timeout.
  void lock() {
    if (!state.isEnabled) return;
    state = state.copyWith(status: AppLockStatus.locked);
  }

  Future<bool> tryBiometric() async {
    if (!state.biometricAvailable || !state.biometricEnabled) return false;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Authenticate to access MyBudga',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth:    true,
        ),
      );
      if (ok) state = state.copyWith(status: AppLockStatus.unlocked);
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> tryPin(String pin) async {
    final stored = await _storage.read(key: _kPinKey);
    if (stored == null) return false;
    final ok = _hash(pin) == stored;
    if (ok) state = state.copyWith(status: AppLockStatus.unlocked);
    return ok;
  }

  Future<void> enableLock(String pin) async {
    await _storage.write(key: _kPinKey, value: _hash(pin));
    await _prefs.setBool(_kEnabled, true);
    state = state.copyWith(status: AppLockStatus.locked);
  }

  Future<void> disableLock() async {
    await _storage.delete(key: _kPinKey);
    await _prefs.setBool(_kEnabled, false);
    state = state.copyWith(status: AppLockStatus.disabled);
  }

  Future<void> changePin(String newPin) async {
    await _storage.write(key: _kPinKey, value: _hash(newPin));
  }

  Future<void> setBiometricEnabled(bool value) async {
    await _prefs.setBool(_kBiometric, value);
    state = state.copyWith(biometricEnabled: value);
  }

  static String _hash(String pin) =>
      sha256.convert(utf8.encode(pin)).toString();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final appLockProvider =
    StateNotifierProvider<AppLockNotifier, AppLockState>((ref) {
  return AppLockNotifier(ref.watch(sharedPreferencesProvider));
});
