class BuildArtifact {
  final String id;
  final String name;
  final String type;
  final String fileName;
  final int sizeBytes;
  final String detectedAt;
  final String modifiedAt;
  final String downloadUrl;

  BuildArtifact({
    required this.id,
    required this.name,
    required this.type,
    required this.fileName,
    required this.sizeBytes,
    required this.detectedAt,
    required this.modifiedAt,
    required this.downloadUrl,
  });

  factory BuildArtifact.fromJson(Map<String, dynamic> json) {
    return BuildArtifact(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      type: json['type'] as String? ?? 'other',
      fileName: json['fileName'] as String? ?? 'unknown',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      detectedAt: json['detectedAt'] as String? ?? '',
      modifiedAt: json['modifiedAt'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String? ?? '',
    );
  }
}
