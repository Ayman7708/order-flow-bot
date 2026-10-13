import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

/// Background isolate entry point
@pragma('vm:entry-point')
void onBackgroundStart(ServiceInstance service) async {
  // Required for plugins in background isolate
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Heartbeat every 30 seconds
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      final now = DateTime.now();
      final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
      try {
        await service.setForegroundNotificationInfo(
          title: 'بوت الأوردر فلو يعمل',
          content: 'المراقبة جارية • $timeStr',
        );
      } catch (_) {}
    }
    service.invoke('heartbeat', {'ts': DateTime.now().millisecondsSinceEpoch});
  });
}

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  try {
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'order_flow_channel',
        initialNotificationTitle: 'بوت الأوردر فلو',
        initialNotificationContent: 'جاري التشغيل...',
        foregroundServiceNotificationId: 777,
        foregroundServiceTypes: [
          AndroidForegroundType.dataSync,
        ],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onBackgroundStart,
      ),
    );
  } catch (e) {
    debugPrint('BG service init error: $e');
  }
}

Future<void> startBgService() async {
  try {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
    service.invoke('setAsForeground');
  } catch (e) {
    debugPrint('BG service start error: $e');
  }
}

Future<void> stopBgService() async {
  try {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
    await Future.delayed(const Duration(milliseconds: 500));
  } catch (e) {
    debugPrint('BG service stop error: $e');
  }
}
