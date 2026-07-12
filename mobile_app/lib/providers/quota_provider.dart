import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';

final quotaSummaryProvider = StreamProvider.autoDispose<Map<String, dynamic>>((ref) async* {
  final apiClient = ref.watch(apiClientProvider);
  
  // Initial fetch
  yield await apiClient.fetchQuotaSummary();

  // Loop to automatically sync data from the server without manual refresh
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    try {
      yield await apiClient.fetchQuotaSummary();
    } catch (e) {
      // Ignore errors on background sync to prevent UI flickering
    }
  }
});
