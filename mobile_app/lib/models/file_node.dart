class FileNode {
  final String name;
  final String path; // relative to workspace
  final String type; // 'file' or 'directory'
  final int? sizeBytes; // only for files
  final int? childCount; // only for directories
  final String? modifiedAt;
  final List<FileNode>? children; // child items in directory tree

  FileNode({
    required this.name,
    required this.path,
    required this.type,
    this.sizeBytes,
    this.childCount,
    this.modifiedAt,
    this.children,
  });
  factory FileNode.fromJson(Map<String, dynamic> json) {
    final childrenJson = json['children'] as List?;
    final childrenList = childrenJson
        ?.map((i) => FileNode.fromJson(i as Map<String, dynamic>))
        .toList();

    return FileNode(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      type: json['type'] ?? 'file',
      sizeBytes: json['sizeBytes'],
      childCount: json['childCount'],
      modifiedAt: json['modifiedAt'],
      children: childrenList,
    );
  }
}
