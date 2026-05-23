import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import '../../shared/models/account.dart';
import '../../shared/models/scheduled_transaction.dart';
import 'payee_pattern.dart';

// ---------------------------------------------------------------------------
// Notification IDs
// ---------------------------------------------------------------------------

// IDs 2000–2099 reserved for payee-pattern reminders
const _kBaseId    = 2000;
const _kMaxSlots  = 20;
// IDs 3000–3099 reserved for bill-due reminders (max 100 scheduled transactions)
const _kBillBase  = 3000;
const _kBillSlots = 100;
// IDs 4000–4049 reserved for CC due T-3 warnings  (max 50 CC accounts)
// IDs 4050–4099 reserved for CC due T-0 reminders (max 50 CC accounts)
const _kCcBase  = 4000;
const _kCcSlots = 50;

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

  // ── Bill-due reminders ───────────────────────────────────────────────────

  static int _billNotifId(String scheduledTxId) =>
      _kBillBase + (scheduledTxId.hashCode.abs() % _kBillSlots);

  Future<void> scheduleBillReminder({
    required String scheduledTxId,
    required String payee,
    required double amount,
    required DateTime dueDate,
  }) async {
    if (!_initialized) return;
    try {
      final id  = _billNotifId(scheduledTxId);
      await _plugin.cancel(id);

      // Fire at 9 am the day before the due date.
      final loc         = tz.local;
      final reminderDay = dueDate.subtract(const Duration(days: 1));
      final scheduled   = tz.TZDateTime(
          loc, reminderDay.year, reminderDay.month, reminderDay.day, 9, 0);
      if (!scheduled.isAfter(tz.TZDateTime.now(loc))) return;

      final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
      await _plugin.zonedSchedule(
        id,
        'Bill due tomorrow',
        '$payee · ${fmt.format(amount.abs())} due tomorrow',
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'bill_reminders',
            'Bill Reminders',
            channelDescription: 'Reminders for upcoming bill payments',
            importance: Importance.high,
            priority:   Priority.high,
          ),
          iOS:   const DarwinNotificationDetails(),
          macOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  Future<void> cancelBillReminder(String scheduledTxId) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_billNotifId(scheduledTxId));
    } catch (_) {}
  }

  /// Cancel all known bill reminders then reschedule for active entries
  /// where [enabledIds] contains the scheduled transaction id.
  Future<void> rescheduleAllBillReminders(
    List<ScheduledTransaction> scheduled,
    Set<String> enabledIds,
  ) async {
    if (!_initialized) return;
    for (final st in scheduled) {
      await cancelBillReminder(st.id);
    }
    for (final st in scheduled) {
      if (!st.isActive || !enabledIds.contains(st.id)) continue;
      await scheduleBillReminder(
        scheduledTxId: st.id,
        payee:         st.payeeName ?? st.memo ?? 'Bill',
        amount:        st.amount,
        dueDate:       st.nextDate,
      );
    }
  }

  // ── Credit-card due reminders ────────────────────────────────────────────

  static int _ccWarningId(String accountId) =>
      _kCcBase + (accountId.hashCode.abs() % _kCcSlots);
  static int _ccDueId(String accountId) =>
      _kCcBase + _kCcSlots + (accountId.hashCode.abs() % _kCcSlots);

  /// Cancels then reschedules CC due notifications for every active,
  /// unpaid credit-card / line-of-credit account in [accounts].
  ///
  /// Schedules two notifications per qualifying account:
  ///   • T-3: 9 AM three days before next due date  — "due in 3 days"
  ///   • T-0: 9 AM on the due date itself           — "due today"
  ///
  /// An account is considered paid when its balance ≥ 0 OR a positive
  /// transaction exists within 21 days before the last due date.
  Future<void> rescheduleCcDueReminders(
    List<Account> accounts,
    Map<String, DateTime> creditDates,
  ) async {
    if (!_initialized) return;

    // Cancel all CC slots first.
    for (var i = _kCcBase; i < _kCcBase + _kCcSlots * 2; i++) {
      await _plugin.cancel(i);
    }

    final now = DateTime.now();
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    for (final account in accounts) {
      if (!account.isActive) continue;
      final t = account.type;
      if (t != AccountType.creditCard && t != AccountType.lineOfCredit) continue;
      if (account.dueDay == null) continue;
      if (account.balance >= 0) continue; // nothing owed

      // 21-day payment window — mirrors _dueStatus() in accounts_screen.dart
      final lastDue = account.dueDay! <= now.day
          ? DateTime(now.year, now.month, account.dueDay!)
          : DateTime(now.year, now.month - 1, account.dueDay!);
      final windowStart = lastDue.subtract(const Duration(days: 21));
      final lastCredit  = creditDates[account.id];
      final hasPaid     = lastCredit != null && !lastCredit.isBefore(windowStart);
      if (hasPaid) continue; // paid this cycle — no notification needed

      // Next upcoming due date.
      final nextDue = account.dueDay! >= now.day
          ? DateTime(now.year, now.month, account.dueDay!)
          : DateTime(now.year, now.month + 1, account.dueDay!);

      final name   = account.displayName;
      final amount = fmt.format(account.balance.abs());
      final dateLabel = _shortDate(nextDue);

      // T-3 — "due in 3 days"
      await _scheduleCcNotif(
        id:    _ccWarningId(account.id),
        fireAt: nextDue.subtract(const Duration(days: 3)),
        title: '$name due in 3 days',
        body:  'Payment of $amount due $dateLabel. Pay on time to avoid charges.',
      );

      // T-0 — "due today"
      await _scheduleCcNotif(
        id:    _ccDueId(account.id),
        fireAt: nextDue,
        title: '$name payment due today',
        body:  '$amount due today. Open MyBudga to record your payment.',
      );
    }
  }

  Future<void> _scheduleCcNotif({
    required int      id,
    required DateTime fireAt,
    required String   title,
    required String   body,
  }) async {
    final loc       = tz.local;
    final scheduled = tz.TZDateTime(
        loc, fireAt.year, fireAt.month, fireAt.day, 9, 0);
    // Skip silently if the fire time is already in the past.
    if (!scheduled.isAfter(tz.TZDateTime.now(loc))) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'cc_due_reminders',
            'Credit Card Due Reminders',
            channelDescription:
                'Alerts before and on a credit card payment due date',
            importance: Importance.high,
            priority:   Priority.high,
          ),
          iOS:   const DarwinNotificationDetails(),
          macOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  static String _shortDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
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
