class OverviewData {
  final List<SubagentInfo> subagents;
  final List<FileChangeInfo> filesChanged;
  final List<ArtifactInfo> artifacts;
  final List<BackgroundTaskInfo> backgroundTasks;

  OverviewData({
    required this.subagents,
    required this.filesChanged,
    required this.artifacts,
    required this.backgroundTasks,
  });

  factory OverviewData.fromJson(Map<String, dynamic> json) {
    return OverviewData(
      subagents: (json['subagents'] as List? ?? []).map((e) => SubagentInfo.fromJson(e)).toList(),
      filesChanged: (json['filesChanged'] as List? ?? []).map((e) => FileChangeInfo.fromJson(e)).toList(),
      artifacts: (json['artifacts'] as List? ?? []).map((e) => ArtifactInfo.fromJson(e)).toList(),
      backgroundTasks: (json['backgroundTasks'] as List? ?? []).map((e) => BackgroundTaskInfo.fromJson(e)).toList(),
    );
  }
}

class SubagentInfo {
  final String name;
  final String id;
  SubagentInfo({required this.name, required this.id});
  factory SubagentInfo.fromJson(Map<String, dynamic> json) => SubagentInfo(name: json['name'] ?? '', id: json['id'] ?? '');
}

class FileChangeInfo {
  final String path;
  final int additions;
  final int deletions;
  FileChangeInfo({required this.path, required this.additions, required this.deletions});
  factory FileChangeInfo.fromJson(Map<String, dynamic> json) => FileChangeInfo(
    path: json['path'] ?? '', 
    additions: json['additions'] ?? 0, 
    deletions: json['deletions'] ?? 0
  );
}

class ArtifactInfo {
  final String name;
  final String path;
  final String iconType;
  ArtifactInfo({required this.name, required this.path, required this.iconType});
  factory ArtifactInfo.fromJson(Map<String, dynamic> json) => ArtifactInfo(
    name: json['name'] ?? '', 
    path: json['path'] ?? '', 
    iconType: json['iconType'] ?? 'document'
  );
}

class BackgroundTaskInfo {
  final String command;
  final String status;
  BackgroundTaskInfo({required this.command, required this.status});
  factory BackgroundTaskInfo.fromJson(Map<String, dynamic> json) => BackgroundTaskInfo(
    command: json['command'] ?? '', 
    status: json['status'] ?? ''
  );
}
