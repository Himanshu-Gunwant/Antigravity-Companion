import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
final _storage = const FlutterSecureStorage();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[Background FCM] Received background message: ${message.messageId} (${message.data})');
}

Future<String> _getOrCreateDeviceId() async {
  String? deviceId = await _storage.read(key: 'device_id');
  if (deviceId == null) {
    final rand = Random.secure();
    final parts = List.generate(4, (_) => rand.nextInt(1000000).toString());
    deviceId = 'device_${parts.join('_')}_${DateTime.now().millisecondsSinceEpoch}';
    await _storage.write(key: 'device_id', value: deviceId);
  }
  return deviceId;
}

class NotificationService {
  final ApiClient _apiClient;
  bool _initialized = false;

  final _clickController = StreamController<String>.broadcast();
  Stream<String> get clickStream => _clickController.stream;
  
  StreamSubscription? _onMessageSub;
  StreamSubscription? _onMessageOpenedAppSub;
  StreamSubscription? _onTokenRefreshSub;

  NotificationService(this._apiClient) {
    _init();
  }

  Future<void> _init() async {
    try {
      debugPrint('[NotificationService] Initializing local notifications & FCM...');

      // 1. Initialize local notifications (foreground alert banners)
      const androidInitializationSettings = AndroidInitializationSettings('ic_notification');
      const initializationSettings = InitializationSettings(
        android: androidInitializationSettings,
        iOS: DarwinInitializationSettings(),
      );

      final initSuccess = await flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('[NotificationService] Notification clicked: ${response.payload}');
          if (response.payload != null) {
            _clickController.add(response.payload!);
          }
        },
      );
      debugPrint('[NotificationService] Local notifications init result: $initSuccess');

      // 2. Request user permissions for notifications
      final messagingInstance = FirebaseMessaging.instance;
      final settings = await messagingInstance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[NotificationService] FCM Permission status: ${settings.authorizationStatus}');

      // Register background messaging handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 3. Register foreground message listener
      _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[NotificationService] Foreground message received: ${message.messageId}');
        _onForegroundMessage(message);
      });

      // 4. Register background message click listener (when app is in background but running)
      _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[NotificationService] App opened from FCM click: ${message.messageId}');
        final category = message.data['category'] as String?;
        if (category != null) {
          _clickController.add(category);
        }
      });

      // 5. Register device and FCM token with backend
      final token = await messagingInstance.getToken();
      if (token != null) {
        debugPrint('[NotificationService] Active FCM Token: $token');
        await _registerToken(token);
      }

      // Listen for token updates
      _onTokenRefreshSub = messagingInstance.onTokenRefresh.listen((newToken) async {
        debugPrint('[NotificationService] FCM Token refreshed: $newToken');
        await _registerToken(newToken);
      });

      // 6. Handle app launch from notification click (terminated state)
      final initialMessage = await messagingInstance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[NotificationService] App launched from initial message: ${initialMessage.messageId}');
        final category = initialMessage.data['category'] as String?;
        if (category != null) {
          Future.delayed(const Duration(milliseconds: 1000), () {
            _clickController.add(category);
          });
        }
      }

      _initialized = true;
      debugPrint('[NotificationService] Service fully initialized.');
    } catch (e) {
      debugPrint('[NotificationService] Initialization failed with error: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      final deviceId = await _getOrCreateDeviceId();
      debugPrint('[NotificationService] Sending token registration to backend: Device ID: $deviceId');
      await _apiClient.registerDevice(deviceId, token, 'android');
      debugPrint('[NotificationService] Token registered successfully on backend.');
    } catch (e) {
      debugPrint('[NotificationService] Token registration failed: $e');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final data = message.data;
    final category = data['category'] as String?;
    final title = notification.title ?? 'Notification';
    final body = notification.body ?? '';
    final priority = data['priority'] as String?;

    _showLocalNotification(category, title, body, priority);
  }

  void _showLocalNotification(String? category, String title, String body, String? priority) async {
    if (!_initialized) {
      debugPrint('[NotificationService] Service not initialized. Ignoring local notification.');
      return;
    }

    late String channelId;
    late String channelName;
    late String channelDesc;
    Importance importance = Importance.defaultImportance;
    Priority notifPriority = Priority.defaultPriority;

    if (category == 'response_ready') {
      channelId = 'response_ready';
      channelName = 'Agent Finished';
      channelDesc = 'Agent finished and responded';
    } else if (category == 'error') {
      channelId = 'error';
      channelName = 'Errors';
      channelDesc = 'Errors in conversations';
      importance = Importance.high;
      notifPriority = Priority.high;
    } else if (category == 'build_complete') {
      channelId = 'build_complete';
      channelName = 'Builds';
      channelDesc = 'Build commands completed';
    } else if (category == 'apk_ready') {
      channelId = 'apk_ready';
      channelName = 'Build Ready';
      channelDesc = 'New build available for install';
      importance = Importance.high;
      notifPriority = Priority.high;
    } else {
      channelId = 'default';
      channelName = 'Default';
      channelDesc = 'Default notifications';
    }

    if (priority == 'high') {
      importance = Importance.high;
      notifPriority = Priority.high;
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: importance,
      priority: notifPriority,
      icon: 'ic_notification',
    );

    final platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    await flutterLocalNotificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: title,
      body: body,
      notificationDetails: platformDetails,
      payload: category,
    );
  }

  void dispose() {
    _onMessageSub?.cancel();
    _onMessageOpenedAppSub?.cancel();
    _onTokenRefreshSub?.cancel();
    _clickController.close();
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(ref.watch(apiClientProvider));
  ref.onDispose(() => service.dispose());
  return service;
});
