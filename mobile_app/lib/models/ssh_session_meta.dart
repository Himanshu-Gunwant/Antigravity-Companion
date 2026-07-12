import 'dart:convert';

class SshSessionMeta {
  final String sessionId;
  final String connectionId;
  final String nickname;
  final String lastCwd;
  final int lastActive; // timestamp

  SshSessionMeta({
    required this.sessionId,
    required this.connectionId,
    required this.nickname,
    this.lastCwd = '',
    required this.lastActive,
  });

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'connectionId': connectionId,
      'nickname': nickname,
      'lastCwd': lastCwd,
      'lastActive': lastActive,
    };
  }

  factory SshSessionMeta.fromMap(Map<String, dynamic> map) {
    return SshSessionMeta(
      sessionId: map['sessionId'] ?? '',
      connectionId: map['connectionId'] ?? '',
      nickname: map['nickname'] ?? '',
      lastCwd: map['lastCwd'] ?? '',
      lastActive: map['lastActive'] ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory SshSessionMeta.fromJson(String source) => SshSessionMeta.fromMap(json.decode(source));
}
