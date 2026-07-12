import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/file_node.dart';

class PcFileManagerScreen extends ConsumerStatefulWidget {
  const PcFileManagerScreen({super.key});

  @override
  ConsumerState<PcFileManagerScreen> createState() => _PcFileManagerScreenState();
}

class _PcFileManagerScreenState extends ConsumerState<PcFileManagerScreen> {
  String _currentPath = '';
  List<FileNode> _nodes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final nodes = await apiClient.getSystemDirectory(path);
      
      // Sort: Folders first, alphabetical
      nodes.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (mounted) {
        setState(() {
          _currentPath = path;
          _nodes = nodes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _navigateUp() {
    if (_currentPath.isEmpty) return;
    
    // Check if we are at root of a drive like "C:\" or "C:/"
    if (_currentPath.length <= 3 && _currentPath.contains(':')) {
      _loadDirectory(''); // Go to drives list
      return;
    }
    
    // Replace backslashes with forward slashes for easier manipulation
    final normalized = _currentPath.replaceAll('\\', '/');
    final lastSlashIndex = normalized.lastIndexOf('/');
    if (lastSlashIndex > 0) {
      final parent = _currentPath.substring(0, lastSlashIndex);
      // Ensure we don't end up with just "C:" instead of "C:/"
      if (parent.endsWith(':')) {
        _loadDirectory('$parent/');
      } else {
        _loadDirectory(parent);
      }
    } else {
      _loadDirectory('');
    }
  }

  Future<void> _createProject() async {
    if (_currentPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a specific directory first.')),
      );
      return;
    }

    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.createNewProject(_currentPath);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Project launched successfully on PC!')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to launch: $e')),
        );
      }
    }
  }

  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Folder name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      try {
        final apiClient = ref.read(apiClientProvider);
        await apiClient.createSystemDirectory(_currentPath, name.trim());
        _loadDirectory(_currentPath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create folder: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PC File Manager'),
            Text(
              _currentPath.isEmpty ? 'This PC (Drives)' : _currentPath,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        leading: _currentPath.isEmpty 
          ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            )
          : IconButton(
              icon: const Icon(Icons.arrow_upward),
              onPressed: _navigateUp,
            ),
        actions: [
          if (_currentPath.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: _createNewFolder,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadDirectory(_currentPath),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 48),
                      const SizedBox(height: 16),
                      Text('Error reading directory', style: Theme.of(context).textTheme.titleMedium),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                      ElevatedButton(
                        onPressed: () => _loadDirectory(_currentPath),
                        child: const Text('Retry'),
                      )
                    ],
                  ),
                )
              : _nodes.isEmpty
                  ? const Center(child: Text('This folder is empty.'))
                  : ListView.builder(
                      itemCount: _nodes.length,
                      itemBuilder: (context, index) {
                        final node = _nodes[index];
                        return ListTile(
                          leading: Icon(
                            node.type == 'directory' ? Icons.folder : Icons.insert_drive_file,
                            color: node.type == 'directory' ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          title: Text(node.name),
                          onTap: () {
                            if (node.type == 'directory') {
                              _loadDirectory(node.path);
                            }
                          },
                        );
                      },
                    ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: FilledButton.icon(
            onPressed: _currentPath.isEmpty ? null : _createProject,
            icon: const Icon(Icons.rocket_launch),
            label: const Text('Initialize Project Here'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ),
    );
  }
}
