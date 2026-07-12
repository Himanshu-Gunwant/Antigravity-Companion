import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/overview.dart';
import '../services/api_client.dart';

import '../screens/artifact_viewer_screen.dart';

class OverviewDrawer extends ConsumerStatefulWidget {
  final String conversationId;
  final void Function(String)? onConversationSelected;

  const OverviewDrawer({
    super.key, 
    required this.conversationId,
    this.onConversationSelected,
  });

  @override
  ConsumerState<OverviewDrawer> createState() => _OverviewDrawerState();
}

class _OverviewDrawerState extends ConsumerState<OverviewDrawer> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final overviewAsyncValue = ref.watch(overviewDataProvider(widget.conversationId));

    return Drawer(
      backgroundColor: colorScheme.surfaceDim,
      child: SafeArea(
        child: overviewAsyncValue.when(
          loading: () => Center(child: CircularProgressIndicator(color: colorScheme.primary)),
          error: (error, stack) => Center(
            child: Text('Error: $error', style: TextStyle(color: colorScheme.error)),
          ),
          data: (data) {
            return ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildSubagentsSection(data.subagents),
                const SizedBox(height: 16),
                _buildFilesChangedSection(data.filesChanged),
                const SizedBox(height: 16),
                _buildArtifactsSection(data.artifacts),
                const SizedBox(height: 16),
                _buildBackgroundTasksSection(data.backgroundTasks),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.menu, color: colorScheme.onSurfaceVariant, size: 20),
        const SizedBox(width: 8),
        Text('Overview', style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        )),
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        )),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(count.toString(), style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
          )),
        ),
      ],
    );
  }

  Widget _buildSubagentsSection(List<SubagentInfo> items) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: _buildSectionHeader('Subagents', items.length),
        children: items.map((e) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(e.name, style: TextStyle(color: colorScheme.onSurface)),
          subtitle: Text(e.id, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
          onTap: widget.onConversationSelected != null && e.id != 'Unknown' && e.id != 'research' && e.id != 'self'
              ? () {
                  Navigator.of(context).pop(); // Close drawer
                  widget.onConversationSelected!(e.id);
                }
              : null,
        )).toList(),
      ),
    );
  }

  Widget _buildFilesChangedSection(List<FileChangeInfo> items) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: _buildSectionHeader('Files Changed', items.length),
        children: items.map((e) {
          final isJs = e.path.endsWith('.js');
          final isTs = e.path.endsWith('.ts');
          final isDart = e.path.endsWith('.dart');
          
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Text(isJs ? 'JS' : isTs ? 'TS' : isDart ? 'DART' : 'TXT', 
                  style: TextStyle(
                    color: isJs ? Colors.yellow : isTs ? Colors.blue : isDart ? Colors.cyan : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  )
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.path.split('/').last, 
                    style: TextStyle(color: colorScheme.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (e.additions > 0)
                  Text('+${e.additions}', style: TextStyle(color: colorScheme.primary, fontSize: 12)),
                const SizedBox(width: 4),
                if (e.deletions > 0)
                  Text('-${e.deletions}', style: TextStyle(color: colorScheme.error, fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildArtifactsSection(List<ArtifactInfo> items) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: _buildSectionHeader('Artifacts', items.length),
        children: items.map((e) {
          final filename = e.path.split('/').last;
          return InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ArtifactViewerScreen(
                    conversationId: widget.conversationId,
                    filename: filename,
                    isMedia: e.iconType == 'media',
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(e.iconType == 'media' ? Icons.image_outlined : Icons.description_outlined,
                    color: colorScheme.onSurfaceVariant,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(e.name, style: TextStyle(color: colorScheme.onSurface)),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBackgroundTasksSection(List<BackgroundTaskInfo> items) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: _buildSectionHeader('Background Tasks', items.length),
        children: items.map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2.0),
                child: Icon(Icons.sync, color: colorScheme.onSurfaceVariant, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(e.command, 
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }
}
