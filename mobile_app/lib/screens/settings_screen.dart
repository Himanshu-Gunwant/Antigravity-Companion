import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/file_provider.dart';
import '../providers/config_provider.dart';
import '../providers/artifact_cache_provider.dart';
import '../services/api_client.dart';
import '../widgets/quota_card.dart';
import '../widgets/appearance_card.dart';
import '../widgets/account_manager_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _testingConnection = false;
  String _latencyText = '';
  int _cachedApkCount = 0;
  double _cachedApkSizeMb = 0.0;

  @override
  void initState() {
    super.initState();
    // Run diagnostics and check storage on entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runDiagnostics();
      _calculateApkCache();
    });
  }

  void _runDiagnostics() async {
    if (!mounted) return;
    setState(() {
      _testingConnection = true;
      _latencyText = 'Testing latency...';
    });

    final stopwatch = Stopwatch()..start();
    final apiClient = ref.read(apiClientProvider);
    final isHealthy = await apiClient.checkHealth();
    stopwatch.stop();

    if (mounted) {
      setState(() {
        _testingConnection = false;
        if (isHealthy) {
          _latencyText = 'Active (${stopwatch.elapsedMilliseconds} ms)';
        } else {
          _latencyText = 'Offline / Unreachable';
        }
      });
    }
  }

  Future<void> _calculateApkCache() async {
    int count = 0;
    int bytes = 0;
    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      if (await dir.exists()) {
        final list = dir.listSync();
        for (final entity in list) {
          if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
            count++;
            bytes += await entity.length();
          }
        }
      }
    } catch (_) {}

    final customDir = ref.read(customDownloadLocationProvider);
    if (customDir.isNotEmpty) {
      try {
        final dir = Directory(customDir);
        if (await dir.exists()) {
          final list = dir.listSync();
          for (final entity in list) {
            if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
              count++;
              bytes += await entity.length();
            }
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _cachedApkCount = count;
        _cachedApkSizeMb = bytes / (1024 * 1024);
      });
    }
  }

  Future<void> _clearApkCache() async {
    int deletedCount = 0;
    int deletedBytes = 0;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      if (await dir.exists()) {
        final list = dir.listSync();
        for (final entity in list) {
          if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
            deletedBytes += await entity.length();
            await entity.delete();
            deletedCount++;
          }
        }
      }
    } catch (_) {}

    final customDir = ref.read(customDownloadLocationProvider);
    if (customDir.isNotEmpty) {
      try {
        final dir = Directory(customDir);
        if (await dir.exists()) {
          final list = dir.listSync();
          for (final entity in list) {
            if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
              deletedBytes += await entity.length();
              await entity.delete();
              deletedCount++;
            }
          }
        }
      } catch (_) {}
    }

    // Refresh UI numbers
    await _calculateApkCache();

    final sizeClearedMb = deletedBytes / (1024 * 1024);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(
          deletedCount > 0
              ? 'Successfully deleted $deletedCount APK files (${sizeClearedMb.toStringAsFixed(1)} MB cleared)!'
              : 'No downloaded APK files found to delete.',
        ),
      ),
    );
  }

  void _pickDownloadLocation() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final selectedPath = await FilePicker.platform.getDirectoryPath();
      if (selectedPath != null && selectedPath.isNotEmpty) {
        ref.read(customDownloadLocationProvider.notifier).setLocation(selectedPath);
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Download location updated: $selectedPath')),
        );
        // Re-calculate cache size since directory changed
        _calculateApkCache();
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to select directory: ${e.toString()}')),
      );
    }
  }

  void _clearCache() {
    ref.read(artifactCacheProvider.notifier).clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('In-memory view cache cleared successfully!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final configAsync = ref.watch(configProvider);
    final relayUrl = configAsync.value?.relayUrl ?? 'No server configured';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.surface.withValues(alpha: 0.9),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Settings',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: colorScheme.outline, height: 1.0),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              children: [
                _buildSectionHeader('Connection diagnostics'),
                _buildConnectionStatusCard(relayUrl),
                
                const SizedBox(height: 32),
                _buildSectionHeader('Account Quota'),
                const ModelQuotaCard(),

                const SizedBox(height: 32),
                _buildSectionHeader('Accounts'),
                const AccountManagerCard(),

                const SizedBox(height: 32),
                
                const AppearanceCard(),

                const SizedBox(height: 32),
                _buildSectionHeader('Preferences'),
                _buildPreferencesCard(),
                
                const SizedBox(height: 32),
                _buildSectionHeader('Cache & Storage'),
                _buildCacheCard(),
                
                const SizedBox(height: 32),
                _buildSectionHeader('About'),
                _buildAboutCard(),
                
                const SizedBox(height: 48),
                _buildFooterBranding(),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 16),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 11,
          letterSpacing: 2.0,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildConnectionStatusCard(String relayUrl) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasConnection = _latencyText.startsWith('Active');
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _testingConnection
                      ? Colors.amber
                      : (hasConnection ? colorScheme.primary : Colors.redAccent),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _testingConnection
                          ? Colors.amber.withValues(alpha: 0.4)
                          : (hasConnection ? colorScheme.primary.withValues(alpha: 0.4) : Colors.redAccent.withValues(alpha: 0.4)),
                      blurRadius: 6,
                    )
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Relay Server Status',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Address: $relayUrl',
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Latency: $_latencyText',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              TextButton.icon(
                icon: Icon(Icons.refresh, size: 16, color: colorScheme.primary),
                label: Text('Test', style: TextStyle(color: colorScheme.primary, fontSize: 13)),
                onPressed: _testingConnection ? null : _runDiagnostics,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: colorScheme.outline.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daemon Path:',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    ref.watch(configProvider).value?.daemonExecutablePath.isEmpty ?? true 
                        ? 'Not configured' 
                        : ref.watch(configProvider).value!.daemonExecutablePath,
                    style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((ref.watch(configProvider).value?.daemonExecutablePath ?? '').isNotEmpty) ...[
                    TextButton.icon(
                      icon: Icon(Icons.restart_alt, size: 16, color: Colors.orange.shade700),
                      label: Text('Restart', style: TextStyle(color: Colors.orange.shade700, fontSize: 13)),
                      onPressed: () {
                        final execPath = ref.read(configProvider).value!.daemonExecutablePath;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Force restarting daemon...')));
                        ref.read(apiClientProvider).restartDaemon(execPath);
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  TextButton(
                    onPressed: () => _editDaemonPath(ref.read(configProvider).value?.daemonExecutablePath ?? ''),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _editDaemonPath(String currentPath) {
    final controller = TextEditingController(text: currentPath);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Daemon Executable Path'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'C:\\Program Files\\Antigravity\\antigravity.exe',
              border: OutlineInputBorder(),
              helperText: 'Paste the shortcut target path',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final newPath = controller.text.trim();
                final config = ref.read(configProvider).value;
                if (config != null) {
                  ref.read(configProvider.notifier).saveConfig(
                    config.relayUrl,
                    config.apiKey,
                    daemonExecutablePath: newPath,
                  );
                }
                context.pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPreferencesCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _pickDownloadLocation,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.folder_shared, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Download Location',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ref.watch(customDownloadLocationProvider).isEmpty ? 'Default' : 'Custom',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4), size: 20),
                      ],
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

  Widget _buildCacheCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final cacheItems = ref.watch(artifactCacheProvider).length;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _clearCache,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.cleaning_services_outlined, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Clear View Cache',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$cacheItems entries',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3), height: 1),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _clearApkCache,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.install_mobile_rounded, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Delete Downloaded APKs',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_cachedApkCount files (${_cachedApkSizeMb.toStringAsFixed(1)} MB)',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                      ],
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

  Widget _buildAboutCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.info, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(
                'Version',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Text(
            'v0.1.0-alpha',
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterBranding() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          'ANTIGRAVITY',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 6.0,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SECURED END-TO-END ENCRYPTION ENABLED',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 9,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
