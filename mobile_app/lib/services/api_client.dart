import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/overview.dart';
import '../providers/config_provider.dart';

import '../models/file_node.dart';
import '../models/git_status.dart';

class ApiClient {
  final Dio _dio;

  ApiClient(this._dio);

  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/api/health');
      return response.statusCode == 200 && response.data['status'] == 'connected';
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> fetchQuotaSummary() async {
    try {
      final response = await _dio.get('/api/quota');
      if (response.data is Map<String, dynamic>) {
        return response.data;
      }
      throw Exception('Invalid quota response format');
    } catch (e) {
      throw Exception('Failed to fetch quota summary: $e');
    }
  }

  Future<Map<String, dynamic>> getQuotaSummary() async {
    try {
      final response = await _dio.get('/api/quota');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<bool> restartDaemon(String executablePath) async {
    try {
      final response = await _dio.post('/api/system/restart-daemon', data: {
        'executablePath': executablePath,
      });
      return response.data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> extractAccount(String profileName, String executablePath) async {
    try {
      final response = await _dio.post('/api/accounts/extract', data: {
        'profileName': profileName,
        'executablePath': executablePath,
      });
      return response.data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<List<String>> listAccounts() async {
    try {
      final response = await _dio.get('/api/accounts');
      if (response.data['success'] == true) {
        return List<String>.from(response.data['profiles']);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> swapAccount(String profileName, String executablePath) async {
    try {
      final response = await _dio.post('/api/accounts/swap', data: {
        'profileName': profileName,
        'executablePath': executablePath,
      });
      return response.data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) async {
    return _dio.get(path, queryParameters: queryParameters);
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final response = await _dio.get('/api/conversations');
      final data = response.data['conversations'] as List;
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Creates a new conversation session. No prompt is sent at creation time;
  /// the user's first message is sent via [sendMessage].
  Future<String> createConversation(String prompt, {String? model, String? selectedModel, Map<String, String>? modelChange}) async {
    try {
      final response = await _dio.post('/api/conversations', data: {
        'prompt': prompt,
        'model': ?model,
        'selectedModel': ?selectedModel,
        'modelChange': ?modelChange,
      });
      final id = response.data['id'];
      if (id == null || id is! String || id.isEmpty) {
        throw Exception('Server returned invalid conversation ID');
      }
      return id;
    } on Exception catch (e) {
      throw Exception('Failed to create conversation: $e');
    }
  }

  Future<void> sendMessage(String id, String content, {String? model, Map<String, String>? modelChange}) async {
    try {
      await _dio.post('/api/conversations/$id/messages', data: {
        'content': content,
        'model': ?model,
        'modelChange': ?modelChange,
      });
    } on Exception catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  Future<List<dynamic>> getHistory(String id, {int? limit, int? beforeIndex}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (limit != null) queryParams['limit'] = limit;
      if (beforeIndex != null) queryParams['beforeIndex'] = beforeIndex;
      
      final response = await _dio.get('/api/conversations/$id/history', queryParameters: queryParams);
      return response.data['history'] as List<dynamic>;
    } on Exception catch (e) {
      throw Exception('Failed to get history: $e');
    }
  }

  Future<List<dynamic>> getConversationHistory(String id) async {
    try {
      final response = await _dio.get('/api/conversations/$id/messages');
      final messages = response.data['messages'];
      if (messages is List) return messages;
      return [];
    } on Exception catch (e) {
      throw Exception('Failed to get conversation history: $e');
    }
  }

  Future<OverviewData> getConversationOverview(String id) async {
    try {
      final response = await _dio.get('/api/conversations/$id/overview');
      return OverviewData.fromJson(response.data);
    } on Exception catch (e) {
      throw Exception('Failed to get conversation overview: $e');
    }
  }

  Future<Map<String, dynamic>> getConversationMetadata(String id) async {
    try {
      final response = await _dio.get('/api/conversations/$id');
      return response.data as Map<String, dynamic>;
    } on Exception catch (e) {
      throw Exception('Failed to get conversation metadata: $e');
    }
  }

  // ============ Files ============

  Future<List<FileNode>> listFiles({String path = '', String? workspace}) async {
    try {
      final response = await _dio.get('/api/files', queryParameters: {
        'path': path,
        'workspace': ?workspace,
      });
      final data = response.data as List;
      return data.map((e) => FileNode.fromJson(e)).toList();
    } on Exception catch (e) {
      throw Exception('Failed to list files: $e');
    }
  }

  Future<Map<String, dynamic>> getFileContent(String path, {String? workspace}) async {
    try {
      final response = await _dio.get('/api/files/content', queryParameters: {
        'path': path,
        'workspace': ?workspace,
      });
      return response.data as Map<String, dynamic>;
    } on Exception catch (e) {
      throw Exception('Failed to read file content: $e');
    }
  }

  Future<FileNode> getFileTree({int depth = 3, String? workspace}) async {
    try {
      final response = await _dio.get('/api/files/tree', queryParameters: {
        'depth': depth,
        'workspace': ?workspace,
      });
      return FileNode.fromJson(response.data);
    } on Exception catch (e) {
      throw Exception('Failed to build file tree: $e');
    }
  }

  Future<void> createFileOrFolder({
    required String path,
    required String type,
    String content = '',
    String? workspace,
    bool base64Encoded = false,
  }) async {
    try {
      await _dio.post('/api/files', data: {
        'path': path,
        'type': type,
        'content': content,
        'workspace': workspace,
        'base64Encoded': base64Encoded,
      });
    } on Exception catch (e) {
      throw Exception('Failed to create $type: $e');
    }
  }

  Future<void> deleteFileOrFolder(String path, {String? workspace}) async {
    try {
      await _dio.delete('/api/files', 
        queryParameters: {
          'path': path,
          'workspace': ?workspace,
        },
        data: {
          'path': path,
          'workspace': workspace,
        },
      );
    } on Exception catch (e) {
      throw Exception('Failed to delete: $e');
    }
  }

  // ============ System & Projects ============

  Future<List<FileNode>> getSystemDirectory(String path) async {
    try {
      final response = await _dio.get('/api/system/fs/ls', queryParameters: {
        'path': path,
      });
      final data = response.data as List;
      return data.map((e) => FileNode.fromJson(e)).toList();
    } on Exception catch (e) {
      throw Exception('Failed to list system directory: $e');
    }
  }

  Future<void> createSystemDirectory(String path, String folderName) async {
    try {
      final fullPath = '$path/$folderName'.replaceAll('//', '/');
      await _dio.post('/api/system/fs/mkdir', data: {
        'path': fullPath,
      });
    } on Exception catch (e) {
      throw Exception('Failed to create system directory: $e');
    }
  }

  Future<void> createNewProject(String targetDirectory) async {
    try {
      await _dio.post('/api/conversations/projects/new', data: {
        'targetDirectory': targetDirectory,
      });
    } on Exception catch (e) {
      throw Exception('Failed to create new project: $e');
    }
  }

  // ============ Git ============

  Future<GitStatus> getGitStatus({String? workspace, String? subPath}) async {
    try {
      final response = await _dio.get('/api/git/status', queryParameters: {
        'workspace': workspace,
        if (subPath != null && subPath.isNotEmpty) 'subPath': subPath,
      });
      return GitStatus.fromJson(response.data);
    } on Exception catch (e) {
      throw Exception('Failed to get git status: $e');
    }
  }

  Future<String> getGitShow(String hash, {String? file, String? workspace, String? subPath}) async {
    try {
      final response = await _dio.get('/api/git/show/$hash', queryParameters: {
        'file': file,
        'workspace': workspace,
        if (subPath != null && subPath.isNotEmpty) 'subPath': subPath,
      });
      return response.data['content'] ?? '';
    } on Exception catch (e) {
      throw Exception('Failed to get git show: $e');
    }
  }

  Future<String> getGitDiff({String? file, bool staged = false, String? workspace, String? subPath}) async {
    try {
      final response = await _dio.get('/api/git/diff', queryParameters: {
        'file': file,
        'staged': staged.toString(),
        'workspace': workspace,
        if (subPath != null && subPath.isNotEmpty) 'subPath': subPath,
      });
      return response.data['diff'] ?? '';
    } on Exception catch (e) {
      throw Exception('Failed to get git diff: $e');
    }
  }

  Future<List<GitLogEntry>> getGitLog({int count = 20, String? workspace, String? subPath}) async {
    try {
      final response = await _dio.get('/api/git/log', queryParameters: {
        'count': count,
        'workspace': workspace,
        if (subPath != null && subPath.isNotEmpty) 'subPath': subPath,
      });
      final data = response.data as List;
      return data.map((e) => GitLogEntry.fromJson(e)).toList();
    } on Exception catch (e) {
      throw Exception('Failed to get git log: $e');
    }
  }

  Future<void> gitAdd(List<String> files, {String? workspace, String? subPath}) async {
    try {
      await _dio.post('/api/git/add', data: {
        'files': files,
        'workspace': workspace,
        if (subPath != null && subPath.isNotEmpty) 'subPath': subPath,
      });
    } on Exception catch (e) {
      throw Exception('Failed to git add: $e');
    }
  }

  Future<String> gitCommit(String message, {String? workspace, String? subPath}) async {
    try {
      final response = await _dio.post('/api/git/commit', data: {
        'message': message,
        'workspace': workspace,
        if (subPath != null && subPath.isNotEmpty) 'subPath': subPath,
      });
      return response.data['output'] ?? '';
    } on Exception catch (e) {
      throw Exception('Failed to git commit: $e');
    }
  }

  Future<String> gitPush({String? remote, String? branch, String? workspace, String? subPath}) async {
    try {
      final response = await _dio.post('/api/git/push', data: {
        'remote': remote,
        'branch': branch,
        'workspace': workspace,
        if (subPath != null && subPath.isNotEmpty) 'subPath': subPath,
      });
      return response.data['output'] ?? '';
    } on Exception catch (e) {
      throw Exception('Failed to git push: $e');
    }
  }

  Future<String> gitPull({String? remote, String? branch, String? workspace, String? subPath}) async {
    try {
      final response = await _dio.post('/api/git/pull', data: {
        'remote': remote,
        'branch': branch,
        'workspace': workspace,
        if (subPath != null && subPath.isNotEmpty) 'subPath': subPath,
      });
      return response.data['output'] ?? '';
    } on Exception catch (e) {
      throw Exception('Failed to git pull: $e');
    }
  }
  Future<Response> download(String path, String savePath, {ProgressCallback? onReceiveProgress}) async {
    return _dio.download(
      path,
      savePath,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<void> registerDevice(String deviceId, String fcmToken, String platform) async {
    try {
      await _dio.post('/api/notifications/register-device', data: {
        'deviceId': deviceId,
        'fcmToken': fcmToken,
        'platform': platform,
      });
    } catch (e) {
      throw Exception('Failed to register device: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getArtifacts(String conversationId) async {
    final response = await _dio.get('/api/conversations/$conversationId/artifacts');
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(response.data['artifacts']);
    }
    throw Exception('Failed to load artifacts');
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(configProvider).value ?? ConfigState();
  
  final dio = Dio(BaseOptions(
    baseUrl: config.relayUrl,
    headers: {
      'x-relay-api-key': config.apiKey,
    },
    contentType: 'application/json',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  return ApiClient(dio);
});

final overviewDataProvider = FutureProvider.family<OverviewData, String>((ref, id) {
  return ref.watch(apiClientProvider).getConversationOverview(id);
});

