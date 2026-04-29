import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'sms_parser.dart';

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------

/// '/transactions' when the app was cold-started from a notification tap.
String? smsInitialLocation;

/// Fires when a bank SMS arrives while the app is in the foreground.
final pendingSmsNotifier = ValueNotifier<ParsedSms?>(null);

// ---------------------------------------------------------------------------
// SmsService
// ---------------------------------------------------------------------------

abstract final class SmsService {
  static const _channel = MethodChannel('mybudga/sms');
  static const _events  = EventChannel('mybudga/sms_stream');
  static StreamSubscription? _streamSub;

  static Future<void> init() async {
    // Check if the activity was opened by a notification tap.
    // If so, set smsInitialLocation and kick the router to re-redirect.
    try {
      final route = await _channel.invokeMethod<String>('getInitialRoute');
      if (route == '/transactions') smsInitialLocation = '/transactions';
    } catch (_) {}

    // Resume stream only if SMS was previously enabled by the user
    if (await isEnabled()) _startStream();
  }

  static Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isSmsEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enables SMS feature. Requests permission first.
  /// Returns true on success, false if permission was denied.
  static Future<bool> enable() async {
    final status = await Permission.sms.request();
    if (!status.isGranted) return false;
    await _channel.invokeMethod('setSmsEnabled', true);
    _startStream();
    return true;
  }

  /// Disables SMS feature — stops the stream and clears the native flag.
  static Future<void> disable() async {
    await _channel.invokeMethod('setSmsEnabled', false);
    await _streamSub?.cancel();
    _streamSub = null;
  }

  static void _startStream() {
    _streamSub?.cancel();
    _streamSub = _events.receiveBroadcastStream().listen((data) {
      if (data is! Map) return;
      final parsed = SmsParser.parse(
        data['body']   as String? ?? '',
        sender: data['sender'] as String?,
      );
      if (parsed != null) pendingSmsNotifier.value = parsed;
    });
  }

  /// Returns and clears all pending bank SMS that arrived while the app was
  /// in the background (stored natively in Android SharedPreferences).
  static Future<List<ParsedSms>> takePending() async {
    if (!await isEnabled()) return [];
    try {
      final json = await _channel.invokeMethod<String>('takePending') ?? '[]';
      final arr  = jsonDecode(json) as List<dynamic>;
      return arr
          .map((e) {
            final m = e as Map<String, dynamic>;
            return SmsParser.parse(
              m['body']   as String? ?? '',
              sender: m['sender'] as String?,
            );
          })
          .whereType<ParsedSms>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
