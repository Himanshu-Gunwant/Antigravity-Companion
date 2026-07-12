import 'package:flutter_riverpod/flutter_riverpod.dart';

class ArtifactCacheNotifier extends Notifier<Map<String, String>> {
  static const int _maxSize = 50;

  @override
  Map<String, String> build() {
    return {};
  }

  void cacheContent(String key, String content) {
    if (state.length >= _maxSize && !state.containsKey(key)) {
      final keys = state.keys.toList();
      final newMap = Map<String, String>.from(state);
      newMap.remove(keys.first);
      newMap[key] = content;
      state = newMap;
    } else {
      state = {...state, key: content};
    }
  }

  void clear() {
    state = {};
  }
}

final artifactCacheProvider = NotifierProvider<ArtifactCacheNotifier, Map<String, String>>(() {
  return ArtifactCacheNotifier();
});
