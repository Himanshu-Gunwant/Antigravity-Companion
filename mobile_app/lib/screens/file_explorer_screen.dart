import 'dart:io' as io;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/file_provider.dart';

import '../widgets/app_sidebar.dart';
import '../services/api_client.dart';
import '../models/file_node.dart';

class FileExplorerScreen extends ConsumerWidget {
  final String path;

  const FileExplorerScreen({super.key, this.path = ''});

  void _handleDelete(BuildContext context, WidgetRef ref, FileNode node) {

    showDialog(
      context: context,
      builder: (context) {
        final dlgColorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: dlgColorScheme.surfaceContainerHigh,
          title: Text('Delete Item', style: TextStyle(color: dlgColorScheme.onSurface)),
          content: Text('Are you sure you want to delete ${node.name}? This action cannot be undone.'),
          actions: [
            TextButton(
              child: Text('Cancel', style: TextStyle(color: dlgColorScheme.onSurfaceVariant)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text('Delete', style: TextStyle(color: dlgColorScheme.error)),
              onPressed: () async {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                Navigator.of(context).pop();
                try {
                  final api = ref.read(apiClientProvider);
                  final workspace = ref.read(activeWorkspaceProvider);
                  await api.deleteFileOrFolder(node.path, workspace: workspace.isEmpty ? null : workspace);
                  ref.invalidate(filesProvider(path));
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('${node.name} deleted successfully')),
                  );
                } catch (e) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('Failed to delete: ${e.toString().replaceAll('Exception:', '').trim()}')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _handleCreate(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final contentController = TextEditingController();
    String itemType = 'file';
    bool isBinary = false;
    String binaryContentBase64 = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final dlgColorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            backgroundColor: dlgColorScheme.surfaceContainerHigh,
            title: Text('Create New', style: TextStyle(color: dlgColorScheme.onSurface)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: TextStyle(color: dlgColorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      labelStyle: TextStyle(color: dlgColorScheme.onSurfaceVariant),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: dlgColorScheme.outline),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: dlgColorScheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Radio<String>(
                        value: 'file',
                        // ignore: deprecated_member_use
                        groupValue: itemType,
                        activeColor: dlgColorScheme.primary,
                        // ignore: deprecated_member_use
                        onChanged: (val) => setState(() => itemType = val!),
                      ),
                      Text('File', style: TextStyle(color: dlgColorScheme.onSurface)),
                      const SizedBox(width: 20),
                      Radio<String>(
                        value: 'directory',
                        // ignore: deprecated_member_use
                        groupValue: itemType,
                        activeColor: dlgColorScheme.primary,
                        // ignore: deprecated_member_use
                        onChanged: (val) => setState(() => itemType = val!),
                      ),
                      Text('Folder', style: TextStyle(color: dlgColorScheme.onSurface)),
                    ],
                  ),
                  if (itemType == 'file') ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: contentController,
                      maxLines: 2,
                      minLines: 1,
                      enabled: !isBinary,
                      style: TextStyle(color: dlgColorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: isBinary ? 'Binary Content' : 'Content (Optional)',
                        labelStyle: TextStyle(color: dlgColorScheme.onSurfaceVariant),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: dlgColorScheme.outline),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: dlgColorScheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      icon: Icon(Icons.upload_file, color: dlgColorScheme.primary),
                      label: Text('Pick Local File', style: TextStyle(color: dlgColorScheme.primary)),
                      onPressed: () async {
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        try {
                          final result = await FilePicker.platform.pickFiles();
                          if (result != null && result.files.single.path != null) {
                            final pickedFile = io.File(result.files.single.path!);
                            try {
                              final bytes = await pickedFile.readAsBytes();
                              final b64 = base64Encode(bytes);
                              setState(() {
                                nameController.text = result.files.single.name;
                                isBinary = true;
                                binaryContentBase64 = b64;
                                contentController.text = '[Binary File Selected - ${bytes.length} bytes]';
                                itemType = 'file';
                              });
                            } catch (e) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(content: Text('Failed to read file: $e')),
                              );
                              return;
                            }
                          }
                        } catch (e) {
                          final errorStr = e.toString();
                          if (errorStr.contains('MissingPluginException') || errorStr.contains('No implementation found')) {
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(
                                content: Text('Please restart/re-run the app (e.g. run "flutter run") to compile the newly added file picker plugin.'),
                                duration: Duration(seconds: 5),
                              ),
                            );
                          } else {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(content: Text('Failed to pick file: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                child: Text('Cancel', style: TextStyle(color: dlgColorScheme.onSurfaceVariant)),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: Text('Create', style: TextStyle(color: dlgColorScheme.primary)),
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;

                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  Navigator.of(context).pop();
                  try {
                    final api = ref.read(apiClientProvider);
                    final workspace = ref.read(activeWorkspaceProvider);
                    final relativePath = path.isEmpty ? name : '$path/$name';
                    await api.createFileOrFolder(
                      path: relativePath,
                      type: itemType,
                      content: itemType == 'file' 
                          ? (isBinary ? binaryContentBase64 : contentController.text) 
                          : '',
                      base64Encoded: isBinary,
                      workspace: workspace.isEmpty ? null : workspace,
                    );
                    ref.invalidate(filesProvider(path));
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text('${itemType == 'file' ? 'File' : 'Folder'} created successfully')),
                    );
                  } catch (e) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text('Failed to create: ${e.toString().replaceAll('Exception:', '').trim()}')),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final filesAsync = ref.watch(filesProvider(path));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          path.isEmpty ? 'File Explorer' : path.split('/').last,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: path.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      drawer: path.isEmpty
          ? AppSidebar(
              onConversationSelected: (id) => context.go('/chat'),
              onNewConversation: () => context.go('/chat'),
            )
          : null,
      body: filesAsync.when(
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
                  'Failed to load directory',
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
        data: (nodes) {
          if (nodes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open_outlined, color: colorScheme.onSurfaceVariant, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'This directory is empty',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }

          // Sort directories first, then files
          final sortedNodes = [...nodes]..sort((a, b) {
              if (a.type == b.type) {
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              }
              return a.type == 'directory' ? -1 : 1;
            });

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sortedNodes.length,
            separatorBuilder: (context, index) => Divider(
              color: colorScheme.outline,
              height: 1,
            ),
            itemBuilder: (context, index) {
              final node = sortedNodes[index];
              final isDir = node.type == 'directory';

              return ListTile(
                leading: Icon(
                  _getFileIcon(node.name, isDir),
                  color: _getFileColor(node.name, isDir, colorScheme),
                  size: 24,
                ),
                title: Text(
                  node.name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: isDir ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                subtitle: Text(
                  isDir
                      ? '${node.childCount ?? 0} items'
                      : _formatSize(node.sizeBytes ?? 0),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: colorScheme.error, size: 20),
                      onPressed: () => _handleDelete(context, ref, node),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: colorScheme.onSurfaceVariant,
                      size: 16,
                    ),
                  ],
                ),
                onTap: () {
                  if (isDir) {
                    context.push('/files?path=${Uri.encodeComponent(node.path)}');
                  } else {
                    context.push('/files/viewer?path=${Uri.encodeComponent(node.path)}');
                  }
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        onPressed: () => _handleCreate(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String name, bool isDir) {
    if (isDir) return Icons.folder;

    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return Icons.code;
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
        return Icons.javascript;
      case 'html':
      case 'xml':
        return Icons.html;
      case 'css':
      case 'scss':
        return Icons.css;
      case 'json':
      case 'yaml':
      case 'yml':
      case 'toml':
      case 'ini':
      case 'conf':
        return Icons.settings;
      case 'md':
      case 'txt':
      case 'log':
        return Icons.description;
      case 'py':
      case 'sh':
      case 'bat':
      case 'ps1':
        return Icons.terminal;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
      case 'webp':
        return Icons.image;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'flac':
        return Icons.audio_file;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
        return Icons.video_file;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'zip':
      case 'rar':
      case 'tar':
      case 'gz':
      case '7z':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  // File type icon colors — kept as semantic constants (work in both themes)
  Color _getFileColor(String name, bool isDir, ColorScheme colorScheme) {
    if (isDir) return const Color(0xFFE2B53E); // Standard Folder Amber

    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return const Color(0xFF00B4D8); // Flutter/Dart Blue-Cyan
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
        return const Color(0xFFF1C40F); // JS/TS Yellow
      case 'html':
      case 'xml':
        return const Color(0xFFE67E22); // HTML Orange
      case 'css':
      case 'scss':
        return const Color(0xFF3498DB); // CSS Blue
      case 'json':
      case 'yaml':
      case 'yml':
      case 'toml':
        return const Color(0xFF1ABC9C); // Config Teal
      case 'md':
        return const Color(0xFF9B59B6); // Markdown Purple
      case 'txt':
      case 'log':
        return const Color(0xFFBDC3C7); // Plain Text Grey
      case 'py':
        return const Color(0xFF2ECC71); // Python Green
      case 'sh':
      case 'bat':
      case 'ps1':
        return const Color(0xFF34495E); // Script Slate
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
      case 'webp':
        return const Color(0xFFE74C3C); // Images Coral/Red
      case 'pdf':
        return const Color(0xFFC0392B); // PDF Dark Red
      case 'zip':
      case 'rar':
      case 'tar':
      case 'gz':
      case '7z':
        return const Color(0xFFF39C12); // Zip Orange
      default:
        return colorScheme.primary; // Default app primary color
    }
  }
}
