class TranscriptEvent {
  final String conversationId;
  final int stepIndex;
  final String source;
  final String category;
  final String status;
  final String timestamp;
  final String summary;
  final String? content;
  final List<ToolCallSummary>? toolCalls;
  final String? error;
  final bool hasThinking;

  TranscriptEvent({
    required this.conversationId,
    required this.stepIndex,
    required this.source,
    required this.category,
    required this.status,
    required this.timestamp,
    required this.summary,
    this.content,
    this.toolCalls,
    this.error,
    required this.hasThinking,
  });

  factory TranscriptEvent.fromJson(Map<String, dynamic> json) {
    return TranscriptEvent(
      conversationId: json['conversationId'] ?? '',
      stepIndex: json['stepIndex'] ?? 0,
      source: json['source'] ?? '',
      category: json['category'] ?? '',
      status: json['status'] ?? '',
      timestamp: json['timestamp'] ?? '',
      summary: json['summary'] ?? '',
      content: json['content'],
      toolCalls: json['toolCalls'] != null
          ? (json['toolCalls'] as List).map((i) => ToolCallSummary.fromJson(i)).toList()
          : null,
      error: json['error'],
      hasThinking: json['hasThinking'] ?? false,
    );
  }
}

class ToolCallSummary {
  final String name;
  final String summary;
  final String action;

  ToolCallSummary({
    required this.name,
    required this.summary,
    required this.action,
  });

  factory ToolCallSummary.fromJson(Map<String, dynamic> json) {
    return ToolCallSummary(
      name: json['name'] ?? '',
      summary: json['summary'] ?? '',
      action: json['action'] ?? '',
    );
  }
}
