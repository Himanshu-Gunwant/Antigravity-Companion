import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../providers/config_provider.dart';

class AccountManagerCard extends ConsumerStatefulWidget {
  const AccountManagerCard({super.key});

  @override
  ConsumerState<AccountManagerCard> createState() => _AccountManagerCardState();
}

class _AccountManagerCardState extends ConsumerState<AccountManagerCard> {
  List<String> _profiles = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);
    final apiClient = ref.read(apiClientProvider);
    final profiles = await apiClient.listAccounts();
    if (mounted) {
      setState(() {
        _profiles = profiles;
        _isLoading = false;
      });
    }
  }

  Future<void> _extractAccount() async {
    final execPath = ref.read(configProvider).value?.daemonExecutablePath;
    if (execPath == null || execPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daemon executable path is not configured.')),
      );
      return;
    }

    final profileNameController = TextEditingController();
    final profileName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Current Account'),
        content: TextField(
          controller: profileNameController,
          decoration: const InputDecoration(
            labelText: 'Profile Name',
            hintText: 'e.g., user@gmail.com',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, profileNameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (profileName != null && profileName.isNotEmpty) {
      setState(() => _isLoading = true);
      final apiClient = ref.read(apiClientProvider);
      final success = await apiClient.extractAccount(profileName, execPath);
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile "$profileName" saved successfully!')),
        );
        _loadProfiles();
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile "$profileName".')),
        );
      }
    }
  }

  Future<void> _swapAccount(String profileName) async {
    final execPath = ref.read(configProvider).value?.daemonExecutablePath;
    if (execPath == null || execPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daemon executable path is not configured.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch Account'),
        content: Text('Are you sure you want to switch to profile "$profileName"? This will restart Antigravity.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final apiClient = ref.read(apiClientProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switching to "$profileName"...')),
      );
      final success = await apiClient.swapAccount(profileName, execPath);
      
      setState(() => _isLoading = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully switched to "$profileName".')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to switch to "$profileName".')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Account Profiles',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadProfiles,
                  tooltip: 'Refresh Profiles',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                'No profiles saved yet.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else
            ..._profiles.map((profile) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      profile,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ),
                  TextButton.icon(
                    icon: Icon(Icons.swap_horiz, size: 16, color: colorScheme.primary),
                    label: Text('Use', style: TextStyle(color: colorScheme.primary)),
                    onPressed: _isLoading ? null : () => _swapAccount(profile),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            )),
          Divider(color: colorScheme.outline.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Save Current Account as Profile'),
              onPressed: _isLoading ? null : _extractAccount,
            ),
          ),
        ],
      ),
    );
  }
}
