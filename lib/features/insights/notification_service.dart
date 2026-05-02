import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'payee_pattern.dart';

// ---------------------------------------------------------------------------
// Notification IDs
// ---------------------------------------------------------------------------

// IDs 2000–2099 reserved for payee-pattern reminders
const _kBaseId = 2000;
const _kMaxSlots = 20; // max concurrent pattern notifications

// ---------------------------------------------------------------------------
// NotificationService — singleton
// ---------------------------------------------------------------------------

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ── Initialise once at app start ──────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit  = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS:     darwinInit,
        macOS:   darwinInit,
      ),
    );

    // Android 13+ — request POST_NOTIFICATIONS permission
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  // ── Schedule / refresh pattern notifications (Path B) ────────────────────

  Future<void> schedulePatternNotifications(
      List<PayeePattern> patterns) async {
    if (!_initialized) return;

    // Cancel all existing pattern notifications
    for (var i = _kBaseId; i < _kBaseId + _kMaxSlots; i++) {
      await _plugin.cancel(i);
    }

    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    var id = _kBaseId;

    for (final pattern in patterns) {
      if (id >= _kBaseId + _kMaxSlots) break;
      if (pattern.typicalDayOfWeek == null) continue;

      // Notify the evening BEFORE their typical shopping day (8 pm)
      final notifyDay = pattern.typicalDayOfWeek! == DateTime.monday
          ? DateTime.sunday
          : pattern.typicalDayOfWeek! - 1;

      final title = '${pattern.payeeName} tomorrow? 🛒';
      final body  = _buildBody(pattern, fmt);

      try {
        await _plugin.zonedSchedule(
          id++,
          title,
          body,
          _nextWeekdayAt(notifyDay, 20, 0),
          NotificationDetails(
            android: AndroidNotificationDetails(
              'payee_patterns',
              'Shopping Reminders',
              channelDescription:
                  'Budget nudges before your regular shopping trips',
              importance: Importance.defaultImportance,
              priority:   Priority.defaultPriority,
            ),
            iOS:   const DarwinNotificationDetails(),
            macOS: const DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      } catch (_) {
        // Scheduling can fail on some emulators/OS versions — silently skip
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _buildBody(PayeePattern p, NumberFormat fmt) {
    final base =
        '${p.visitsThisMonth}× this month · avg ${fmt.format(p.avgSpend)}/visit';
    if (p.projectedVisitsLeft != null && p.projectedVisitsLeft! > 0) {
      return '$base · ~${p.projectedVisitsLeft} visit${p.projectedVisitsLeft == 1 ? '' : 's'} left this month. Open app for your spend target.';
    }
    return '$base. Open the app to see your budget.';
  }

  /// Returns the next occurrence of [weekday] (1=Mon…7=Sun) at [hour]:[minute]
  /// in the device's local timezone, always in the future.
  tz.TZDateTime _nextWeekdayAt(int weekday, int hour, int minute) {
    final loc = tz.local;
    final now = tz.TZDateTime.now(loc);
    var scheduled =
        tz.TZDateTime(loc, now.year, now.month, now.day, hour, minute);

    // Advance day-by-day until we hit the right weekday in the future
    var safety = 0;
    while ((scheduled.weekday != weekday || !scheduled.isAfter(now)) &&
        safety < 8) {
      scheduled = scheduled.add(const Duration(days: 1));
      safety++;
    }
    return scheduled;
  }
}
