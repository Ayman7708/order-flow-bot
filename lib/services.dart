import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings);
      final a = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (a != null) await a.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notif init error: $e');
    }
  }

  static Future<void> show(String title, String body) async {
    try {
      await init();
      const android = AndroidNotificationDetails(
        'flow_channel', 'Order Flow',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(android: android);
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title, body, details,
      );
    } catch (_) {}
  }
}

class Store {
  static const _kData = 'flow_data_v1';

  static Future<void> save(Map<String, dynamic> data) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kData, json.encode(data));
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  static Future<Map<String, dynamic>?> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_kData);
      if (s == null) return null;
      return json.decode(s) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Load error: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.clear();
  }
}
