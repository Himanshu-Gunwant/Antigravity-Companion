import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/build_artifact.dart';
import '../repositories/build_repository.dart';
import '../services/ws_client.dart';

final buildsProvider = FutureProvider<List<BuildArtifact>>((ref) {
  final repo = ref.watch(buildRepositoryProvider);

  // Auto-refresh when new builds are detected
  final wsClient = ref.watch(wsClientProvider);
  final sub = wsClient.buildStream.listen((event) {
    ref.invalidateSelf();
  });
  ref.onDispose(() => sub.cancel());

  return repo.listBuilds();
});

class BuildStatusNotifier extends Notifier<String> {
  Timer? _resetTimer;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  String build() {
    _sub?.cancel();
    _resetTimer?.cancel();

    final wsClient = ref.read(wsClientProvider);
    _sub = wsClient.buildStream.listen((event) {
      state = 'Completed';
      _scheduleReset();
    });

    ref.onDispose(() {
      _sub?.cancel();
      _resetTimer?.cancel();
    });

    return 'Idle';
  }

  void _scheduleReset() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 5), () {
      state = 'Idle';
    });
  }

  void setBuilding() {
    _resetTimer?.cancel();
    state = 'Building...';
  }
}

final buildStatusProvider = NotifierProvider<BuildStatusNotifier, String>(() {
  return BuildStatusNotifier();
});
