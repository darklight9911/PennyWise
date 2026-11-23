import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/router/app_router.dart';
import '../../../core/utils/money.dart';
import '../../ledger/application/ledger_providers.dart';
import '../../ledger/data/ledger_store.dart';
import '../presentation/due_style.dart';

/// Reminders fire at this local hour on the reminder date.
const reminderHour = 9;

/// One planned notification.
@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.dueId,
  });

  /// Stable per due, so rescheduling replaces it.
  final int id;

  /// Local wall-clock time.
  final DateTime at;
  final String title;
  final String body;
  final String dueId;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.at == at &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, at, title, body);
}

/// A 31-bit id from a due id (FNV-1a), the same on every run.
int reminderIdFor(String dueId) {
  var h = 0x811c9dc5;
  for (final c in dueId.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// Which notifications should exist now: one per open due with a
/// reminder whose time is still ahead.
List<PlannedReminder> planDueReminders(List<DueProgress> dues, DateTime now) {
  final out = <PlannedReminder>[];
  for (final p in dues) {
    final date = p.reminderDate;
    if (date == null) continue;
    final d = DateTime.parse(date);
    final at = DateTime(d.year, d.month, d.day, reminderHour);
    if (!at.isAfter(now)) continue;
    final due = p.due;
    final left = '${formatMinor(p.leftMinor, due.currency)} ${due.currency}';
    final days = due.remindDaysBefore ?? 0;
    final when = days == 0
        ? 'today'
        : days == 1
        ? 'tomorrow'
        : 'in $days days';
    out.add(
      PlannedReminder(
        id: reminderIdFor(due.id),
        at: at,
        dueId: due.id,
        title: due.direction == DueDirection.owedToMe
            ? '${due.person} owes you $left'
            : 'You owe ${due.person} $left',
        body: 'Due $when (${dueDateLabel(due.dueDate!)}).',
      ),
    );
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// The phone's notification system. Tests use a fake.
abstract class ReminderPlatform {
  /// [onOpen] gets the due id of a tapped reminder.
  Future<void> init(void Function(String dueId) onOpen);

  /// Asks the user to allow notifications. True if allowed.
  Future<bool> requestPermission();
  Future<void> cancelAll();
  Future<void> schedule(PlannedReminder r);
}

class LocalReminderPlatform implements ReminderPlatform {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'due_reminders',
      'Due reminders',
      channelDescription: 'Reminders before money you owe or are owed is due',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> init(void Function(String dueId) onOpen) async {
    tzdata.initializeTimeZones();
    try {
      final name = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(name));
    } on Object {
      // Unknown zone: tz.local stays UTC; reminders may be off by hours.
    }
    void open(NotificationResponse r) {
      final id = r.payload;
      if (id != null && id.isNotEmpty) onOpen(id);
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: open,
    );
    _ready = true;
    // Opened by tapping a reminder while the app was closed.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
      open(response);
    }
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  @override
  Future<void> cancelAll() async {
    if (_ready) await _plugin.cancelAll();
  }

  @override
  Future<void> schedule(PlannedReminder r) async {
    if (!_ready) {
      return;
    }
    await _plugin.zonedSchedule(
      id: r.id,
      title: r.title,
      body: r.body,
      payload: r.dueId,
      scheduledDate: tz.TZDateTime(
        tz.local,
        r.at.year,
        r.at.month,
        r.at.day,
        r.at.hour,
        r.at.minute,
      ),
      notificationDetails: _details,
      // Inexact: no special alarm permission, and a few minutes late is fine.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}

final reminderPlatformProvider = Provider<ReminderPlatform>(
  (ref) => LocalReminderPlatform(),
);

/// Clock for planning. Tests replace it.
final reminderClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Keeps the phone's scheduled reminders in step with the dues: whenever
/// they change, all due reminders are replaced. Logging out empties the
/// dues, which cancels them all.
class DueReminders {
  DueReminders(this.ref) {
    unawaited(_start());
  }

  final Ref ref;
  List<PlannedReminder>? _last;
  Future<void> _queue = Future.value();

  Future<void> _start() async {
    try {
      await ref.read(reminderPlatformProvider).init((dueId) {
        ref.read(routerProvider).push(Routes.due(dueId));
      });
    } on Object catch (e) {
      debugPrint('Due reminders unavailable: $e');
      return;
    }
    // Only while someone's data is open (a guest or a user): before that
    // there is no database to read, and a change of owner (log out, other
    // user) must drop the old reminders first.
    ref.listen<String?>(dataOwnerProvider, (prev, next) {
      _dues?.close();
      _dues = null;
      if (prev != null && next != prev) _apply(const []);
      if (next == null) return;
      _dues = ref.listen(duesProvider, (_, d) {
        final dues = d.value;
        if (dues != null) _apply(dues);
      }, fireImmediately: true);
    }, fireImmediately: true);
  }

  ProviderSubscription<AsyncValue<List<DueProgress>>>? _dues;

  void _apply(List<DueProgress> dues) {
    final plan = planDueReminders(dues, ref.read(reminderClockProvider)());
    if (listEquals(plan, _last)) {
      return;
    }
    _last = plan;
    final platform = ref.read(reminderPlatformProvider);
    // One change at a time, so a fast second change never interleaves.
    _queue = _queue.then((_) async {
      try {
        await platform.cancelAll();
        for (final r in plan) {
          await platform.schedule(r);
        }
      } on Object catch (e) {
        debugPrint('Could not schedule reminders: $e');
      }
    });
  }
}

final dueRemindersProvider = Provider<DueReminders>(DueReminders.new);
