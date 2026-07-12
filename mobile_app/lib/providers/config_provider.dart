import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
class ConfigState {
  final String relayUrl;
  final String apiKey;
  final String daemonExecutablePath;
  final String username;
  final bool isConfigured;

  ConfigState({
    this.relayUrl = '',
    this.apiKey = '',
    this.daemonExecutablePath = '',
    this.username = '',
    this.isConfigured = false,
  });

  ConfigState copyWith({
    String? relayUrl,
    String? apiKey,
    String? daemonExecutablePath,
    String? username,
    bool? isConfigured,
  }) {
    return ConfigState(
      relayUrl: relayUrl ?? this.relayUrl,
      apiKey: apiKey ?? this.apiKey,
      daemonExecutablePath: daemonExecutablePath ?? this.daemonExecutablePath,
      username: username ?? this.username,
      isConfigured: isConfigured ?? this.isConfigured,
    );
  }
}

class ConfigNotifier extends AsyncNotifier<ConfigState> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<ConfigState> build() async {
    return _loadConfig();
  }

  Future<ConfigState> _loadConfig() async {
    try {
      final relayUrl = await _storage.read(key: 'relayUrl');
      final apiKey = await _storage.read(key: 'apiKey');
      final daemonExecutablePath = await _storage.read(key: 'daemonExecutablePath') ?? '';
      final username = await _storage.read(key: 'username') ?? 'User';

      if (relayUrl != null && apiKey != null && relayUrl.isNotEmpty && apiKey.isNotEmpty) {
        return ConfigState(
          relayUrl: relayUrl,
          apiKey: apiKey,
          daemonExecutablePath: daemonExecutablePath,
          username: username,
          isConfigured: true,
        );
      }
    } catch (e) {
      // Ignore storage errors on load and return unconfigured
    }
    return ConfigState();
  }

  Future<void> saveConfig(String relayUrl, String apiKey, {String? daemonExecutablePath, String? username}) async {
    state = const AsyncLoading();
    try {
      await _storage.write(key: 'relayUrl', value: relayUrl);
      await _storage.write(key: 'apiKey', value: apiKey);
      if (daemonExecutablePath != null) {
        await _storage.write(key: 'daemonExecutablePath', value: daemonExecutablePath);
      }
      if (username != null) {
        await _storage.write(key: 'username', value: username);
      }
      
      final currentDaemonPath = daemonExecutablePath ?? (await _storage.read(key: 'daemonExecutablePath')) ?? '';
      final currentUsername = username ?? (await _storage.read(key: 'username')) ?? 'User';
      
      state = AsyncData(ConfigState(
        relayUrl: relayUrl,
        apiKey: apiKey,
        daemonExecutablePath: currentDaemonPath,
        username: currentUsername,
        isConfigured: true,
      ));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> clearConfig() async {
    state = const AsyncLoading();
    try {
      await _storage.delete(key: 'relayUrl');
      await _storage.delete(key: 'apiKey');
      await _storage.delete(key: 'daemonExecutablePath');
      await _storage.delete(key: 'username');
      state = AsyncData(ConfigState());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final configProvider = AsyncNotifierProvider<ConfigNotifier, ConfigState>(() {
  return ConfigNotifier();
});
