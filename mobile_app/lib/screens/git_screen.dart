import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../providers/git_provider.dart';
import '../providers/file_provider.dart';
import '../models/git_status.dart';
import '../services/api_client.dart';

import '../widgets/app_sidebar.dart';

class GitScreen extends ConsumerStatefulWidget {
  const GitScreen({super.key});

  @override
  ConsumerState<GitScreen> createState() => _GitScreenState();
}

class _GitScreenState extends ConsumerState<GitScreen> {
  final TextEditingController _commitMessageController = TextEditingController();
  final TextEditingController _subPathController = TextEditingController();
  final Set<String> _selectedFiles = {};
  bool _isOperating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _subPathController.text = ref.read(gitSubPathProvider);
      }
    });
  }

  @override
  void dispose() {
    _commitMessageController.dispose();
    _subPathController.dispose();
    super.dispose();
  }

  void _showResultSnackBar(String operation, String output, {bool isError = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? colorScheme.error : colorScheme.surfaceContainer,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isError ? '$operation Failed' : '$operation Successful',
              style: TextStyle(
                color: isError ? colorScheme.onError : colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              output.trim().isEmpty ? 'No output returned.' : output,
              style: TextStyle(
                color: isError ? colorScheme.onError.withValues(alpha: 0.7) : colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _handleCommit() async {
    final msg = _commitMessageController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a commit message')),
      );
      return;
    }
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select files to stage and commit')),
      );
      return;
    }

    setState(() => _isOperating = true);
    try {
      final api = ref.read(apiClientProvider);
      final workspace = ref.read(activeWorkspaceProvider);
      final workspaceParam = workspace.isEmpty ? null : workspace;
      final subPath = ref.read(gitSubPathProvider);
      
      // 1. Stage selected files
      await api.gitAdd(_selectedFiles.toList(), workspace: workspaceParam, subPath: subPath);
      
      // 2. Commit staged changes
      final output = await api.gitCommit(msg, workspace: workspaceParam, subPath: subPath);
      
      _commitMessageController.clear();
      _selectedFiles.clear();
      _showResultSnackBar('Commit', output);
      
      // Refresh providers
      ref.invalidate(gitStatusProvider);
      ref.invalidate(gitLogProvider);
    } catch (e) {
      _showResultSnackBar('Commit', e.toString().replaceAll('Exception:', '').trim(), isError: true);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _handlePush() async {
    setState(() => _isOperating = true);
    try {
      final workspace = ref.read(activeWorkspaceProvider);
      final workspaceParam = workspace.isEmpty ? null : workspace;
      final subPath = ref.read(gitSubPathProvider);
      final output = await ref.read(apiClientProvider).gitPush(workspace: workspaceParam, subPath: subPath);
      _showResultSnackBar('Push', output);
      ref.invalidate(gitStatusProvider);
      ref.invalidate(gitLogProvider);
    } catch (e) {
      _showResultSnackBar('Push', e.toString().replaceAll('Exception:', '').trim(), isError: true);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  Future<void> _handlePull() async {
    setState(() => _isOperating = true);
    try {
      final workspace = ref.read(activeWorkspaceProvider);
      final workspaceParam = workspace.isEmpty ? null : workspace;
      final subPath = ref.read(gitSubPathProvider);
      final output = await ref.read(apiClientProvider).gitPull(workspace: workspaceParam, subPath: subPath);
      _showResultSnackBar('Pull', output);
      ref.invalidate(gitStatusProvider);
      ref.invalidate(gitLogProvider);
    } catch (e) {
      _showResultSnackBar('Pull', e.toString().replaceAll('Exception:', '').trim(), isError: true);
    } finally {
      if (mounted) setState(() => _isOperating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusAsync = ref.watch(gitStatusProvider);
    final logAsync = ref.watch(gitLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Git Workspace', style: Theme.of(context).textTheme.headlineMedium),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      drawer: AppSidebar(
        onConversationSelected: (id) => context.go('/chat'),
        onNewConversation: () => context.go('/chat'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _subPathController,
                        style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Sub-Repository Path (e.g. frontend)',
                          labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                          prefixIcon: Icon(Icons.folder_open, color: colorScheme.primary, size: 18),
                          isDense: true,
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.outline)),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.primary)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        ref.read(gitSubPathProvider.notifier).setPath(_subPathController.text.trim());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.surfaceContainerHigh,
                        foregroundColor: colorScheme.onSurface,
                      ),
                      child: const Text('Load'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 1. Sync & Info Header Card
                statusAsync.when(
                  loading: () => Center(child: CircularProgressIndicator(color: colorScheme.primary)),
                  error: (err, stack) => _buildErrorCard('Failed to load status', err.toString()),
                  data: (status) => _buildStatusHeader(status),
                ),
                const SizedBox(height: 16),

                // 2. Changes & Commit Card
                statusAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (err, stack) => const SizedBox.shrink(),
                  data: (status) {
                    final allChanged = [
                      ...status.changedFiles.map((f) => f.path),
                      ...status.untrackedFiles
                    ];
                    
                    if (allChanged.isEmpty) {
                      return _buildCleanWorkingTreeCard();
                    }
                    return _buildCommitCard(status);
                  },
                ),
                const SizedBox(height: 16),

                // 3. Commit History (Log)
                Text(
                  'Recent Commits',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 8),
                logAsync.when(
                  loading: () => Center(child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(color: colorScheme.primary),
                  )),
                  error: (err, stack) => _buildErrorCard('Failed to load commits', err.toString()),
                  data: (log) => _buildCommitLogList(log),
                ),
              ],
            ),
          ),
          if (_isOperating)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Performing Git operation...',
                      style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String title, String details) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(details, style: TextStyle(color: colorScheme.error.withValues(alpha: 0.8), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildStatusHeader(GitStatus status) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAhead = status.ahead > 0;
    final isBehind = status.behind > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fork_right, color: colorScheme.primary, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Branch: ${status.branch}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (status.upstream != null)
                      Text(
                        'Upstream: ${status.upstream}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSyncStatIndicator(
                  Icons.arrow_upward,
                  '${status.ahead} commits ahead',
                  isAhead ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: _buildSyncStatIndicator(
                  Icons.arrow_downward,
                  '${status.behind} commits behind',
                  isBehind ? colorScheme.error : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isOperating ? null : _handlePull,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Pull'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.surfaceContainerHigh,
                    foregroundColor: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isOperating ? null : _handlePush,
                  icon: const Icon(Icons.upload, size: 16),
                  label: const Text('Push'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.secondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatIndicator(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  Widget _buildCleanWorkingTreeCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, color: colorScheme.primary, size: 48),
          const SizedBox(height: 16),
          Text(
            'Working tree clean',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'No uncommitted changes detected.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildCommitCard(GitStatus status) {
    final colorScheme = Theme.of(context).colorScheme;
    final changed = status.changedFiles;
    final untracked = status.untrackedFiles;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Stage & Commit',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 16),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    final List<String> allPaths = <String>[
                      ...changed.map((f) => f.path),
                      ...untracked
                    ];
                    if (_selectedFiles.length == allPaths.length) {
                      _selectedFiles.clear();
                    } else {
                      _selectedFiles.addAll(allPaths);
                    }
                  });
                },
                child: Text(
                  _selectedFiles.length == (changed.length + untracked.length)
                      ? 'Deselect All'
                      : 'Select All',
                  style: TextStyle(color: colorScheme.primary, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Changed list
          ...changed.map((f) => _buildFileCheckbox(f.path, f.status, f.staged)),
          // Untracked list
          ...untracked.map((path) => _buildFileCheckbox(path, 'untracked', false)),
          const SizedBox(height: 16),
          TextField(
            controller: _commitMessageController,
            decoration: const InputDecoration(
              hintText: 'Enter commit message...',
            ),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isOperating ? null : _handleCommit,
              icon: const Icon(Icons.commit),
              label: const Text('Stage & Commit Selected'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCheckbox(String filePath, String type, bool staged) {
    final colorScheme = Theme.of(context).colorScheme;
    final filename = filePath.split('/').last;
    final isUntracked = type == 'untracked';

    // Semantic status colors — keep as-is
    Color typeColor = Colors.yellow;
    String typeLabel = 'M';

    if (isUntracked) {
      typeColor = Colors.green;
      typeLabel = '?';
    } else if (type == 'added') {
      typeColor = Colors.green;
      typeLabel = 'A';
    } else if (type == 'deleted') {
      typeColor = Colors.red;
      typeLabel = 'D';
    }

    return CheckboxListTile(
      value: _selectedFiles.contains(filePath),
      onChanged: (val) {
        setState(() {
          if (val == true) {
            _selectedFiles.add(filePath);
          } else {
            _selectedFiles.remove(filePath);
          }
        });
      },
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              border: Border.all(color: typeColor.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              typeLabel,
              style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () {
                context.push('/git/diff?file=${Uri.encodeComponent(filePath)}&staged=$staged');
              },
              child: Text(
                filename,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(filePath, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: colorScheme.primary,
      checkColor: colorScheme.onPrimary,
    );
  }

  Widget _buildCommitLogList(List<dynamic> log) {
    final colorScheme = Theme.of(context).colorScheme;
    if (log.isEmpty) {
      return Center(
        child: Text(
          'No commits found',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: log.length,
      itemBuilder: (context, index) {
        final commit = log[index];
        final dt = DateTime.fromMillisecondsSinceEpoch(commit.timestamp * 1000);
        final timeagoStr = timeago.format(dt);

        return Card(
          color: colorScheme.surfaceContainerLow,
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: ListTile(
            title: Text(
              commit.message,
              style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              '${commit.author} • $timeagoStr',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                commit.shortHash,
                style: TextStyle(color: colorScheme.primary, fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            onTap: () {
              context.push('/git/diff?hash=${commit.hash}');
            },
          ),
        );
      },
    );
  }
}
