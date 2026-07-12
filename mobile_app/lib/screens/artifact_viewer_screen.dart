import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import '../providers/config_provider.dart';
import '../providers/artifact_cache_provider.dart';
import '../services/api_client.dart';


class ArtifactViewerScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String filename;
  final bool isMedia;

  const ArtifactViewerScreen({
    super.key,
    required this.conversationId,
    required this.filename,
    required this.isMedia,
  });

  @override
  ConsumerState<ArtifactViewerScreen> createState() => _ArtifactViewerScreenState();
}

class _ArtifactViewerScreenState extends ConsumerState<ArtifactViewerScreen> {
  String? _markdownData;
  bool _isLoading = false;
  String? _error;
  final TextEditingController _feedbackController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isMedia) {
      _loadMarkdown();
    }
  }

  Future<void> _loadMarkdown() async {
    final cacheKey = '${widget.conversationId}_${widget.filename}';
    final cachedContent = ref.read(artifactCacheProvider)[cacheKey];
    if (cachedContent != null) {
      setState(() {
        _markdownData = cachedContent;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final config = ref.read(configProvider).value!;
      final url = '${config.relayUrl}/api/conversations/${widget.conversationId}/artifacts/${widget.filename}';
      final dio = Dio();
      final response = await dio.get(
        url, 
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'x-relay-api-key': config.apiKey,
          },
        ),
      );
      
      final content = response.data.toString();
      ref.read(artifactCacheProvider.notifier).cacheContent(cacheKey, content);

      setState(() {
        _markdownData = content;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load document: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final config = ref.watch(configProvider).value!;
    final url = '${config.relayUrl}/api/conversations/${widget.conversationId}/artifacts/${widget.filename}';

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: SafeArea(
                    bottom: false,
                    child: widget.isMedia ? _buildMediaViewer(url) : _buildMarkdownViewer(),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        border: Border.all(color: colorScheme.onSurface.withValues(alpha: 0.1)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.close,
                        color: colorScheme.onSurface,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!widget.isMedia) _buildFeedbackInput(context),
        ],
      ),
    );
  }

  Widget _buildFeedbackInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _feedbackController,
                decoration: InputDecoration(
                  hintText: 'Add feedback...',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                maxLines: null,
              ),
            ),
            const SizedBox(width: 8),
            if (_isSending)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              IconButton(
                icon: const Icon(Icons.send),
                color: colorScheme.primary,
                onPressed: _sendFeedback,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendFeedback() async {
    final text = _feedbackController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.sendMessage(
        widget.conversationId, 
        'Regarding the artifact `${widget.filename}`: $text'
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback sent!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Widget _buildMediaViewer(String url) {

    final config = ref.read(configProvider).value!;
    return Center(
      child: InteractiveViewer(
        child: CachedNetworkImage(
          imageUrl: url,
          httpHeaders: {
            'x-relay-api-key': config.apiKey,
          },
          errorWidget: (context, url, error) {
            final cs = Theme.of(context).colorScheme;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, color: cs.error, size: 64),
                const SizedBox(height: 16),
                Text('Failed to load image', style: TextStyle(color: cs.error)),
              ],
            );
          },
          placeholder: (context, url) {
            final cs = Theme.of(context).colorScheme;
            return CircularProgressIndicator(color: cs.primary);
          },
        ),
      ),
    );
  }

  Widget _buildMarkdownViewer() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: colorScheme.error)),
      );
    }
    if (_markdownData == null) {
      return Center(child: Text('No data found.', style: TextStyle(color: colorScheme.onSurfaceVariant)));
    }

    return Markdown(
      data: _markdownData!,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: colorScheme.onSurface),
        h1: TextStyle(color: colorScheme.primary, fontSize: 24, fontWeight: FontWeight.bold),
        h2: TextStyle(color: colorScheme.primary, fontSize: 20, fontWeight: FontWeight.bold),
        h3: TextStyle(color: colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
        code: TextStyle(backgroundColor: colorScheme.surfaceContainerHigh, fontFamily: 'monospace'),
        codeblockDecoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
