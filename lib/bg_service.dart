import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// This function runs in a SEPARATE isolate (background)
/// It must be a TOP-LEVEL function with @pragma
@pragma('vm:entry-point')
void onBackgroundStart(ServiceInstance service) async {
  // Required for isolate
  DartPluginRegistrant.ensureInitialized();

  final notif = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await notif.initialize(initSettings);

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
    // Start as foreground service immediately
    await service.setAsForegroundService();
  }

  // Heartbeat every 30 seconds to keep service alive
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      final now = DateTime.now();
      final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      await service.setForegroundNotificationInfo(
        title: 'بوت الأوردر فلو يعمل',
        content: 'المراقبة جارية • آخر تحديث: $timeStr',
      );
    }
    service.invoke('heartbeat', {'ts': DateTime.now().millisecondsSinceEpoch});
  });
}

/// Configure the service
Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'order_flow_channel',
      initialNotificationTitle: 'بوت الأوردر فلو',
      initialNotificationContent: 'جاري التشغيل...',
      foregroundServiceNotificationId: 777,
      autoStartOnBoot: true,
      foregroundServiceTypes: [
        AndroidForegroundType.dataSync,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundStart,
      onBackground: (service) => true,
    ),
  );
}

Future<void> startBgService() async {
  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
  }
  service.invoke('setAsForeground');
}

Future<void> stopBgService() async {
  final service = FlutterBackgroundService();
  service.invoke('stopService');
  await Future.delayed(const Duration(milliseconds: 500));
}
