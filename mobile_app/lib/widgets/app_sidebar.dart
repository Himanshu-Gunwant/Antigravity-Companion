import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:timeago/timeago.dart' as timeago;
import '../providers/file_provider.dart';
import '../providers/conversations_provider.dart';

class AppSidebar extends ConsumerStatefulWidget {
  final Function(String)? onConversationSelected;
  final VoidCallback? onNewConversation;

  const AppSidebar({
    super.key,
    this.onConversationSelected,
    this.onNewConversation,
  });

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  @override
  void initState() {
    super.initState();
    // Refresh list of projects/conversations in the background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(conversationsProvider.notifier).refreshBackground();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Drawer(
      backgroundColor: colorScheme.surfaceDim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            _buildActionArea(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
                children: [
                  _buildSectionHeader('Projects'),
                  ref.watch(conversationsProvider).when(
                    loading: () => Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator(color: colorScheme.primary)),
                    ),
                    error: (err, stack) => Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Text(
                            'Failed to load chats',
                            style: TextStyle(color: colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                          TextButton(
                            onPressed: () => ref.read(conversationsProvider.notifier).refresh(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                    data: (conversations) {
                      if (conversations.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'No recent chats found',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      final grouped = <String, List<Map<String, dynamic>>>{};
                      for (var c in conversations) {
                        final proj = c['project'] as String? ?? 'General';
                        grouped.putIfAbsent(proj, () => []).add(c);
                      }

                      return Column(
                        children: grouped.entries.map((entry) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent,
                              listTileTheme: const ListTileThemeData(dense: true),
                            ),
                            child: ExpansionTile(
                              leading: Icon(Icons.folder, size: 18, color: colorScheme.onSurfaceVariant),
                              title: Text(
                                entry.key,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                              childrenPadding: const EdgeInsets.only(left: 16),
                              children: entry.value.map((c) {
                                final title = c['title'] ?? 'New Conversation';
                                final updatedAt = DateTime.parse(c['updatedAt'] as String);
                                return _buildNavItem(
                                  icon: Icons.chat_bubble_outline,
                                  title: title,
                                  trailing: timeago.format(updatedAt, locale: 'en_short'),
                                  onTap: () {
                                    if (widget.onConversationSelected != null) {
                                      widget.onConversationSelected!(c['id'] as String);
                                    }
                                    final workspace = c['workspace'] as String?;
                                    if (workspace != null && workspace.isNotEmpty) {
                                      ref.read(activeWorkspaceProvider.notifier).setWorkspace(workspace);
                                    }
                                    Navigator.of(context).pop();
                                  },
                                );
                              }).toList(),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  Divider(color: colorScheme.outlineVariant, height: 1),
                  const SizedBox(height: 16),
                  
                  _buildNavItem(
                    icon: Icons.folder,
                    title: 'File Explorer',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/files');
                    },
                  ),
                  _buildNavItem(
                    icon: Icons.commit,
                    title: 'Git Workspace',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/git');
                    },
                  ),
                  _buildNavItem(
                    icon: Icons.build_circle_outlined,
                    title: 'Builds & Artifacts',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/builds');
                    },
                  ),
                  _buildNavItem(
                    icon: Icons.terminal,
                    title: 'SSH Terminal',
                    titleStyle: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/ssh');
                    },
                  ),
                  _buildNavItem(
                    icon: Icons.settings,
                    title: 'Settings',
                    onTap: () {
                      Navigator.of(context).pop(); // Close drawer
                      context.push('/settings');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
            ),
            alignment: Alignment.center,
            child: Text(
              'AG',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Antigravity',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: -0.5,
                ),
              ),
              Row(
                children: [
                  Text(
                    'COMPANION',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 9,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'v0.1.0',
                    style: TextStyle(
                      color: colorScheme.outlineVariant,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionArea() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop();
                context.go('/dashboard');
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.space_dashboard_outlined, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Home Dashboard',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (widget.onNewConversation != null) {
                  widget.onNewConversation!();
                }
                Navigator.of(context).pop();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'New Conversation',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                Navigator.of(context).pop();
                final result = await context.push<bool>('/pc_file_manager');
                if (result == true && widget.onNewConversation != null) {
                  widget.onNewConversation!();
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.create_new_folder, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'Create Project',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String title,
    String? trailing,
    Widget? trailingWidget,
    Color? iconColor,
    TextStyle? titleStyle,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () {},
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor ?? colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: titleStyle ?? TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?trailingWidget,
              if (trailingWidget == null && trailing != null)
                Text(
                  trailing,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }


}
