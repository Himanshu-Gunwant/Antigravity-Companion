import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'ws_client.dart';

class QueuedMessage {
  final String conversationId;
  final String text;
  final String? model;
  final Map<String, String>? modelChange;

  QueuedMessage({
    required this.conversationId,
    required this.text,
    this.model,
    this.modelChange,
  });
}

class OfflineQueue extends Notifier<List<QueuedMessage>> {
  StreamSubscription? _sub;

  @override
  List<QueuedMessage> build() {
    final wsClient = ref.watch(wsClientProvider);
    _sub?.cancel();
    _sub = wsClient.stateStream.listen((state) {
      if (state == WsConnectionState.connected) {
        _flush();
      }
    });
    ref.onDispose(() {
      _sub?.cancel();
    });
    return [];
  }

  void add(QueuedMessage msg) {
    state = [...state, msg];
  }

  Future<void> _flush() async {
    if (state.isEmpty) return;
    
    final toSend = List<QueuedMessage>.from(state);
    state = [];
    
    final apiClient = ref.read(apiClientProvider);
    for (final msg in toSend) {
      try {
        await apiClient.sendMessage(
          msg.conversationId,
          msg.text,
          model: msg.model,
          modelChange: msg.modelChange,
        );
      } catch (e) {
        // Drop the print statement to clear the avoid_print warning as well
        state = [msg, ...state];
        break;
      }
    }
  }
}

final offlineQueueProvider = NotifierProvider<OfflineQueue, List<QueuedMessage>>(() {
  return OfflineQueue();
});

