import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/config_provider.dart';
import '../services/api_client.dart';


class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _urlController = TextEditingController(text: 'http://100.87.154.124:3579');
  final _keyController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final relayUrl = _urlController.text.trim();
    final apiKey = _keyController.text.trim();
    final username = _nameController.text.trim();

    if (relayUrl.isEmpty || apiKey.isEmpty || username.isEmpty) {
      setState(() {
        _error = 'Please enter URL, API Key, and your name';
        _isLoading = false;
      });
      return;
    }

    try {
      final uri = Uri.tryParse(relayUrl);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        setState(() {
          _error = 'Invalid URL format';
          _isLoading = false;
        });
        return;
      }

      await ref.read(configProvider.notifier).saveConfig(relayUrl, apiKey, username: username);
      
      final client = ref.read(apiClientProvider);
      final isHealthy = await client.checkHealth();

      if (isHealthy) {
        if (mounted) {
          context.go('/dashboard');
        }
      } else {
        await ref.read(configProvider.notifier).clearConfig();
        if (mounted) {
          setState(() {
            _error = 'Connection failed. Relay server is unreachable or API key is invalid.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      await ref.read(configProvider.notifier).clearConfig();
      if (mounted) {
        setState(() {
          _error = 'Connection error: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Text(
                  'ANTIGRAVITY',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'MOBILE COMPANION',
                  style: Theme.of(context).textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 64),
                
                // Form
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'Relay Server URL',
                    prefixIcon: Icon(Icons.hub_outlined, color: colorScheme.secondaryContainer),
                  ),
                  keyboardType: TextInputType.url,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Your Name',
                    prefixIcon: Icon(Icons.person_outline, color: colorScheme.secondaryContainer),
                  ),
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keyController,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    prefixIcon: Icon(Icons.key_outlined, color: colorScheme.secondaryContainer),
                  ),
                  obscureText: true,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                
                // Error Display
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: colorScheme.error.withAlpha(26),
                      border: Border.all(color: colorScheme.error.withAlpha(128)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: colorScheme.error, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                // Submit Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _connect,
                  child: _isLoading 
                    ? SizedBox(
                        height: 20, 
                        width: 20, 
                        child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary)
                      )
                    : const Text('INITIALIZE CONNECTION'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
