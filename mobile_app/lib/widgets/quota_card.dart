import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/quota_provider.dart';


class ModelQuotaCard extends ConsumerWidget {
  const ModelQuotaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final quotaState = ref.watch(quotaSummaryProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.data_usage_rounded, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'MODEL QUOTA',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface.withValues(alpha: 0.9),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: colorScheme.onSurfaceVariant, size: 20),
                onPressed: () {
                  ref.invalidate(quotaSummaryProvider);
                },
                tooltip: 'Refresh Quota',
              ),
            ],
          ),
          const SizedBox(height: 16),
          quotaState.when(
            data: (data) {
              final response = data['response'] as Map<String, dynamic>?;
              if (response == null || !response.containsKey('groups')) {
                return Text('No quota data available.', style: TextStyle(color: colorScheme.onSurfaceVariant));
              }
              final groups = response['groups'] as List<dynamic>;
              return Column(
                children: groups.map((g) => _buildQuotaGroup(context, g)).toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (err, stack) => Text('Error loading quota: $err', style: TextStyle(color: colorScheme.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaGroup(BuildContext context, Map<String, dynamic> group) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = group['displayName'] as String? ?? 'Models';
    final buckets = group['buckets'] as List<dynamic>? ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayName,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: buckets.map((b) => _buildQuotaRing(context, b)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaRing(BuildContext context, Map<String, dynamic> bucket) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = bucket['displayName'] as String? ?? 'Limit';
    final remainingFraction = (bucket['remainingFraction'] as num?)?.toDouble() ?? 0.0;
    
    // Parse reset time to duration
    final resetTimeStr = bucket['resetTime'] as String?;
    String timeRemaining = 'Unknown';
    if (resetTimeStr != null) {
      try {
        final resetDate = DateTime.parse(resetTimeStr);
        final diff = resetDate.difference(DateTime.now());
        if (diff.isNegative) {
          timeRemaining = 'Refreshed';
        } else if (diff.inDays > 0) {
          timeRemaining = '${diff.inDays}d ${diff.inHours % 24}h';
        } else {
          timeRemaining = '${diff.inHours}h ${diff.inMinutes % 60}m';
        }
      } catch (e) {
        // Ignore parse errors
      }
    }

    final percentage = (remainingFraction * 100).toInt();
    
    Color ringColor = colorScheme.primary;
    if (remainingFraction < 0.2) {
      ringColor = colorScheme.error;
    } else if (remainingFraction < 0.5) {
      ringColor = Colors.orange;
    }

    return Column(
      children: [
        SizedBox(
          height: 60,
          width: 60,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: remainingFraction,
                strokeWidth: 6,
                backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.2),
                color: ringColor,
              ),
              Center(
                child: Text(
                  '$percentage%',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          displayName,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        Text(
          timeRemaining,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
