import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../models/build_artifact.dart';
import '../services/api_client.dart';

class BuildRepository {
  final ApiClient _api;

  BuildRepository(this._api);

  Future<List<BuildArtifact>> listBuilds() async {
    final response = await _api.get('/api/builds');
    return (response.data as List)
        .map((e) => BuildArtifact.fromJson(e))
        .toList();
  }

  Future<void> downloadAndInstall(
    BuildArtifact build, {
    Function(int, int)? onProgress,
  }) async {
    final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/${build.fileName}';
    final file = File(filePath);

    // APK Download Caching
    final isApk = build.fileName.toLowerCase().endsWith('.apk');
    final typeStr = isApk ? 'application/vnd.android.package-archive' : null;

    if (await file.exists()) {
      final stat = await file.stat();
      if (stat.size == build.sizeBytes) {
        // Assume it's the same file if size matches perfectly
        await OpenFilex.open(filePath, type: typeStr);
        return;
      }
    }

    await _api.download(
      build.downloadUrl,
      filePath,
      onReceiveProgress: onProgress,
    );

    // Trigger Android package installer
    await OpenFilex.open(filePath, type: typeStr);
  }
}

final buildRepositoryProvider = Provider<BuildRepository>((ref) {
  return BuildRepository(ref.watch(apiClientProvider));
});
