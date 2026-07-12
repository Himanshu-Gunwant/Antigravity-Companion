import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/ws_client.dart';
import '../services/api_client.dart';
import '../models/event.dart';
import '../theme/design_system.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/overview_drawer.dart';

import '../providers/file_provider.dart';

class ProcessGroup {
  final List<TranscriptEvent> events;
  final bool isCompleted;
  ProcessGroup({required this.events, required this.isCompleted});
}

class ChatScreen extends ConsumerStatefulWidget {
  final String? initialConversationId;

  const ChatScreen({super.key, this.initialConversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _conversationId;
  String? _mentionQuery;
  List<Map<String, dynamic>> _conversationArtifacts = [];
  bool _isLoading = false;
  String? _errorMsg;
  bool _isSending = false;
  bool _showScrollToBottom = false;
  
  bool _isLoadingHistory = false;
  bool _hasMoreHistory = true;

  final List<TranscriptEvent> _events = [];
  bool _displayItemsDirty = true;
  List<dynamic> _cachedDisplayItems = [];
  StreamSubscription<TranscriptEvent>? _eventSub;
  StreamSubscription<WsConnectionState>? _stateSub;

  // Track which stepIndex values we've already shown to avoid duplicates
  final Set<int> _seenStepIndices = {};

  // Model selection state
  String _selectedModel = 'gemini_3.5_flash_high_fast';
  String? _pendingModelChangeFrom;
  String? _pendingModelChangeTo;

  String _getFriendlyModelName(String modelKey) {
    switch (modelKey) {
      case 'gemini_3.5_flash_medium': return 'Gemini 3.5 Flash (Medium)';
      case 'gemini_3.5_flash_high_fast': return 'Gemini 3.5 Flash (High) Fast';
      case 'gemini_3.5_flash_low': return 'Gemini 3.5 Flash (Low)';
      case 'gemini_3.1_pro_low': return 'Gemini 3.1 Pro (Low)';
      case 'gemini_3.1_pro_high': return 'Gemini 3.1 Pro (High)';
      case 'claude_sonnet_4.6_thinking': return 'Claude Sonnet 4.6 (Thinking)';
      case 'claude_opus_4.6_thinking': return 'Claude Opus 4.6 (Thinking)';
      case 'gpt_oss_120b_medium': return 'GPT-OSS 120B (Medium)';
      default: return 'Gemini 3.5 Flash (High) Fast';
    }
  }

  String _getCliModel(String modelKey) {
    if (modelKey.contains('pro') || modelKey.contains('claude')) {
      return 'pro';
    }
    if (modelKey.contains('lite')) {
      return 'flash_lite';
    }
    return 'flash';
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialConversationId != null) {
      _conversationId = widget.initialConversationId;
      _loadConversation(widget.initialConversationId!);
    }

    _messageController.addListener(() {
      final text = _messageController.text;
      final selection = _messageController.selection;
      
      if (selection.isValid && selection.isCollapsed) {
        final pos = selection.baseOffset;
        int atIndex = -1;
        for (int i = pos - 1; i >= 0; i--) {
          if (text[i] == ' ') break;
          if (text[i] == '@') {
            atIndex = i;
            break;
          }
        }
        
        if (atIndex != -1) {
          final query = text.substring(atIndex + 1, pos);
          setState(() {
            _mentionQuery = query;
          });
        } else {
          if (_mentionQuery != null) {
            setState(() {
              _mentionQuery = null;
            });
          }
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadArtifacts();
    });
    _setupWsListeners();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final show = _scrollController.position.pixels < _scrollController.position.maxScrollExtent - 100;
      if (show != _showScrollToBottom) {
        setState(() => _showScrollToBottom = show);
      }
      
      // Fetch more history when scrolled near the top
      if (_scrollController.position.pixels <= 100) {
        _fetchHistory();
      }
    });
  }



  void _loadConversation(String id) {
    final ws = ref.read(wsClientProvider);
    if (_conversationId != null) {
      ws.unsubscribe(_conversationId!);
    }
    setState(() {
      _conversationId = id;
      _events.clear();
      _displayItemsDirty = true;
      _seenStepIndices.clear();
      _errorMsg = null;
      _hasMoreHistory = true;
      _isLoadingHistory = false;
    });
    if (ws.connectionState == WsConnectionState.connected) {
      ws.subscribe(id);
    }
    
    // Fetch conversation metadata to get workspace path
    ref.read(apiClientProvider).getConversationMetadata(id).then((meta) {
      if (!mounted || _conversationId != id) return;
      final workspace = meta['workspace'] as String?;
      if (workspace != null && workspace.isNotEmpty) {
        ref.read(activeWorkspaceProvider.notifier).setWorkspace(workspace);
      }
    }).catchError((_) {});
    
    // Preload overview data
    ref.read(overviewDataProvider(id).future);
    
    // Fetch initial history chunk
    _fetchHistory(initial: true);

    // Load artifacts for this conversation
    _loadArtifacts();
  }

  Future<void> _loadArtifacts() async {
    if (!mounted || _conversationId == null) return;
    try {
      final client = ref.read(apiClientProvider);
      final artifacts = await client.getArtifacts(_conversationId!);
      if (mounted) setState(() => _conversationArtifacts = artifacts);
    } catch (e) {
      debugPrint('Error loading artifacts: $e');
    }
  }

  Future<void> _fetchHistory({bool initial = false}) async {
    if (_isLoadingHistory || !_hasMoreHistory || _conversationId == null) return;
    setState(() {
      _isLoadingHistory = true;
    });
    
    try {
      final client = ref.read(apiClientProvider);
      final beforeIndex = initial || _events.isEmpty ? null : _events.first.stepIndex;
      
      final historyData = await client.getHistory(_conversationId!, limit: 20, beforeIndex: beforeIndex);
      final newEvents = historyData.map((e) => TranscriptEvent.fromJson(e as Map<String, dynamic>)).toList();
      
      if (!mounted) return;
      
      setState(() {
        if (newEvents.length < 20) {
          _hasMoreHistory = false;
        }
        for (final e in newEvents) {
          if (!_seenStepIndices.contains(e.stepIndex)) {
            _seenStepIndices.add(e.stepIndex);
            _events.add(e);
          }
        }
        _events.sort((a, b) => a.stepIndex.compareTo(b.stepIndex));
        _displayItemsDirty = true;
        _isLoadingHistory = false;
      });
      
      if (initial) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  void _startNewConversation() {
    final ws = ref.read(wsClientProvider);
    if (_conversationId != null) {
      ws.unsubscribe(_conversationId!);
    }
    setState(() {
      _conversationId = null;
      _events.clear();
      _displayItemsDirty = true;
      _seenStepIndices.clear();
      _errorMsg = null;
    });
  }

  void _setupWsListeners() {
    final ws = ref.read(wsClientProvider);

    // Listen for real-time transcript events
    _eventSub = ws.transcriptStream.listen((event) {
      if (!mounted) return;
      if (event.conversationId != _conversationId) return;
      
      // De-duplicate by stepIndex (history replay can send same steps)
      if (_seenStepIndices.contains(event.stepIndex)) return;
      _seenStepIndices.add(event.stepIndex);

      setState(() {
        int low = 0;
        int high = _events.length - 1;
        while (low <= high) {
          int mid = low + ((high - low) >> 1);
          if (_events[mid].stepIndex < event.stepIndex) {
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }
        _events.insert(low, event);
        _displayItemsDirty = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

      // Invalidate overview cache on stream completion of a step
      if (event.status == 'DONE') {
        ref.invalidate(overviewDataProvider(_conversationId!));
      }
    });

    // If WS is disconnected, trigger connection
    if (ws.connectionState == WsConnectionState.disconnected) {
      ws.connect();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    _messageController.clear();
    setState(() => _isSending = true);

    try {
      final client = ref.read(apiClientProvider);
      
      // Construct model change payload if there is a pending selection
      Map<String, String>? modelChangeMap;
      if (_pendingModelChangeFrom != null && _pendingModelChangeTo != null) {
        modelChangeMap = {
          'from': _pendingModelChangeFrom!,
          'to': _pendingModelChangeTo!,
        };
      }
      
      if (_conversationId == null) {
        // Send initial model change from "None" if first model selection is configured
        final firstModelChange = _selectedModel != 'gemini_3.5_flash_high_fast' 
            ? {'from': 'None', 'to': _getFriendlyModelName(_selectedModel)} 
            : null;

        // Create conversation using the user's actual prompt and mapped CLI model
        final id = await client.createConversation(
          text, 
          model: _getCliModel(_selectedModel),
          selectedModel: _selectedModel,
          modelChange: modelChangeMap ?? firstModelChange,
        );
        if (!mounted) return;
        
        setState(() {
          _conversationId = id;
        });
        
        // Subscribe to WS stream
        ref.read(wsClientProvider).subscribe(id);
      } else {
        await client.sendMessage(
          _conversationId!, 
          text,
          model: _selectedModel,
          modelChange: modelChangeMap,
        );
      }
      
      // Clear pending model change after successful transmission
      _pendingModelChangeFrom = null;
      _pendingModelChangeTo = null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _stateSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      drawer: AppSidebar(
        onConversationSelected: _loadConversation,
        onNewConversation: _startNewConversation,
      ),
      endDrawer: _conversationId != null 
          ? OverviewDrawer(
              conversationId: _conversationId!,
              onConversationSelected: _loadConversation,
            ) 
          : null,
      body: Stack(
        children: [
          // Main Body
          Positioned.fill(
            child: _buildBody(),
          ),

          // Top Header Background Cover (prevents chat content from drawing under system status bar / camera cutout)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: Container(
              color: Theme.of(context).colorScheme.background,
            ),
          ),
          
          // Floating Menu Button
          Positioned(
            top: MediaQuery.paddingOf(context).top + 16,
            left: 16,
            child: Builder(
              builder: (ctx) => GestureDetector(
                onTap: () => Scaffold.of(ctx).openDrawer(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.menu,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),

          // Floating Connection Indicator
          Positioned(
            top: MediaQuery.paddingOf(context).top + 24,
            right: 76,
            child: _buildConnectionDot(),
          ),

          // Floating Overview Button
          if (_conversationId != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 16,
              right: 16,
              child: Builder(
                builder: (ctx) => GestureDetector(
                  onTap: () => Scaffold.of(ctx).openEndDrawer(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),

          // Input Area (Fixed Bottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildInputArea(),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionDot() {
    return Consumer(
      builder: (context, ref, _) {
        final ws = ref.watch(wsClientProvider);
        final isConnected = ws.connectionState == WsConnectionState.connected;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
            boxShadow: [
              BoxShadow(
                color: (isConnected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error)
                    .withValues(alpha: 0.4),
                blurRadius: 8,
              ),
            ],
          ),
        );
      },
    );
  }

  List<dynamic> _buildDisplayItems() {
    if (!_displayItemsDirty) return _cachedDisplayItems;

    final List<dynamic> items = [];
    final List<TranscriptEvent> currentGroup = [];

    for (int i = 0; i < _events.length; i++) {
      final event = _events[i];
      final cat = event.category.toLowerCase();
      final source = event.source.toUpperCase();

      if ((cat == 'user_message' && source == 'USER_EXPLICIT') || cat == 'agent_response') {
        if (currentGroup.isNotEmpty) {
          items.add(ProcessGroup(
            events: currentGroup.toList(),
            isCompleted: true,
          ));
          currentGroup.clear();
        }
        items.add(event);
      } else {
        currentGroup.add(event);
      }
    }

    if (currentGroup.isNotEmpty) {
      items.add(ProcessGroup(
        events: currentGroup.toList(),
        isCompleted: false,
      ));
    }

    _cachedDisplayItems = items;
    _displayItemsDirty = false;
    return items;
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
            SizedBox(height: 16),
            Text(
              'Connecting to Antigravity...',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMsg!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMsg = null;
                    _isLoading = true;
                    _conversationId = null;
                  });
                  _setupWsListeners();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final displayItems = _buildDisplayItems();

    return displayItems.isEmpty && !_isLoadingHistory
        ? _buildEmptyState()
        : ListView.separated(
            controller: _scrollController,
            padding: EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: MediaQuery.paddingOf(context).top + 76.0,
              bottom: MediaQuery.paddingOf(context).bottom + 220.0,
            ),
            itemCount: displayItems.length + (_hasMoreHistory ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 24),
            itemBuilder: (context, index) {
              if (_hasMoreHistory && index == 0) {
                return Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                    child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                  ),
                );
              }
              final eventIndex = _hasMoreHistory ? index - 1 : index;
              final item = displayItems[eventIndex];
              if (item is ProcessGroup) {
                return _buildProcessGroupWidget(item);
              } else if (item is TranscriptEvent) {
                return _buildEventItem(item);
              }
              return const SizedBox.shrink();
            },
          );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              'AG',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Session initialized.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to begin.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessGroupWidget(ProcessGroup group) {
    return ProcessGroupCard(
      group: group,
      eventBuilder: (event) => _buildEventItem(event),
    );
  }

  Widget _buildEventItem(TranscriptEvent event) {
    final cat = event.category.toLowerCase();
    if (cat == 'user_message') {
      final parsedTime = DateTime.tryParse(event.timestamp);
      return _buildUserBubble(event.content ?? event.summary, parsedTime);
    } else if (cat == 'agent_response') {
      return _buildAgentBubble(event.content ?? event.summary, event);
    } else if (cat == 'tool_invocation') {
      final isDone = event.status.toLowerCase() == 'done';
      return _buildToolCallCard(event, isProcessing: !isDone);
    } else if (cat == 'tool_result') {
      return _buildToolCallCard(event, isProcessing: false);
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildUserBubble(String text, DateTime? timestamp) {
    final timeStr = timestamp != null
        ? "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}"
        : "";

    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16.0),
                bottomLeft: Radius.circular(16.0),
                bottomRight: Radius.circular(16.0),
                topRight: Radius.zero,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          if (timeStr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: Text(
                timeStr,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAgentBubble(String text, TranscriptEvent event) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.95),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: text.isEmpty ? '...' : text,
              styleSheet: MarkdownStyleSheet(
                p: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 17,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.5,
                  fontWeight: FontWeight.normal,
                ),
                code: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                  backgroundColor: Colors.transparent,
                ),
                codeblockDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                codeblockPadding: const EdgeInsets.all(16.0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCallCard(TranscriptEvent event, {required bool isProcessing}) {
    final toolName = event.toolCalls?.first.summary ?? event.summary;
    final content = event.content ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.3),
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2.0),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(12.0),
          bottomRight: Radius.circular(12.0),
        ),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.terminal,
                      color: Theme.of(context).colorScheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        toolName.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isProcessing ? 'PROCESSING' : 'COMPLETED',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Text(
                content,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final activeModelDisplay = _getFriendlyModelName(_selectedModel);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_mentionQuery != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: _buildMentionAutocomplete(),
          ),
        if (_showScrollToBottom)
          Padding(
            padding: const EdgeInsets.only(right: 16.0, bottom: 8.0),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_downward, color: Theme.of(context).colorScheme.onSurface, size: 20),
                onPressed: _scrollToBottom,
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
          padding: EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: 12.0,
            bottom: MediaQuery.paddingOf(context).bottom + 16.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Text area container
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 5,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: const InputDecoration(
                      filled: false,
                      hintText: 'Ask anything, @ to mention, / for actions',
                      hintStyle: TextStyle(color: Color(0xFF666666)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12.0, bottom: 12.0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 32,
                    width: 32,
                    decoration: BoxDecoration(
                      color: _isSending
                          ? Theme.of(context).colorScheme.surfaceContainerHigh
                          : Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: _isSending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_upward, color: Colors.black, size: 18),
                      onPressed: _isSending ? null : _sendMessage,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tool buttons & Model Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, color: Color(0xFF999999), size: 22),
                    onPressed: () {},
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  IconButton(
                    icon: const Icon(Icons.mic, color: Color(0xFF999999), size: 22),
                    onPressed: () {},
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  IconButton(
                    icon: const Icon(Icons.alternate_email, color: Color(0xFF999999), size: 22),
                    onPressed: () {
                      final text = _messageController.text;
                      final selection = _messageController.selection;
                      if (selection.isValid) {
                        _messageController.value = TextEditingValue(
                          text: text.replaceRange(selection.start, selection.end, '@'),
                          selection: TextSelection.collapsed(offset: selection.start + 1),
                        );
                      } else {
                        _messageController.text = '$text@';
                        _messageController.selection = TextSelection.collapsed(offset: _messageController.text.length);
                      }
                    },
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _showModelPicker,
                child: Row(
                  children: [
                    Text(
                      activeModelDisplay,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.expand_less,
                      size: 14,
                      color: Color(0xFF666666),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
      ],
    );
  }

  void _showModelPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'SELECT MODEL',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      _buildModelTile('gemini_3.5_flash_medium', 'Gemini 3.5 Flash (Medium)'),
                      _buildModelTile('gemini_3.5_flash_high_fast', 'Gemini 3.5 Flash (High) Fast'),
                      _buildModelTile('gemini_3.5_flash_low', 'Gemini 3.5 Flash (Low)'),
                      _buildModelTile('gemini_3.1_pro_low', 'Gemini 3.1 Pro (Low)'),
                      _buildModelTile('gemini_3.1_pro_high', 'Gemini 3.1 Pro (High)'),
                      _buildModelTile('claude_sonnet_4.6_thinking', 'Claude Sonnet 4.6 (Thinking)'),
                      _buildModelTile('claude_opus_4.6_thinking', 'Claude Opus 4.6 (Thinking)'),
                      _buildModelTile('gpt_oss_120b_medium', 'GPT-OSS 120B (Medium)'),
                    ],
                  ),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Widget _buildModelTile(String modelKey, String displayName) {
    final isSelected = _selectedModel == modelKey;
    return ListTile(
      title: Text(
        displayName,
        style: GoogleFonts.jetBrainsMono(
          color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: () {
        final oldModelKey = _selectedModel;
        if (oldModelKey != modelKey) {
          setState(() {
            _selectedModel = modelKey;
            _pendingModelChangeFrom = _getFriendlyModelName(oldModelKey);
            _pendingModelChangeTo = _getFriendlyModelName(modelKey);
          });
        }
        Navigator.pop(context);
      },
    );
  }

  Widget _buildMentionAutocomplete() {
    if (_mentionQuery == null) return const SizedBox.shrink();
    final query = _mentionQuery!.toLowerCase();
    final matches = _conversationArtifacts.where((a) => (a['filename'] as String).toLowerCase().contains(query)).take(50).toList();
    if (matches.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.5), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      constraints: const BoxConstraints(maxHeight: 250),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                SizedBox(width: 6),
                Text('Conversation', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: matches.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
              itemBuilder: (context, index) {
                final artifact = matches[index];
                final filename = artifact['filename'] as String;
                final isMedia = artifact['isMedia'] as bool;
                final absolutePath = artifact['absolutePath'] as String;
                
                String displayName = filename;
                if (filename.endsWith('.md')) {
                  displayName = filename.replaceAll('_', ' ').replaceAll('.md', '');
                  displayName = displayName.split(' ').map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1)).join(' ');
                } else if (isMedia) {
                  displayName = 'Media (Artifact)';
                }

                return ListTile(
                  dense: true,
                  leading: Icon(isMedia ? Icons.image_outlined : Icons.description_outlined, color: Theme.of(context).colorScheme.secondary, size: 18),
                  title: Text(displayName, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
                  subtitle: Text(filename, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    final link = isMedia ? '![$displayName](file:///$absolutePath) ' : '[$displayName](file:///$absolutePath) ';
                    final currentText = _messageController.text;
                    final currentSel = _messageController.selection;
                    if (currentSel.isValid) {
                      final newText = currentText.replaceRange(currentSel.start, currentSel.end, link);
                      _messageController.value = TextEditingValue(
                        text: newText,
                        selection: TextSelection.collapsed(offset: currentSel.start + link.length),
                      );
                    } else {
                      _messageController.text += link;
                    }
                    setState(() => _mentionQuery = null);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProcessGroupCard extends StatefulWidget {
  final ProcessGroup group;
  final Widget Function(TranscriptEvent) eventBuilder;

  const ProcessGroupCard({
    super.key,
    required this.group,
    required this.eventBuilder,
  });

  @override
  State<ProcessGroupCard> createState() => _ProcessGroupCardState();
}

class _ProcessGroupCardState extends State<ProcessGroupCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = !widget.group.isCompleted;
  }

  @override
  void didUpdateWidget(ProcessGroupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.isCompleted != widget.group.isCompleted) {
      if (widget.group.isCompleted) {
        _isExpanded = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    
    int toolCalls = group.events.where((e) => e.category.toLowerCase() == 'tool_invocation').length;
    bool hasThinking = group.events.any((e) => e.hasThinking);
    
    String titleText = "Processing...";
    if (group.isCompleted) {
      if (toolCalls > 0) {
        titleText = "Ran $toolCalls tool${toolCalls > 1 ? 's' : ''}";
        if (hasThinking) titleText += " and reasoned";
      } else if (hasThinking) {
        titleText = "Reasoned internally";
      } else {
        titleText = "System processes";
      }
    }

    return Card(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _isExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _isExpanded = expanded;
            });
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          leading: Icon(
            group.isCompleted ? Icons.check_circle_outline : Icons.sync,
            color: group.isCompleted ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.secondary,
            size: 20,
          ),
          title: Text(
            titleText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 8),
          children: [
            for (int i = 0; i < group.events.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              widget.eventBuilder(group.events[i]),
            ],
          ],
        ),
      ),
    );
  }
}

