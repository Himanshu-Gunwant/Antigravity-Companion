import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../providers/build_provider.dart';
import '../repositories/build_repository.dart';
import '../theme/design_system.dart';
import '../models/build_artifact.dart';

class BuildsScreen extends ConsumerStatefulWidget {
  const BuildsScreen({super.key});

  @override
  ConsumerState<BuildsScreen> createState() => _BuildsScreenState();
}

class _BuildsScreenState extends ConsumerState<BuildsScreen> {
  final Set<String> _downloadingIds = {};
  final Map<String, double> _downloadProgress = {};

  Future<void> _downloadAndInstall(BuildArtifact build) async {
    if (_downloadingIds.contains(build.id)) return;

    setState(() {
      _downloadingIds.add(build.id);
      _downloadProgress[build.id] = 0.0;
    });

    try {
      await ref.read(buildRepositoryProvider).downloadAndInstall(
        build,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() {
              _downloadProgress[build.id] = received / total;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.onError),
                const SizedBox(width: 8),
                Expanded(child: Text('Download failed: $e')),
              ],
            ),
            backgroundColor: colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingIds.remove(build.id);
          _downloadProgress.remove(build.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final buildsAsync = ref.watch(buildsProvider);
    final buildStatus = ref.watch(buildStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Builds & Artifacts',
          style: DesignSystem.textTheme.headlineMedium?.copyWith(
            letterSpacing: -0.5,
            color: colorScheme.onSurface,
          ),
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: colorScheme.outline,
            height: 1,
          ),
        ),
      ),
      body: Column(
        children: [
          if (buildStatus != 'Idle')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: buildStatus == 'Failed' 
                    ? colorScheme.error.withValues(alpha: 0.1) 
                    : colorScheme.primary.withValues(alpha: 0.05),
                border: Border(
                  bottom: BorderSide(
                    color: buildStatus == 'Failed' 
                        ? colorScheme.error.withValues(alpha: 0.2) 
                        : colorScheme.primary.withValues(alpha: 0.1),
                  ),
                ),
              ),
              width: double.infinity,
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: buildStatus == 'Failed'
                        ? Icon(Icons.error_outline, color: colorScheme.error, size: 16)
                        : CircularProgressIndicator(
                            color: colorScheme.primary,
                            strokeWidth: 2,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    buildStatus == 'Failed' ? 'Agent Build Failed' : 'Agent Status: $buildStatus',
                    style: TextStyle(
                      color: buildStatus == 'Failed' ? colorScheme.error : colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: buildsAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: colorScheme.primary),
              ),
              error: (err, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.error, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load builds',
                      style: DesignSystem.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      err.toString(),
                      style: DesignSystem.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(buildsProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                  ],
                ),
              ),
              data: (builds) {
                if (builds.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.build_circle_outlined, 
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4), 
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No builds available yet.', 
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Trigger a build from your workspace to see it here.',
                          style: DesignSystem.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.surfaceDim,
                  onRefresh: () async {
                    ref.invalidate(buildsProvider);
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    itemCount: builds.length,
                    itemBuilder: (context, index) {
                      final b = builds[index];
                      final isDownloading = _downloadingIds.contains(b.id);
                      final progress = _downloadProgress[b.id] ?? 0.0;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [colorScheme.surfaceContainerLow, colorScheme.surfaceContainerLowest],
                          ),
                          border: Border.all(color: colorScheme.outline),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(18.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _buildIconForType(b.type, colorScheme),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                b.fileName,
                                                style: DesignSystem.textTheme.bodyLarge?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: colorScheme.onSurface,
                                                  fontSize: 14,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (_buildArchBadge(b.fileName, colorScheme) != null) ...[
                                              _buildArchBadge(b.fileName, colorScheme)!,
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${b.name} • ${(b.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB • ${_formatTime(b.modifiedAt)}',
                                          style: DesignSystem.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  _buildActionButton(b, isDownloading, progress, colorScheme),
                                ],
                              ),
                            ),
                            if (isDownloading)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 3,
                                  color: colorScheme.primary.withValues(alpha: 0.1),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: progress,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [colorScheme.primary, colorScheme.secondaryContainer],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildArtifact b, bool isDownloading, double progress, ColorScheme colorScheme) {
    if (isDownloading) {
      return Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.05),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Text(
          '${(progress * 100).toInt()}%',
          style: TextStyle(
            color: colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final isApk = b.type == 'apk';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _downloadAndInstall(b),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.08),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.25),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isApk ? Icons.install_mobile_rounded : Icons.download_rounded,
                color: colorScheme.primary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                isApk ? 'Install' : 'Get',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return 'unknown';
    return timeago.format(dt);
  }

  Widget? _buildArchBadge(String fileName, ColorScheme colorScheme) {
    String? label;
    Color color = colorScheme.primary;
    if (fileName.contains('arm64-v8a')) {
      label = 'ARM64';
      color = const Color(0xFF00FFCC);
    } else if (fileName.contains('armeabi-v7a')) {
      label = 'ARMv7';
      color = const Color(0xFFFF9900);
    } else if (fileName.contains('x86_64')) {
      label = 'x86_64';
      color = const Color(0xFF3399FF);
    } else if (fileName.contains('release') && !fileName.contains('arm') && !fileName.contains('x86')) {
      label = 'Universal';
      color = const Color(0xFFE066FF);
    }

    if (label == null) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildIconForType(String type, ColorScheme colorScheme) {
    IconData icon;
    Color color;
    switch (type) {
      case 'apk':
        icon = Icons.android_rounded;
        color = const Color(0xFF3DDC84); // Android green
        break;
      case 'aab':
        icon = Icons.archive_rounded;
        color = Colors.orangeAccent;
        break;
      case 'web':
        icon = Icons.language_rounded;
        color = Colors.lightBlueAccent;
        break;
      default:
        icon = Icons.insert_drive_file_rounded;
        color = colorScheme.onSurfaceVariant;
    }
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 20),
    );
  }
}
