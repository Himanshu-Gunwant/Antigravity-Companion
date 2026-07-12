import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/config_provider.dart';
import 'providers/appearance_provider.dart';
import 'screens/setup_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/file_explorer_screen.dart';
import 'screens/file_viewer_screen.dart';
import 'screens/git_screen.dart';
import 'screens/git_diff_screen.dart';
import 'screens/builds_screen.dart';
import 'screens/pc_file_manager_screen.dart';
import 'services/notification_service.dart';
import 'services/ssh_service.dart';
import 'screens/ssh_connections_screen.dart';
import 'screens/terminal_screen.dart';
import 'theme/design_system.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  late final GoRouter _router;
  StreamSubscription<String>? _notificationClickSub;
  bool _hasAttemptedRestore = false;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/setup',
      routes: [
        GoRoute(
          path: '/setup',
          builder: (context, state) => const SetupScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/chat',
          builder: (context, state) {
            final id = state.uri.queryParameters['id'];
            return ChatScreen(initialConversationId: id);
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/files',
          builder: (context, state) {
            final path = state.uri.queryParameters['path'] ?? '';
            return FileExplorerScreen(path: path);
          },
        ),
        GoRoute(
          path: '/files/viewer',
          builder: (context, state) {
            final path = state.uri.queryParameters['path'] ?? '';
            return FileViewerScreen(path: path);
          },
        ),
        GoRoute(
          path: '/git',
          builder: (context, state) => const GitScreen(),
        ),
        GoRoute(
          path: '/git/diff',
          builder: (context, state) {
            final file = state.uri.queryParameters['file'];
            final staged = state.uri.queryParameters['staged'] == 'true';
            final hash = state.uri.queryParameters['hash'];
            return GitDiffScreen(file: file, staged: staged, hash: hash);
          },
        ),
        GoRoute(
          path: '/builds',
          builder: (context, state) => const BuildsScreen(),
        ),
        GoRoute(
          path: '/ssh',
          builder: (context, state) => const SshConnectionsScreen(),
        ),
        GoRoute(
          path: '/pc_file_manager',
          builder: (context, state) => const PcFileManagerScreen(),
        ),
        GoRoute(
          path: '/ssh/terminal/:sessionId',
          builder: (context, state) {
            final sessionId = state.pathParameters['sessionId'] ?? '';
            return TerminalScreen(sessionId: sessionId);
          },
        ),
      ],
      redirect: (context, state) {
        final configAsync = ref.read(configProvider);
        if (configAsync.isLoading) return null;
        
        final config = configAsync.value;
        if (config == null || !config.isConfigured) {
          if (state.uri.path != '/setup') {
            return '/setup';
          }
        } else if (state.uri.path == '/setup') {
          return '/dashboard'; // Redirect away from setup if already configured
        }
        return null;
      },
    );

    // Listen to notification clicks for deep linking
    _notificationClickSub = ref.read(notificationServiceProvider).clickStream.listen((payload) {
      debugPrint('[MyApp] Notification click received with payload: $payload');
      if (payload == 'build_complete' || payload == 'apk_ready') {
        _router.push('/builds');
      } else if (payload == 'response_ready' || payload == 'error') {
        _router.push('/chat');
      }
    });
  }

  @override
  void dispose() {
    _notificationClickSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(configProvider, (previous, next) {
      if (!next.isLoading) {
        _router.refresh();
      }
    });

    final configAsync = ref.watch(configProvider);
    
    // Initialize NotificationService and restore active SSH sessions
    if (configAsync.hasValue && configAsync.value!.isConfigured) {
      ref.watch(notificationServiceProvider);
      if (!_hasAttemptedRestore) {
        _hasAttemptedRestore = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(sshServiceProvider).attemptRestoreSessions();
          }
        });
      }
    }

    final appearance = ref.watch(appearanceProvider);

    final lightTheme = DesignSystem.buildDynamicTheme(
      isDark: false,
      bgHex: appearance.lightBg,
      fgHex: appearance.lightFg,
      accentHex: appearance.lightAccent,
    );

    final darkTheme = DesignSystem.buildDynamicTheme(
      isDark: true,
      bgHex: appearance.darkBg,
      fgHex: appearance.darkFg,
      accentHex: appearance.darkAccent,
    );

    if (configAsync.isLoading && !configAsync.hasValue) {
      return MaterialApp(
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: appearance.themeMode,
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp.router(
      title: 'Antigravity Companion',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: appearance.themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
    );
  }
}
