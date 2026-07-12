class GitStatus {
  final String branch;
  final String? upstream;
  final int ahead;
  final int behind;
  final List<GitFileStatus> changedFiles;
  final List<String> untrackedFiles;

  GitStatus({
    required this.branch,
    this.upstream,
    required this.ahead,
    required this.behind,
    required this.changedFiles,
    required this.untrackedFiles,
  });

  factory GitStatus.fromJson(Map<String, dynamic> json) {
    return GitStatus(
      branch: json['branch'] ?? '',
      upstream: json['upstream'],
      ahead: json['ahead'] ?? 0,
      behind: json['behind'] ?? 0,
      changedFiles: json['changedFiles'] != null
          ? (json['changedFiles'] as List).map((i) => GitFileStatus.fromJson(i)).toList()
          : [],
      untrackedFiles: json['untrackedFiles'] != null
          ? List<String>.from(json['untrackedFiles'])
          : [],
    );
  }
}

class GitFileStatus {
  final String path;
  final String status; // 'modified', 'added', 'deleted', 'renamed', 'copied'
  final bool staged;

  GitFileStatus({
    required this.path,
    required this.status,
    required this.staged,
  });

  factory GitFileStatus.fromJson(Map<String, dynamic> json) {
    return GitFileStatus(
      path: json['path'] ?? '',
      status: json['status'] ?? 'modified',
      staged: json['staged'] ?? false,
    );
  }
}

class GitLogEntry {
  final String hash;
  final String shortHash;
  final String author;
  final String email;
  final int timestamp; // unix timestamp
  final String message;

  GitLogEntry({
    required this.hash,
    required this.shortHash,
    required this.author,
    required this.email,
    required this.timestamp,
    required this.message,
  });

  factory GitLogEntry.fromJson(Map<String, dynamic> json) {
    return GitLogEntry(
      hash: json['hash'] ?? '',
      shortHash: json['shortHash'] ?? '',
      author: json['author'] ?? '',
      email: json['email'] ?? '',
      timestamp: json['timestamp'] ?? 0,
      message: json['message'] ?? '',
    );
  }
}
