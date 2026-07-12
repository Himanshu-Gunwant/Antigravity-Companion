import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';

class ConversationsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final apiClient = ref.watch(apiClientProvider);
    return apiClient.getConversations();
  }

  /// Triggers a full refresh showing a loading state (e.g. for manual retries)
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final apiClient = ref.read(apiClientProvider);
      final items = await apiClient.getConversations();
      state = AsyncValue.data(items);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Fetches new updates in the background without clearing the cached UI data
  Future<void> refreshBackground() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final items = await apiClient.getConversations();
      state = AsyncValue.data(items);
    } catch (e, stack) {
      // If we don't have any cached data yet, show the error. Otherwise, keep current data.
      if (!state.hasValue) {
        state = AsyncValue.error(e, stack);
      }
    }
  }
}

final conversationsProvider = AsyncNotifierProvider<ConversationsNotifier, List<Map<String, dynamic>>>(() {
  return ConversationsNotifier();
});
