import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../providers/config_provider.dart';
import '../providers/conversations_provider.dart';
import '../services/api_client.dart';
import '../widgets/app_sidebar.dart';
import '../theme/design_system.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isServerHealthy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(conversationsProvider.notifier).refreshBackground();
      _checkHealth();
    });
  }

  Future<void> _checkHealth() async {
    final client = ref.read(apiClientProvider);
    final healthy = await client.checkHealth();
    if (mounted) {
      setState(() {
        _isServerHealthy = healthy;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(configProvider);
    final username = configAsync.value?.username ?? 'User';
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: colorScheme.onSurfaceVariant),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      drawer: AppSidebar(
        onNewConversation: () {
          context.push('/chat');
        },
        onConversationSelected: (id) {
          context.push('/chat?id=$id');
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _checkHealth();
          await ref.read(conversationsProvider.notifier).refreshBackground();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Greeting Section
              Text(
                'Hi, $username',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ready to build cool stuff?',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),

              // Status Cards
              Row(
                children: [
                  Expanded(
                    child: _buildStatusCard(
                      context: context,
                      title: 'Server Status',
                      subtitle: _isServerHealthy ? 'Connected' : 'Disconnected',
                      icon: _isServerHealthy ? Icons.check_circle : Icons.error,
                      color: _isServerHealthy ? Colors.green : colorScheme.error,
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatusCard(
                      context: context,
                      title: 'Builds & APKs',
                      subtitle: 'View Artifacts',
                      icon: Icons.build_circle_outlined,
                      color: colorScheme.secondary,
                      onTap: () => context.push('/builds'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Projects Section
              Text(
                'Your Projects',
                style: DesignSystem.textTheme.headlineMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              ref.watch(conversationsProvider).when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (err, stack) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Failed to load projects: $err',
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
                ),
                data: (conversations) {
                  if (conversations.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                        color: colorScheme.surfaceContainerLow,
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.folder_off_outlined, size: 48, color: colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text(
                            'No projects yet.',
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Create New Project'),
                            onPressed: () => context.push('/pc_file_manager'),
                          )
                        ],
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
                      final project = entry.key;
                      final chats = entry.value;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: colorScheme.outlineVariant),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          leading: Icon(Icons.folder, color: colorScheme.onSurfaceVariant, size: 28),
                          title: Text(
                            project,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Text(
                            '${chats.length} chat${chats.length == 1 ? '' : 's'}',
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                          children: chats.map((chat) {
                            final updatedAt = DateTime.parse(chat['updatedAt']).toLocal();
                            return InkWell(
                              onTap: () {
                                context.push('/chat?id=${chat['id']}');
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(50))),
                                  color: colorScheme.surfaceContainerLowest,
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.chat_bubble_outline, size: 16, color: colorScheme.secondary),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            chat['title'] ?? 'New Chat',
                                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            timeago.format(updatedAt),
                                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right, size: 16, color: colorScheme.onSurfaceVariant),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        onPressed: () {
          context.push('/chat');
        },
        icon: const Icon(Icons.add),
        label: const Text('New Chat'),
      ),
    );
  }

  Widget _buildStatusCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(50)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
