import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/file_provider.dart';


class FileViewerScreen extends ConsumerWidget {
  final String path;

  const FileViewerScreen({super.key, required this.path});

  Future<String> _downloadFile(String filename, String content, String customPath) async {
    if (kIsWeb) {
      return 'Downloads not supported on web client';
    }

    try {
      io.Directory? tempDir;
      if (customPath.isNotEmpty) {
        tempDir = io.Directory(customPath);
        if (!await tempDir.exists()) {
          await tempDir.create(recursive: true);
        }
      } else {
        if (io.Platform.isAndroid) {
          tempDir = io.Directory('/storage/emulated/0/Download');
          if (!await tempDir.exists()) {
            tempDir = await getExternalStorageDirectory();
          }
        } else if (io.Platform.isIOS) {
          tempDir = await getApplicationDocumentsDirectory();
        } else {
          tempDir = await getDownloadsDirectory();
        }
      }

      tempDir ??= await getApplicationDocumentsDirectory();

      final filePath = '${tempDir.path}/$filename';
      final file = io.File(filePath);
      await file.writeAsString(content);
      return filePath;
    } catch (e) {
      final tempDir = await getApplicationDocumentsDirectory();
      final filePath = '${tempDir.path}/$filename';
      final file = io.File(filePath);
      await file.writeAsString(content);
      return filePath;
    }
  }

  void _showDownloadConfirmDialog(BuildContext context, String filename, String content, String defaultCustomPath) async {
    String resolvedDefaultPath = defaultCustomPath;
    if (resolvedDefaultPath.isEmpty && !kIsWeb) {
      try {
        io.Directory? tempDir;
        if (io.Platform.isAndroid) {
          tempDir = io.Directory('/storage/emulated/0/Download');
          if (!await tempDir.exists()) {
            tempDir = await getExternalStorageDirectory();
          }
        } else if (io.Platform.isIOS) {
          tempDir = await getApplicationDocumentsDirectory();
        } else {
          tempDir = await getDownloadsDirectory();
        }
        tempDir ??= await getApplicationDocumentsDirectory();
        resolvedDefaultPath = tempDir.path;
      } catch (e) {
        resolvedDefaultPath = '';
      }
    }

    final controller = TextEditingController(text: resolvedDefaultPath);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        final dlgColorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: dlgColorScheme.surfaceContainerHigh,
          title: Text('Download File', style: TextStyle(color: dlgColorScheme.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirm or modify the directory path to save "$filename":',
                style: TextStyle(color: dlgColorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      style: TextStyle(color: dlgColorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Destination Folder',
                        labelStyle: TextStyle(color: dlgColorScheme.onSurfaceVariant),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: dlgColorScheme.outline),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: dlgColorScheme.primary),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.folder_open, color: dlgColorScheme.primary),
                    tooltip: 'Pick Directory',
                    onPressed: () async {
                      try {
                        final path = await FilePicker.platform.getDirectoryPath();
                        if (path != null) {
                          controller.text = path;
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to pick directory: $e')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Cancel', style: TextStyle(color: dlgColorScheme.onSurfaceVariant)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text('Download', style: TextStyle(color: dlgColorScheme.primary)),
              onPressed: () async {
                final targetPath = controller.text.trim();
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                Navigator.of(context).pop();
                try {
                  final savedPath = await _downloadFile(filename, content, targetPath);
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('File saved to: $savedPath')),
                  );
                } catch (e) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('Failed to save file: $e')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final fileContentAsync = ref.watch(fileContentProvider(path));
    final filename = path.split('/').last;
    final customPath = ref.watch(customDownloadLocationProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          filename,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        backgroundColor: colorScheme.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
        actions: fileContentAsync.maybeWhen(
          data: (data) {
            final content = data['content'] as String? ?? '';
            return [
              IconButton(
                icon: Icon(Icons.copy, color: colorScheme.onSurface),
                tooltip: 'Copy Content',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Content copied to clipboard')),
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.download, color: colorScheme.onSurface),
                tooltip: 'Download File',
                onPressed: () => _showDownloadConfirmDialog(context, filename, content, customPath),
              ),
            ];
          },
          orElse: () => [],
        ),
      ),
      body: fileContentAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: colorScheme.primary),
        ),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: colorScheme.error, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Failed to read file',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString().replaceAll('Exception:', '').trim(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          final content = data['content'] as String? ?? '';
          return Container(
            color: colorScheme.surfaceContainerLow,
            height: double.infinity,
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  content,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.9),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
