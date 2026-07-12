import 'dart:convert';

class SshConnection {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authType; // 'password' or 'privateKey'
  final bool hasPassphrase;

  SshConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    required this.authType,
    this.hasPassphrase = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'authType': authType,
      'hasPassphrase': hasPassphrase,
    };
  }

  factory SshConnection.fromMap(Map<String, dynamic> map) {
    return SshConnection(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      host: map['host'] ?? '',
      port: map['port'] ?? 22,
      username: map['username'] ?? '',
      authType: map['authType'] ?? 'password',
      hasPassphrase: map['hasPassphrase'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory SshConnection.fromJson(String source) => SshConnection.fromMap(json.decode(source));
}
