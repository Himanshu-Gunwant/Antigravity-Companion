import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_node.dart';
import '../services/api_client.dart';
import '../services/ws_client.dart';

class ActiveWorkspaceNotifier extends Notifier<String> {
  @override
  String build() => '';
  
  void setWorkspace(String path) {
    state = path;
  }
}

final activeWorkspaceProvider = NotifierProvider<ActiveWorkspaceNotifier, String>(() {
  return ActiveWorkspaceNotifier();
});

class CustomDownloadLocationNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setLocation(String path) {
    state = path;
  }
}

final customDownloadLocationProvider = NotifierProvider<CustomDownloadLocationNotifier, String>(() {
  return CustomDownloadLocationNotifier();
});

final filesProvider = FutureProvider.family<List<FileNode>, String>((ref, path) {
  final apiClient = ref.watch(apiClientProvider);
  final workspace = ref.watch(activeWorkspaceProvider);
  
  // Auto-refresh when file change events are received for this folder
  final wsClient = ref.watch(wsClientProvider);
  final sub = wsClient.fileChangeStream.listen((event) {
    final changePath = event['path'] as String? ?? '';
    // If it's a file inside this directory, refresh
    if (path.isEmpty || changePath.startsWith('$path/') || changePath == path) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(() => sub.cancel());

  return apiClient.listFiles(path: path, workspace: workspace.isEmpty ? null : workspace);
});

final fileContentProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, path) {
  final apiClient = ref.watch(apiClientProvider);
  final workspace = ref.watch(activeWorkspaceProvider);

  // Auto-refresh if this file changes
  final wsClient = ref.watch(wsClientProvider);
  final sub = wsClient.fileChangeStream.listen((event) {
    final changePath = event['path'] as String? ?? '';
    if (changePath == path) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(() => sub.cancel());

  return apiClient.getFileContent(path, workspace: workspace.isEmpty ? null : workspace);
});
