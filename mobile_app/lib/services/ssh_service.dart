import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import '../models/ssh_connection.dart';
import '../models/ssh_session_meta.dart';

const _storage = FlutterSecureStorage();

class SshSessionInstance {
  final String sessionId;
  final SshConnection connection;
  final Terminal terminal;
  final void Function(String status) onStatusChange;
  final Future<bool> Function(String host, String fingerprint) verifyHostKeyCallback;

  SSHClient? _client;
  SSHSession? _shellSession;
  String _status = 'Disconnected';
  String get status => _status;

  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;
  bool _isDisposed = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  SshSessionInstance({
    required this.sessionId,
    required this.connection,
    required this.terminal,
    required this.onStatusChange,
    required this.verifyHostKeyCallback,
  }) {
    terminal.onOutput = _handleTerminalOutput;
  }

  void _setStatus(String newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      onStatusChange(newStatus);
    }
  }

  Future<void> connect() async {
    if (_isDisposed) return;
    _reconnectTimer?.cancel();
    _setStatus('Connecting');
    terminal.write('\r\n\x1b[1;36m[SSH] Connecting to ${connection.host}:${connection.port}...\x1b[0m\r\n');

    try {
      // Fetch credentials securely
      final password = await _storage.read(key: 'ssh_pass_${connection.id}');
      final privateKey = await _storage.read(key: 'ssh_key_${connection.id}');
      final passphrase = await _storage.read(key: 'ssh_passphrase_${connection.id}');

      final socket = await SSHSocket.connect(
        connection.host,
        connection.port,
        timeout: const Duration(seconds: 10),
      );

      _client = SSHClient(
        socket,
        username: connection.username,
        onPasswordRequest: () => password,
        identities: privateKey != null 
            ? SSHKeyPair.fromPem(privateKey, passphrase != null && passphrase.isNotEmpty ? passphrase : null) 
            : null,
        onVerifyHostKey: (type, fingerprintBytes) async {
          final fingerprint = utf8.decode(fingerprintBytes);
          return await verifyHostKeyCallback(connection.host, fingerprint);
        },
        keepAliveInterval: const Duration(seconds: 15),
      );

      // Await authentication success
      await _client!.authenticated;

      // Start shell session
      _shellSession = await _client!.shell();

      _setStatus('Connected');
      terminal.write('\x1b[1;32m[SSH] Authentication Succeeded. Session Opened.\x1b[0m\r\n');
      _reconnectAttempts = 0;

      // Pipe SSH output to Terminal view
      _stdoutSub = _shellSession!.stdout.listen((data) {
        terminal.write(utf8.decode(data));
      });

      _stderrSub = _shellSession!.stderr.listen((data) {
        terminal.write(utf8.decode(data));
      });

      // Handle socket closure
      _client!.done.then((_) {
        _handleDisconnect();
      }).catchError((_) {
        _handleDisconnect();
      });
    } catch (e) {
      terminal.write('\r\n\x1b[1;31m[SSH] Connection failed: $e\x1b[0m\r\n');
      _handleDisconnect();
    }
  }

  void _handleTerminalOutput(String data) {
    if (_status == 'Connected' && _shellSession != null) {
      _shellSession!.write(utf8.encode(data));
    }
  }

  void _handleDisconnect() {
    if (_isDisposed) return;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _shellSession = null;
    _client = null;

    if (_reconnectAttempts < 5) {
      _reconnectAttempts++;
      _setStatus('Reconnecting');
      final backoff = Duration(seconds: 2 * _reconnectAttempts);
      terminal.write('\r\n\x1b[1;33m[SSH] Disconnected. Reconnecting in ${_reconnectAttempts * 2}s...\x1b[0m\r\n');
      _reconnectTimer = Timer(backoff, () => connect());
    } else {
      _setStatus('Disconnected');
      terminal.write('\r\n\x1b[1;31m[SSH] Disconnected permanently. Max reconnection attempts reached.\x1b[0m\r\n');
    }
  }

  bool get isConnected => _status == 'Connected';

  void write(String data) {
    if (_status == 'Connected' && _shellSession != null) {
      _shellSession!.write(utf8.encode(data));
    }
  }

  void writeBytes(List<int> bytes) {
    if (_status == 'Connected' && _shellSession != null) {
      _shellSession!.write(Uint8List.fromList(bytes));
    }
  }

  Future<void> sendCommand(String command) async {
    if (_status == 'Connected' && _shellSession != null) {
      _shellSession!.write(utf8.encode('$command\n'));
    }
  }

  Future<SftpClient?> getSftpClient() async {
    if (_status == 'Connected' && _client != null) {
      return await _client!.sftp();
    }
    return null;
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _shellSession?.close();
    _client?.close();
  }
}

class SshService {
  final Ref _ref;

  // Active runtime sessions (sessionId -> SessionInstance)
  final Map<String, SshSessionInstance> _activeSessions = {};
  
  // Custom Session State change listeners (sessionId -> callback)
  final Map<String, List<void Function(String status)>> _statusListeners = {};

  SshService(this._ref);

  // Connection Profile Management (stored as JSON array in secure storage)
  Future<List<SshConnection>> loadConnections() async {
    try {
      final jsonStr = await _storage.read(key: 'ssh_profiles');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = json.decode(jsonStr);
        return decoded.map((item) => SshConnection.fromMap(item)).toList();
      }
    } catch (e) {
      debugPrint('[SshService] Failed to load connections: $e');
    }
    return [];
  }

  Future<void> saveConnection(SshConnection profile, {String? password, String? privateKey, String? passphrase}) async {
    final connections = await loadConnections();
    final index = connections.indexWhere((c) => c.id == profile.id);
    if (index >= 0) {
      connections[index] = profile;
    } else {
      connections.add(profile);
    }

    await _storage.write(key: 'ssh_profiles', value: json.encode(connections.map((c) => c.toMap()).toList()));

    // Store credentials securely
    if (password != null) {
      await _storage.write(key: 'ssh_pass_${profile.id}', value: password);
    }
    if (privateKey != null) {
      await _storage.write(key: 'ssh_key_${profile.id}', value: privateKey);
    }
    if (passphrase != null) {
      await _storage.write(key: 'ssh_passphrase_${profile.id}', value: passphrase);
    }
  }

  Future<void> deleteConnection(String id) async {
    final connections = await loadConnections();
    connections.removeWhere((c) => c.id == id);
    await _storage.write(key: 'ssh_profiles', value: json.encode(connections.map((c) => c.toMap()).toList()));

    // Clear associated secure storage credentials
    await _storage.delete(key: 'ssh_pass_$id');
    await _storage.delete(key: 'ssh_key_$id');
    await _storage.delete(key: 'ssh_passphrase_$id');
  }

  // Fingerprint trust management
  Future<Set<String>> loadTrustedFingerprints() async {
    final raw = await _storage.read(key: 'ssh_trusted_fingerprints');
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> list = json.decode(raw);
      return list.map((e) => e.toString()).toSet();
    }
    return {};
  }

  Future<void> trustFingerprint(String host, String fingerprint) async {
    final trusted = await loadTrustedFingerprints();
    trusted.add('$host:$fingerprint');
    await _storage.write(key: 'ssh_trusted_fingerprints', value: json.encode(trusted.toList()));
  }

  Future<bool> verifyFingerprint(String host, String fingerprint) async {
    final trusted = await loadTrustedFingerprints();
    final key = '$host:$fingerprint';
    
    // Check if we already have a trusted key for this host
    final existingForHost = trusted.firstWhere((e) => e.startsWith('$host:'), orElse: () => '');
    if (existingForHost.isNotEmpty) {
      final matches = existingForHost == key;
      if (!matches) {
        debugPrint('[SshService] Host key verification FAILED for $host. Expected: $existingForHost, Got: $key');
      }
      return matches;
    }
    
    // First time seeing this host - auto trust and save it!
    debugPrint('[SshService] Auto-trusting new host fingerprint: $key');
    await trustFingerprint(host, fingerprint);
    return true;
  }

  // Stored snippets
  Future<List<String>> loadSnippets() async {
    final raw = await _storage.read(key: 'ssh_snippets');
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> list = json.decode(raw);
      return list.map((e) => e.toString()).toList();
    }
    // Return some default handy commands
    return ['git status', 'git pull', 'flutter build apk', 'flutter clean', 'npm run dev', 'htop'];
  }

  Future<void> saveSnippet(String command) async {
    final snippets = await loadSnippets();
    if (!snippets.contains(command)) {
      snippets.add(command);
      await _storage.write(key: 'ssh_snippets', value: json.encode(snippets));
    }
  }

  Future<void> deleteSnippet(String command) async {
    final snippets = await loadSnippets();
    snippets.remove(command);
    await _storage.write(key: 'ssh_snippets', value: json.encode(snippets));
  }

  // Active Terminal Tab Sessions
  SshSessionInstance? getSession(String sessionId) {
    return _activeSessions[sessionId];
  }

  List<String> getActiveSessionIds() {
    return _activeSessions.keys.toList();
  }

  void addStatusListener(String sessionId, void Function(String status) listener) {
    _statusListeners.putIfAbsent(sessionId, () => []).add(listener);
  }

  void removeStatusListener(String sessionId, void Function(String status) listener) {
    _statusListeners[sessionId]?.remove(listener);
  }

  Future<String> createSession(SshConnection connection) async {
    final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    final terminal = Terminal(maxLines: 5000);

    final instance = SshSessionInstance(
      sessionId: sessionId,
      connection: connection,
      terminal: terminal,
      onStatusChange: (status) {
        _ref.notifyListeners();
        final listeners = _statusListeners[sessionId];
        if (listeners != null) {
          for (final callback in listeners) {
            callback(status);
          }
        }
        _saveActiveSessionsMeta();
      },
      verifyHostKeyCallback: (host, fingerprint) async {
        return await verifyFingerprint(host, fingerprint);
      },
    );

    _activeSessions[sessionId] = instance;
    _ref.notifyListeners();
    
    // Connect immediately
    instance.connect();
    
    await _saveActiveSessionsMeta();
    return sessionId;
  }

  void closeSession(String sessionId) {
    final instance = _activeSessions.remove(sessionId);
    instance?.dispose();
    _statusListeners.remove(sessionId);
    _ref.notifyListeners();
    _saveActiveSessionsMeta();
  }

  // Tab Persistence Metadata (to rebuild placeholders on reboot)
  Future<List<SshSessionMeta>> loadSessionMeta() async {
    final raw = await _storage.read(key: 'ssh_sessions_meta');
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> list = json.decode(raw);
      return list.map((item) => SshSessionMeta.fromMap(item)).toList();
    }
    return [];
  }

  Future<void> _saveActiveSessionsMeta() async {
    final list = _activeSessions.entries.map((entry) {
      return SshSessionMeta(
        sessionId: entry.key,
        connectionId: entry.value.connection.id,
        nickname: entry.value.connection.name,
        lastActive: DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();

    await _storage.write(key: 'ssh_sessions_meta', value: json.encode(list.map((m) => m.toMap()).toList()));
  }

  Future<void> attemptRestoreSessions() async {
    final metas = await loadSessionMeta();
    if (metas.isEmpty) return;

    final connections = await loadConnections();
    for (final meta in metas) {
      // If we don't already have this session active, and the connection profile exists, restore it!
      if (!_activeSessions.containsKey(meta.sessionId)) {
        final conn = connections.firstWhere((c) => c.id == meta.connectionId, orElse: () => SshConnection(id: '', name: '', host: '', username: '', authType: ''));
        if (conn.id.isNotEmpty) {
          final terminal = Terminal(maxLines: 5000);
          final instance = SshSessionInstance(
            sessionId: meta.sessionId,
            connection: conn,
            terminal: terminal,
            onStatusChange: (status) {
              _ref.notifyListeners();
              final listeners = _statusListeners[meta.sessionId];
              if (listeners != null) {
                for (final callback in listeners) {
                  callback(status);
                }
              }
            },
            verifyHostKeyCallback: (host, fingerprint) async {
              return await verifyFingerprint(host, fingerprint);
            },
          );
          _activeSessions[meta.sessionId] = instance;
          instance.connect();
        }
      }
    }
    _ref.notifyListeners();
  }

  // Network/Lifecycle events trigger reconnect of all connecting/reconnecting sessions
  void triggerReconnectAll() {
    debugPrint('[SshService] Network change triggered. Reconnecting active sessions...');
    for (final instance in _activeSessions.values) {
      if (instance.status == 'Disconnected' || instance.status == 'Reconnecting') {
        instance.connect();
      }
    }
  }

  void dispose() {
    for (final instance in _activeSessions.values) {
      instance.dispose();
    }
    _activeSessions.clear();
  }
}

final sshServiceProvider = Provider<SshService>((ref) {
  final service = SshService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
