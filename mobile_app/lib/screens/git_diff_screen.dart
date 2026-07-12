import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/git_provider.dart';


class GitDiffScreen extends ConsumerWidget {
  final String? file;
  final bool staged;
  final String? hash;

  const GitDiffScreen({super.key, this.file, this.staged = false, this.hash});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final AsyncValue<String> diffAsync;
    if (hash != null) {
      diffAsync = ref.watch(gitShowProvider(GitShowArg(hash: hash!, file: file)));
    } else {
      diffAsync = ref.watch(gitDiffProvider(GitDiffArg(file: file, staged: staged)));
    }
    
    final filename = file?.split('/').last ?? (hash != null ? 'Commit ${hash!.substring(0, 7)}' : 'Workspace Diff');

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
      ),
      body: diffAsync.when(
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
                  'Failed to load diff',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        data: (diffText) {
          if (diffText.trim().isEmpty) {
            return Center(
              child: Text(
                'No changes detected',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            );
          }

          final lines = diffText.split('\n');

          return Container(
            color: colorScheme.surfaceContainerLow,
            height: double.infinity,
            width: double.infinity,
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                
                // Diff styling rules — keep hardcoded semantic colors for diff highlights
                Color textColor = colorScheme.onSurface;
                Color bgColor = Colors.transparent;
                
                if (line.startsWith('+') && !line.startsWith('+++')) {
                  textColor = const Color(0xFF8CE19E); // light green
                  bgColor = const Color(0xFF14321A); // dark green container
                } else if (line.startsWith('-') && !line.startsWith('---')) {
                  textColor = const Color(0xFFFFB4AB); // light red
                  bgColor = const Color(0xFF3C1414); // dark red container
                } else if (line.startsWith('@@')) {
                  textColor = colorScheme.secondary; // cyan/blue info
                  bgColor = const Color(0xFF0F1E36);
                } else if (line.startsWith('diff') || line.startsWith('index') || line.startsWith('---') || line.startsWith('+++')) {
                  textColor = colorScheme.onSurfaceVariant;
                  bgColor = colorScheme.surfaceContainer;
                }

                return Container(
                  width: double.infinity,
                  color: bgColor,
                  padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
                  child: Text(
                    line,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: textColor,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
