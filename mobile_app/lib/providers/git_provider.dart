import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/git_status.dart';
import '../services/api_client.dart';
import '../services/ws_client.dart';
import 'file_provider.dart';

class GitSubPathNotifier extends Notifier<String> {
  @override
  String build() => '';
  
  void setPath(String path) {
    state = path;
  }
}

final gitSubPathProvider = NotifierProvider<GitSubPathNotifier, String>(() {
  return GitSubPathNotifier();
});
final gitStatusProvider = FutureProvider<GitStatus>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final workspace = ref.watch(activeWorkspaceProvider);

  // Auto-refresh when git status changes over WebSocket
  final wsClient = ref.watch(wsClientProvider);
  final sub = wsClient.gitStatusStream.listen((event) {
    ref.invalidateSelf();
  });
  ref.onDispose(() => sub.cancel());

  final subPath = ref.watch(gitSubPathProvider);
  return apiClient.getGitStatus(workspace: workspace.isEmpty ? null : workspace, subPath: subPath);
});

final gitLogProvider = FutureProvider<List<GitLogEntry>>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final workspace = ref.watch(activeWorkspaceProvider);

  // Auto-refresh log when status changes (since commits/pushes change status)
  final wsClient = ref.watch(wsClientProvider);
  final sub = wsClient.gitStatusStream.listen((event) {
    ref.invalidateSelf();
  });
  ref.onDispose(() => sub.cancel());

  final subPath = ref.watch(gitSubPathProvider);
  return apiClient.getGitLog(workspace: workspace.isEmpty ? null : workspace, subPath: subPath);
});

class GitDiffArg {
  final String? file;
  final bool staged;
  GitDiffArg({this.file, required this.staged});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GitDiffArg &&
          runtimeType == other.runtimeType &&
          file == other.file &&
          staged == other.staged;

  @override
  int get hashCode => Object.hash(file, staged);
}

final gitDiffProvider = FutureProvider.family<String, GitDiffArg>((ref, arg) {
  final apiClient = ref.watch(apiClientProvider);
  final workspace = ref.watch(activeWorkspaceProvider);

  // Auto-refresh diff on status change
  final wsClient = ref.watch(wsClientProvider);
  final sub = wsClient.gitStatusStream.listen((event) {
    ref.invalidateSelf();
  });
  ref.onDispose(() => sub.cancel());

  final subPath = ref.watch(gitSubPathProvider);
  return apiClient.getGitDiff(file: arg.file, staged: arg.staged, workspace: workspace.isEmpty ? null : workspace, subPath: subPath);
});

class GitShowArg {
  final String hash;
  final String? file;
  GitShowArg({required this.hash, this.file});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GitShowArg &&
          runtimeType == other.runtimeType &&
          hash == other.hash &&
          file == other.file;

  @override
  int get hashCode => Object.hash(hash, file);
}

final gitShowProvider = FutureProvider.family<String, GitShowArg>((ref, arg) {
  final workspace = ref.watch(activeWorkspaceProvider);
  final subPath = ref.watch(gitSubPathProvider);
  return ref.watch(apiClientProvider).getGitShow(arg.hash, file: arg.file, workspace: workspace.isEmpty ? null : workspace, subPath: subPath);
});
