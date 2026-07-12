import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ssh_connection.dart';
import '../services/ssh_service.dart';
import '../theme/design_system.dart';
import '../widgets/app_sidebar.dart';
import 'terminal_screen.dart';

class SshConnectionsScreen extends ConsumerStatefulWidget {
  const SshConnectionsScreen({super.key});

  @override
  ConsumerState<SshConnectionsScreen> createState() => _SshConnectionsScreenState();
}

class _SshConnectionsScreenState extends ConsumerState<SshConnectionsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<SshConnection> _connections = [];
  List<String> _snippets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final service = ref.read(sshServiceProvider);
    final list = await service.loadConnections();
    final snips = await service.loadSnippets();
    setState(() {
      _connections = list;
      _snippets = snips;
      _isLoading = false;
    });
  }

  void _showFormDialog({SshConnection? existing}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ConnectionFormDialog(
        existing: existing,
        onSave: (profile, password, privateKey, passphrase) async {
          final service = ref.read(sshServiceProvider);
          await service.saveConnection(
            profile,
            password: password,
            privateKey: privateKey,
            passphrase: passphrase,
          );
          _loadData();
        },
      ),
    );
  }

  void _deleteConnection(String id) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surfaceDim,
        title: const Text('Delete Connection?'),
        content: const Text('Are you sure you want to delete this profile? Associated credentials will be permanently erased.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(sshServiceProvider).deleteConnection(id);
      _loadData();
    }
  }

  void _connect(SshConnection conn) async {
    final service = ref.read(sshServiceProvider);
    
    // Check if we need host key verification (V1 trust check)
    // We'll let the session establish its verification handler inside createSession.
    // The verifyHostKeyCallback will trigger a user dialog if a fingerprint is unknown.
    
    // Create new session
    final sessionId = await service.createSession(conn);
    
    // Navigate directly to Terminal Screen
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TerminalScreen(sessionId: sessionId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Watch service changes to rebuild active status
    ref.watch(sshServiceProvider);

    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppSidebar(),
      appBar: AppBar(
        title: const Text('SSH Terminals'),
        backgroundColor: colorScheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showFormDialog(),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Active Sessions Section (if any)
                  _buildActiveSessionsSection(colorScheme),
                  
                  const SizedBox(height: 12),
                  Text(
                    'Connection Profiles',
                    style: DesignSystem.textTheme.headlineMedium?.copyWith(color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 12),
                  
                  if (_connections.isEmpty)
                    _buildEmptyState(colorScheme)
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _connections.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final conn = _connections[index];
                        return _ConnectionCard(
                          connection: conn,
                          onConnect: () => _connect(conn),
                          onEdit: () => _showFormDialog(existing: conn),
                          onDelete: () => _deleteConnection(conn.id),
                          ref: ref,
                        );
                      },
                    ),

                  const SizedBox(height: 32),
                  Text(
                    'Command Snippets',
                    style: DesignSystem.textTheme.headlineMedium?.copyWith(color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 12),
                  _buildSnippetsSection(colorScheme),
                ],
              ),
            ),
    );
  }

  Widget _buildActiveSessionsSection(ColorScheme colorScheme) {
    final service = ref.read(sshServiceProvider);
    final activeIds = service.getActiveSessionIds();
    if (activeIds.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active Sessions',
          style: DesignSystem.textTheme.headlineMedium?.copyWith(color: colorScheme.onSurface),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: activeIds.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final sessionId = activeIds[index];
            final session = service.getSession(sessionId);
            if (session == null) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.terminal, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.connection.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${session.connection.username}@${session.connection.host}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(session.status, colorScheme),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_right, color: colorScheme.onSurface),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => TerminalScreen(sessionId: sessionId),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                    onPressed: () {
                      service.closeSession(sessionId);
                      setState(() {});
                    },
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStatusChip(String status, ColorScheme colorScheme) {
    Color color;
    if (status == 'Connected') {
      color = colorScheme.primary;
    } else if (status == 'Connecting' || status == 'Reconnecting') {
      color = Colors.amber;
    } else {
      color = Colors.redAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colorScheme.surfaceDim,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        children: [
          Icon(Icons.settings_ethernet, size: 48, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          const Text(
            'No connection profiles found',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first SSH profile to manage your dev laptop remotely.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Connection'),
            onPressed: () => _showFormDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildSnippetsSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceDim,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _snippets.map((snip) {
              return Chip(
                backgroundColor: colorScheme.surfaceBright,
                side: BorderSide(color: colorScheme.outline),
                label: Text(
                  snip,
                  style: DesignSystem.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
                ),
                deleteIcon: Icon(Icons.close, size: 14, color: colorScheme.onSurfaceVariant),
                onDeleted: () async {
                  await ref.read(sshServiceProvider).deleteSnippet(snip);
                  _loadData();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Add new snippet (e.g. docker ps)',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onSubmitted: (val) async {
                    if (val.trim().isNotEmpty) {
                      await ref.read(sshServiceProvider).saveSnippet(val.trim());
                      _loadData();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final SshConnection connection;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final WidgetRef ref;

  const _ConnectionCard({
    required this.connection,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceDim,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              connection.name,
              style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            subtitle: Text(
              '${connection.username}@${connection.host}:${connection.port}',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            trailing: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: colorScheme.onSurface),
              color: colorScheme.surfaceBright,
              onSelected: (val) {
                if (val == 'edit') {
                  onEdit();
                } else if (val == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit Profile'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete Profile', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outline),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Copy IP Address',
                  icon: Icon(Icons.copy, size: 18, color: colorScheme.onSurfaceVariant),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: connection.host));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('IP Copied to Clipboard')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Wake Device (Future)',
                  icon: Icon(Icons.power_settings_new, size: 18, color: colorScheme.onSurfaceVariant),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Wake-on-LAN is not supported on this host yet')),
                    );
                  },
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.terminal, size: 16),
                  label: const Text('Open Terminal'),
                  onPressed: onConnect,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionFormDialog extends StatefulWidget {
  final SshConnection? existing;
  final Function(SshConnection profile, String? password, String? privateKey, String? passphrase) onSave;

  const _ConnectionFormDialog({this.existing, required this.onSave});

  @override
  State<_ConnectionFormDialog> createState() => _ConnectionFormDialogState();
}

class _ConnectionFormDialogState extends State<_ConnectionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _host;
  late int _port;
  late String _username;
  late String _authType;
  
  String? _password;
  String? _privateKey;
  String? _passphrase;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = e?.name ?? '';
    _host = e?.host ?? '';
    _port = e?.port ?? 22;
    _username = e?.username ?? '';
    _authType = e?.authType ?? 'password';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: colorScheme.surfaceDim,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.existing == null ? 'Add SSH Connection' : 'Edit Connection',
                  style: DesignSystem.textTheme.headlineMedium?.copyWith(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: _name,
                  decoration: const InputDecoration(labelText: 'Connection Name (e.g. Dev Laptop)'),
                  validator: (val) => val == null || val.isEmpty ? 'Name required' : null,
                  onSaved: (val) => _name = val ?? '',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: _host,
                        decoration: const InputDecoration(labelText: 'IP/Host (e.g. 100.87.x.x)'),
                        validator: (val) => val == null || val.isEmpty ? 'Host required' : null,
                        onSaved: (val) => _host = val ?? '',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        initialValue: _port.toString(),
                        decoration: const InputDecoration(labelText: 'Port'),
                        keyboardType: TextInputType.number,
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Required';
                          if (int.tryParse(val) == null) return 'Invalid';
                          return null;
                        },
                        onSaved: (val) => _port = int.tryParse(val ?? '22') ?? 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _username,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (val) => val == null || val.isEmpty ? 'Username required' : null,
                  onSaved: (val) => _username = val ?? '',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _authType,
                  decoration: const InputDecoration(labelText: 'Authentication Method'),
                  dropdownColor: colorScheme.surfaceBright,
                  items: const [
                    DropdownMenuItem(value: 'password', child: Text('Password')),
                    DropdownMenuItem(value: 'privateKey', child: Text('Private Key')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _authType = val);
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (_authType == 'password') ...[
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    onSaved: (val) => _password = val,
                  ),
                ] else ...[
                  TextFormField(
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Private Key (PEM format)',
                      hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                    ),
                    onSaved: (val) => _privateKey = val,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Private Key Passphrase (optional)'),
                    obscureText: true,
                    onSaved: (val) => _passphrase = val,
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() == true) {
                          _formKey.currentState?.save();
                          
                          final profile = SshConnection(
                            id: widget.existing?.id ?? 'profile_${DateTime.now().millisecondsSinceEpoch}',
                            name: _name,
                            host: _host,
                            port: _port,
                            username: _username,
                            authType: _authType,
                            hasPassphrase: _passphrase != null && _passphrase!.isNotEmpty,
                          );
                          
                          widget.onSave(profile, _password, _privateKey, _passphrase);
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
