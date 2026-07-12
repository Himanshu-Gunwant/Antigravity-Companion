import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../providers/config_provider.dart';
import '../models/event.dart';

enum WsConnectionState { disconnected, connecting, connected, error }

class WsClient {
  final String _baseUrl;
  final String _apiKey;
  WebSocketChannel? _channel;

  WsConnectionState _connectionState = WsConnectionState.disconnected;
  WsConnectionState get connectionState => _connectionState;

  bool _isDaemonActive = true;
  bool get isDaemonActive => _isDaemonActive;

  final _stateController = StreamController<WsConnectionState>.broadcast();
  Stream<WsConnectionState> get stateStream => _stateController.stream;

  final _daemonStatusController = StreamController<bool>.broadcast();
  Stream<bool> get daemonStatusStream => _daemonStatusController.stream;

  final _transcriptController = StreamController<TranscriptEvent>.broadcast();
  final _fileChangeController = StreamController<Map<String, dynamic>>.broadcast();
  final _gitStatusController = StreamController<Map<String, dynamic>>.broadcast();
  final _buildController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<TranscriptEvent> get transcriptStream => _transcriptController.stream;
  Stream<Map<String, dynamic>> get fileChangeStream => _fileChangeController.stream;
  Stream<Map<String, dynamic>> get gitStatusStream => _gitStatusController.stream;
  Stream<Map<String, dynamic>> get buildStream => _buildController.stream;

  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  // Queue subscriptions that arrive before the WS is fully confirmed open
  final Set<String> _activeSubscriptions = {};

  WsClient(this._baseUrl, this._apiKey);

  void connect() {
    if (_connectionState == WsConnectionState.connected ||
        _connectionState == WsConnectionState.connecting) {
      return;
    }

    _setConnectionState(WsConnectionState.connecting);

    try {
      final wsUrl = _baseUrl.replaceFirst('http', 'ws');
      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl/ws?token=$_apiKey'),
      );

      _channel!.stream.listen(
        (message) {
          _reconnectAttempts = 0;
          if (_connectionState != WsConnectionState.connected) {
            _setConnectionState(WsConnectionState.connected);
            _flushActiveSubscriptions();
          }
          _handleMessage(message);
        },
        onError: (error) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
        cancelOnError: true,
      );

      // Wait for the WebSocket to be ready, then send a ping to confirm
      // the connection is alive. The pong response will trigger the
      // stream listener above, confirming the connected state.
      _channel!.ready.timeout(const Duration(seconds: 10)).then((_) {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      }).catchError((_) {
        _handleDisconnect();
      });
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _flushActiveSubscriptions() {
    // Always subscribe to files and git channels
    _channel?.sink.add(jsonEncode({
      'type': 'subscribe',
      'channels': [
        {'kind': 'files'},
        {'kind': 'git'},
        {'kind': 'builds'}
      ]
    }));

    for (final id in _activeSubscriptions) {
      _sendSubscribeMessage(id);
    }
  }

  void _sendSubscribeMessage(String conversationId) {
    _channel?.sink.add(jsonEncode({
      'type': 'subscribe',
      'channels': [
        {'kind': 'transcript', 'conversationId': conversationId}
      ]
    }));
  }

  void _handleMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message as String);
      if (decoded['type'] == 'step' && decoded['data'] != null) {
        final event = TranscriptEvent.fromJson(decoded['data'] as Map<String, dynamic>);
        _transcriptController.add(event);
      } else if (decoded['type'] == 'file_change' && decoded['data'] != null) {
        _fileChangeController.add(decoded['data'] as Map<String, dynamic>);
      } else if (decoded['type'] == 'git_status' && decoded['data'] != null) {
        _gitStatusController.add(decoded['data'] as Map<String, dynamic>);
      } else if (decoded['type'] == 'build_detected') {
        _buildController.add(decoded['data'] as Map<String, dynamic>);
      } else if (decoded['type'] == 'daemon_status' && decoded['data'] != null) {
        _isDaemonActive = decoded['data']['active'] as bool? ?? true;
        _daemonStatusController.add(_isDaemonActive);
      }
    } catch (_) {
      // ignore malformed messages
    }
  }

  void _handleDisconnect() {
    _setConnectionState(WsConnectionState.disconnected);
    _channel?.sink.close(status.goingAway);
    _channel = null;

    _reconnectAttempts++;
    final seconds = math.min(math.pow(2, _reconnectAttempts).toInt(), 120);
    final backoff = Duration(seconds: seconds);
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(backoff, connect);
  }

  void subscribe(String conversationId) {
    _activeSubscriptions.add(conversationId);
    if (_connectionState == WsConnectionState.connected) {
      _sendSubscribeMessage(conversationId);
    }
  }

  void unsubscribe(String conversationId) {
    _activeSubscriptions.remove(conversationId);
    if (_connectionState == WsConnectionState.connected) {
      _channel?.sink.add(jsonEncode({
        'type': 'unsubscribe',
        'channels': [
          {'kind': 'transcript', 'conversationId': conversationId}
        ]
      }));
    }
  }

  void _setConnectionState(WsConnectionState state) {
    _connectionState = state;
    _stateController.add(state);
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close(status.normalClosure);
    _stateController.close();
    _daemonStatusController.close();
    _transcriptController.close();
    _fileChangeController.close();
    _gitStatusController.close();
    _buildController.close();
  }
}

final wsClientProvider = Provider<WsClient>((ref) {
  final config = ref.watch(configProvider).value ?? ConfigState();
  final client = WsClient(config.relayUrl, config.apiKey);

  if (config.isConfigured) {
    client.connect();
  }

  ref.onDispose(() {
    client.dispose();
  });

  return client;
});
