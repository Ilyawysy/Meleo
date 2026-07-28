import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import '../models/notification.dart' as notification_model;
import '../data/notification_db.dart';
import '../../../core/models/recurrence.dart';
import '../../../core/id_generator.dart';
import '../../../core/preferences/settings_preferences.dart';

// Top-level функция для обработки фоновых уведомлений
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  if (response.id != null) {
    LocalNotificationService().handleNotificationShown(response.id!);
  }
}

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initFuture;
  Timer? _checkTimer;

  Future<void> initialize() async {
    if (_initialized) return;
    // Prevent concurrent initialization (e.g. sync_bridge + onboarding
    // both calling initialize() before the first one completes).
    if (_initFuture != null) {
      await _initFuture;
      return;
    }
    _initFuture = _doInitialize();
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _doInitialize() async {

    debugPrint('🔔 [LocalNotification] Initializing...');

    // Инициализация timezone
    tz.initializeTimeZones();

    // Создаем канал уведомлений для Android ПЕРЕД инициализацией
    final androidImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImplementation != null) {
      // Создаем канал уведомлений с высоким приоритетом
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'notifications_channel',
          'Уведомления',
          description: 'Уведомления о событиях',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );
      debugPrint('📱 [LocalNotification] Notification channel created');

      // Check if notifications are already enabled before requesting
      final areEnabled = await androidImplementation.areNotificationsEnabled();
      debugPrint(
        '📱 [LocalNotification] areNotificationsEnabled() result: $areEnabled',
      );

      // Only request permission if not already granted (Android 13+)
      if (areEnabled != true) {
        final granted = await androidImplementation
            .requestNotificationsPermission();
        debugPrint(
          '📱 [LocalNotification] requestNotificationsPermission() result: $granted',
        );
      }

      // Запрашиваем разрешение на exact alarms (Android 12+)
      try {
        final exactAlarmsGranted = await androidImplementation
            .requestExactAlarmsPermission();
        debugPrint(
          '📱 [LocalNotification] requestExactAlarmsPermission() result: $exactAlarmsGranted',
        );
      } catch (e) {
        debugPrint(
          '⚠️ [LocalNotification] requestExactAlarmsPermission() error (may not be available): $e',
        );
      }
    }

    // Настройка для Android
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // Настройка для iOS
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    _initialized = true;
    debugPrint('✅ [LocalNotification] Initialized successfully');

    // Перепланировать все уведомления при старте
    await rescheduleAllNotifications();

    // Запустить периодическую проверку показанных уведомлений
    _startPeriodicCheck();
  }

  void _startPeriodicCheck() {
    _checkTimer?.cancel();
    // Проверяем каждые 5 секунд, какие уведомления нужно пометить как sent
    // Это позволяет быстро удалять уведомления из UI после их показа
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _checkAndMarkSentNotifications();
    });
  }

  Future<void> _checkAndMarkSentNotifications() async {
    final db = NotificationDb();
    final notifications = await db.list(limit: 1000);
    final now = DateTime.now();

    // Проверяем запланированные уведомления в системе
    final pendingNotifications = await _notifications
        .pendingNotificationRequests();

    // Помечаем как sent только если:
    // 1. Время уведомления прошло
    // 2. Уведомление больше не в списке запланированных (значит было показано системой)
    for (final notification in notifications) {
      if (notification.sent) continue;

      final notificationId = (notification.id.hashCode & 0x7FFFFFFF);
      final isPending = pendingNotifications.any((n) => n.id == notificationId);

      // Если время прошло и уведомление больше не в pending - значит было показано
      if (notification.time.isBefore(now) && !isPending) {
        await markAsSent(notification.id);

        // Если это повторяющееся уведомление, планируем следующее
        if (notification.recurrence != Recurrence.none) {
          await scheduleRecurringNotification(notification);
        }
      }
    }
  }

  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _initialized = false;
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Обработка нажатия на уведомление
    debugPrint('🔔 [LocalNotification] Notification tapped: ID=${response.id}');

    // Когда уведомление показано и пользователь нажал на него,
    // помечаем как sent (если это не повторяющееся)
    if (response.id != null) {
      handleNotificationShown(response.id!);
    }
  }

  Future<void> scheduleNotification(
    notification_model.Notification notification,
  ) async {
    if (!_initialized) await initialize();

    debugPrint(
      '📅 [LocalNotification] scheduleNotification called for: ${notification.title} (ID: ${notification.id})',
    );

    // Проверяем глобальный переключатель уведомлений
    final notificationsEnabled =
        await SettingsPreferences.getNotificationsEnabled();
    if (!notificationsEnabled) {
      debugPrint(
        '⏭️ [LocalNotification] Notifications disabled globally, skipping: ${notification.title}',
      );
      return;
    }

    // Пропускаем уже отправленные уведомления
    if (notification.sent) {
      debugPrint(
        '⏭️ [LocalNotification] Skipping sent notification: ${notification.title}',
      );
      return;
    }

    final now = DateTime.now();

    // Пропускаем уведомления в прошлом (если не повторяющиеся)
    if (notification.time.isBefore(now)) {
      debugPrint(
        '⏭️ [LocalNotification] Skipping past notification: ${notification.title} (time: ${notification.time}, now: $now)',
      );
      // Если это повторяющееся уведомление, планируем следующее
      if (notification.recurrence != Recurrence.none) {
        await scheduleRecurringNotification(notification);
      }
      return;
    }

    // Используем хеш ID для безопасного преобразования в int (32-bit)
    // Оставляем только положительные числа используя & 0x7FFFFFFF
    final id = (notification.id.hashCode & 0x7FFFFFFF);

    DateTimeComponents? dateTimeComponents;
    if (notification.recurrence == Recurrence.daily) {
      dateTimeComponents = DateTimeComponents.time;
    } else if (notification.recurrence == Recurrence.weekly) {
      dateTimeComponents = DateTimeComponents.dayOfWeekAndTime;
    }

    // ВАЖНО: Преобразуем время правильно
    // notification.time может быть в UTC или локальном времени
    // Нужно убедиться, что мы используем локальное время для планирования
    DateTime localTime;
    if (notification.time.isUtc) {
      // Если время в UTC, конвертируем в локальное
      localTime = notification.time.toLocal();
    } else {
      // Если уже локальное, используем как есть
      localTime = notification.time;
    }

    final scheduledTime = tz.TZDateTime.from(localTime, tz.local);

    // Проверяем тихие часы
    final quietHoursEnabled =
        await SettingsPreferences.getQuietHoursEnabled();
    if (quietHoursEnabled) {
      final startStr = await SettingsPreferences.getQuietHoursStart();
      final endStr = await SettingsPreferences.getQuietHoursEnd();
      if (_isInQuietHours(localTime, startStr, endStr)) {
        debugPrint(
          '⏭️ [LocalNotification] Quiet hours active, skipping: ${notification.title}',
        );
        return;
      }
    }

    final sound = await SettingsPreferences.getNotificationsSound();
    final vibration = await SettingsPreferences.getNotificationsVibration();

    try {
      // Проверяем разрешения перед планированием
      final androidImplementation = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidImplementation != null) {
        final permissionGranted = await androidImplementation
            .areNotificationsEnabled();
        if (permissionGranted == false) {
          await androidImplementation.requestNotificationsPermission();
        }
      }

      await _notifications.zonedSchedule(
        id,
        notification.title,
        'Время: ${_formatTime(notification.time)}',
        scheduledTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'notifications_channel',
            'Уведомления',
            channelDescription: 'Уведомления о событиях',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: vibration,
            playSound: sound,
            showWhen: true,
            autoCancel: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: sound,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: dateTimeComponents,
      );

      // Планируем проверку сразу после времени уведомления, чтобы быстро удалить из UI
      final timeUntilNotification = scheduledTime.difference(
        tz.TZDateTime.now(tz.local),
      );
      if (timeUntilNotification.isNegative) {
        // Если время уже прошло, проверяем сразу через 2 секунды
        Future.delayed(const Duration(seconds: 2), () async {
          await _checkAndMarkSentNotifications();
        });
      } else {
        // Если время еще не наступило, проверяем через несколько секунд после времени
        Future.delayed(
          timeUntilNotification + const Duration(seconds: 2),
          () async {
            await _checkAndMarkSentNotifications();
          },
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [LocalNotification] Failed to schedule notification: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> scheduleRecurringNotification(
    notification_model.Notification notification,
  ) async {
    if (notification.recurrence == Recurrence.none) return;

    // Вычисляем следующее время
    DateTime nextTime;
    final now = DateTime.now();

    if (notification.recurrence == Recurrence.daily) {
      // Следующее время завтра в то же время
      nextTime = DateTime(
        now.year,
        now.month,
        now.day,
        notification.time.hour,
        notification.time.minute,
      ).add(const Duration(days: 1));
    } else if (notification.recurrence == Recurrence.weekly) {
      // Следующее время через неделю
      nextTime = notification.time.add(const Duration(days: 7));
      // Если время уже прошло, добавляем еще неделю
      while (nextTime.isBefore(now)) {
        nextTime = nextTime.add(const Duration(days: 7));
      }
    } else {
      return;
    }

    // Создаем новое уведомление для следующего раза
    final nextNotification = notification.copyWith(
      id: generateLocalId(),
      time: nextTime,
      sent: false,
    );

    await scheduleNotification(nextNotification);
  }

  Future<void> cancelNotification(String notificationId) async {
    // Используем безопасное преобразование ID
    final id = (notificationId.hashCode & 0x7FFFFFFF);
    debugPrint(
      '🚫 [LocalNotification] Cancelling notification with ID: $id (original: $notificationId)',
    );
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  Future<void> markAsSent(String notificationId) async {
    final db = NotificationDb();
    await db.markAsSent(notificationId);
  }

  Future<void> rescheduleAllNotifications() async {
    // Если уведомления отключены глобально — отменяем все и выходим
    final notificationsEnabled =
        await SettingsPreferences.getNotificationsEnabled();
    if (!notificationsEnabled) {
      await cancelAllNotifications();
      return;
    }

    final db = NotificationDb();
    final notifications = await db.list(limit: 1000);

    // Отменяем все старые уведомления
    await cancelAllNotifications();

    final now = DateTime.now();

    // Планируем все активные уведомления
    for (final notification in notifications) {
      if (!notification.sent && notification.time.isAfter(now)) {
        await scheduleNotification(notification);
      } else if (!notification.sent &&
          notification.recurrence != Recurrence.none) {
        // Планируем следующее повторяющееся уведомление
        await scheduleRecurringNotification(notification);
      }
    }
  }

  Future<void> scheduleDailyReminder(TimeOfDay time) async {
    if (!_initialized) await initialize();
    const int dailyReminderId = 999999999;

    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    final scheduledTime = tz.TZDateTime.from(scheduledDate, tz.local);

    final sound = await SettingsPreferences.getNotificationsSound();
    final vibration = await SettingsPreferences.getNotificationsVibration();

    await _notifications.zonedSchedule(
      dailyReminderId,
      'Незавершённые задачи',
      'Проверьте ваши задачи на сегодня',
      scheduledTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'notifications_channel',
          'Уведомления',
          channelDescription: 'Уведомления о событиях',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: vibration,
          playSound: sound,
          showWhen: true,
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: sound,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDailyReminder() async {
    await _notifications.cancel(999999999);
  }

  bool _isInQuietHours(DateTime time, String startStr, String endStr) {
    final startParts = startStr.split(':');
    final endParts = endStr.split(':');
    if (startParts.length != 2 || endParts.length != 2) return false;
    final startH = int.tryParse(startParts[0]) ?? 23;
    final startM = int.tryParse(startParts[1]) ?? 0;
    final endH = int.tryParse(endParts[0]) ?? 7;
    final endM = int.tryParse(endParts[1]) ?? 0;

    final t = time.hour * 60 + time.minute;
    final s = startH * 60 + startM;
    final e = endH * 60 + endM;

    if (s <= e) {
      return t >= s && t < e;
    } else {
      return t >= s || t < e;
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // Обработка показанного уведомления (вызывается когда уведомление показано)
  Future<void> handleNotificationShown(int notificationId) async {
    try {
      final db = NotificationDb();
      // Находим уведомление по ID и помечаем как отправленное
      final notifications = await db.list(limit: 1000);
      final notification = notifications.firstWhere(
        (n) => (n.id.hashCode & 0x7FFFFFFF) == notificationId,
        orElse: () => throw Exception('Notification not found'),
      );

      await markAsSent(notification.id);

      // Если это повторяющееся уведомление, планируем следующее
      if (notification.recurrence != Recurrence.none) {
        await scheduleRecurringNotification(notification);
      }
    } catch (e) {
      // Игнорируем ошибки, если уведомление не найдено
    }
  }

  // Метод для тестирования уведомлений
  Future<void> scheduleTestNotification() async {
    if (!_initialized) await initialize();

    final now = DateTime.now();
    final testTime = now.add(const Duration(seconds: 10)); // Через 10 секунд

    debugPrint(
      '🧪 [LocalNotification] Scheduling test notification for $testTime',
    );

    try {
      await _notifications.zonedSchedule(
        999999,
        'Тестовое уведомление',
        'Если вы видите это, уведомления работают!',
        tz.TZDateTime.from(testTime, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'notifications_channel',
            'Уведомления',
            channelDescription: 'Уведомления о событиях',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      // Проверяем сразу после планирования
      final pendingAfter = await _notifications.pendingNotificationRequests();
      debugPrint('✅ [LocalNotification] Test notification scheduled');
      debugPrint(
        '   - Pending notifications immediately after: ${pendingAfter.length}',
      );
      debugPrint(
        '   - Test notification ID in pending: ${pendingAfter.any((n) => n.id == 999999)}',
      );

      // Проверяем через 15 секунд
      Future.delayed(const Duration(seconds: 15), () async {
        final pendingLater = await _notifications.pendingNotificationRequests();
        debugPrint(
          '   - Pending notifications after 15s: ${pendingLater.length}',
        );
        debugPrint(
          '   - Test notification ID still pending: ${pendingLater.any((n) => n.id == 999999)}',
        );
      });
    } catch (e) {
      debugPrint(
        '❌ [LocalNotification] Failed to schedule test notification: $e',
      );
    }
  }

  // Метод для немедленного показа уведомления (тест permissions/channel)
  Future<void> showTestNotificationNow() async {
    if (!_initialized) await initialize();

    debugPrint('🧪 [LocalNotification] Showing test notification NOW');

    try {
      await _notifications.show(
        888888,
        'Тест: Показать сейчас',
        'Если вы видите это, permissions/channel работают',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'notifications_channel',
            'Уведомления',
            channelDescription: 'Уведомления о событиях',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
      debugPrint('✅ [LocalNotification] Test notification shown');
    } catch (e) {
      debugPrint('❌ [LocalNotification] Failed to show test notification: $e');
    }
  }
}
