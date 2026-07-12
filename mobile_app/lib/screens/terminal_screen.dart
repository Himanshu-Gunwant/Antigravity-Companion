import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xterm/xterm.dart';
import '../services/ssh_service.dart';
import '../theme/design_system.dart';

// Premium ANSI Terminal Theme
const _customTerminalTheme = TerminalTheme(
  cursor: Color(0x7756E472),
  selection: Color(0x3356E472),
  background: Color(0xFF050505),
  foreground: Color(0xFFE2E8F0),
  black: Color(0xFF000000),
  red: Color(0xFFEF4444),
  green: Color(0xFF10B981),
  yellow: Color(0xFFF59E0B),
  blue: Color(0xFF3B82F6),
  magenta: Color(0xFFD946EF),
  cyan: Color(0xFF06B6D4),
  white: Color(0xFFCBD5E1),
  brightBlack: Color(0xFF64748B),
  brightRed: Color(0xFFF87171),
  brightGreen: Color(0xFF34D399),
  brightYellow: Color(0xFFFBBF24),
  brightBlue: Color(0xFF60A5FA),
  brightMagenta: Color(0xFFF472B6),
  brightCyan: Color(0xFF22D3EE),
  brightWhite: Color(0xFFF8FAFC),
  searchHitBackground: Color(0XFFFFFF2B),
  searchHitBackgroundCurrent: Color(0XFF31FF26),
  searchHitForeground: Color(0XFF000000),
);

class TerminalScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const TerminalScreen({super.key, required this.sessionId});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  late SshSessionInstance _session;
  bool _ctrlActive = false;
  bool _altActive = false;
  String _sessionStatus = 'Connecting';

  @override
  void initState() {
    super.initState();
    final service = ref.read(sshServiceProvider);
    final activeSession = service.getSession(widget.sessionId);
    if (activeSession == null) {
      // Re-route back if session is dead
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop();
      });
      return;
    }

    _session = activeSession;
    _sessionStatus = _session.status;

    // Listen for connection status changes
    service.addStatusListener(widget.sessionId, _onStatusChange);

    // Set up intercept for local custom Ctrl/Alt sequences
    _session.terminal.onOutput = _handleTerminalKeyboardOutput;
  }

  void _onStatusChange(String status) {
    if (mounted) {
      setState(() => _sessionStatus = status);
    }
  }

  @override
  void dispose() {
    ref.read(sshServiceProvider).removeStatusListener(widget.sessionId, _onStatusChange);
    super.dispose();
  }

  // Intercept typed keyboard inputs to apply Shift/Ctrl/Alt states if active
  void _handleTerminalKeyboardOutput(String data) {
    if (!_session.isConnected) return;

    if (data.isNotEmpty) {
      var code = data.codeUnitAt(0);

      // Handle Ctrl modifier
      if (_ctrlActive) {
        if (code >= 97 && code <= 122) { // a-z
          code = code - 96;
        } else if (code >= 65 && code <= 90) { // A-Z
          code = code - 64;
        }
        setState(() => _ctrlActive = false);
        _session.writeBytes([code]);
        return;
      }

      // Handle Alt modifier
      if (_altActive) {
        setState(() => _altActive = false);
        _session.write('\x1b$data');
        return;
      }
    }

    // Handle Enter key (Carriage Return) - map to CRLF (\r\n) for Windows compatibility
    if (data == '\r') {
      _session.write('\r\n');
      return;
    }

    _session.write(data);
  }

  // Accessory keys handler
  void _sendSpecialKey(String keySeq) {
    if (_session.isConnected) {
      _session.write(keySeq);
    }
  }

  void _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _sendSpecialKey(data.text!);
    }
  }

  void _showSnippetsSheet() async {
    final service = ref.read(sshServiceProvider);
    final snippets = await service.loadSnippets();

    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceDim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        final sheetColorScheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Command Snippets',
                style: DesignSystem.textTheme.headlineMedium?.copyWith(color: colorScheme.onSurface),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: snippets.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final snippet = snippets[index];
                    return ListTile(
                      tileColor: sheetColorScheme.surfaceBright,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      title: Text(
                        snippet,
                        style: GoogleFonts.jetBrainsMono(fontSize: 13, color: sheetColorScheme.onSurface),
                      ),
                      trailing: Icon(Icons.arrow_forward_ios, size: 14, color: sheetColorScheme.onSurfaceVariant),
                      onTap: () {
                        _session.sendCommand(snippet);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _session.connection.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                _buildStatusDot(),
                const SizedBox(width: 6),
                Text(
                  _sessionStatus,
                  style: TextStyle(
                    fontSize: 11,
                    color: _getStatusColor().withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.content_paste, color: colorScheme.onSurface),
            tooltip: 'Paste Clipboard',
            onPressed: _pasteClipboard,
          ),
          IconButton(
            icon: Icon(Icons.list_alt, color: colorScheme.onSurface),
            tooltip: 'Snippets',
            onPressed: _showSnippetsSheet,
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.redAccent),
            tooltip: 'Close Tab',
            onPressed: () {
              ref.read(sshServiceProvider).closeSession(widget.sessionId);
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Interactive terminal shell view using JetBrains Mono
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: TerminalView(
                  _session.terminal,
                  theme: _customTerminalTheme,
                  textStyle: TerminalStyle(
                    fontSize: 13,
                    fontFamily: GoogleFonts.jetBrainsMono().fontFamily ?? 'monospace',
                  ),
                ),
              ),
            ),

            // Accessory keyboard toolbar
            _buildAccessoryToolbar(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDot() {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: _getStatusColor(),
        shape: BoxShape.circle,
      ),
    );
  }

  Color _getStatusColor() {
    final colorScheme = Theme.of(context).colorScheme;
    switch (_sessionStatus) {
      case 'Connected':
        return colorScheme.primary;
      case 'Connecting':
      case 'Reconnecting':
        return Colors.amber;
      default:
        return Colors.redAccent;
    }
  }

  Widget _buildAccessoryToolbar(ColorScheme colorScheme) {
    return Container(
      height: 48,
      color: colorScheme.surfaceDim,
      child: Row(
        children: [
          // Modifiers (Ctrl/Alt)
          _buildModifierButton('Ctrl', _ctrlActive, () {
            setState(() => _ctrlActive = !_ctrlActive);
          }, colorScheme),
          _buildModifierButton('Alt', _altActive, () {
            setState(() => _altActive = !_altActive);
          }, colorScheme),
          
          VerticalDivider(width: 1, color: colorScheme.outline),

          // Scrollable keys
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildKeyButton('Esc', () => _sendSpecialKey('\x1b'), colorScheme),
                _buildKeyButton('Tab', () => _sendSpecialKey('\t'), colorScheme),
                _buildKeyButton('^Up', () => _sendSpecialKey('\x1b[A'), colorScheme),
                _buildKeyButton('^Down', () => _sendSpecialKey('\x1b[B'), colorScheme),
                _buildKeyButton('^Left', () => _sendSpecialKey('\x1b[D'), colorScheme),
                _buildKeyButton('^Right', () => _sendSpecialKey('\x1b[C'), colorScheme),
                _buildKeyButton('/', () => _sendSpecialKey('/'), colorScheme),
                _buildKeyButton('\\', () => _sendSpecialKey('\\'), colorScheme),
                _buildKeyButton('~', () => _sendSpecialKey('~'), colorScheme),
                _buildKeyButton('`', () => _sendSpecialKey('`'), colorScheme),
                _buildKeyButton('-', () => _sendSpecialKey('-'), colorScheme),
                _buildKeyButton('_', () => _sendSpecialKey('_'), colorScheme),
                _buildKeyButton(':', () => _sendSpecialKey(':'), colorScheme),
                _buildKeyButton(';', () => _sendSpecialKey(';'), colorScheme),
                _buildKeyButton('|', () => _sendSpecialKey('|'), colorScheme),
                _buildKeyButton('Ctrl+C', () => _sendSpecialKey('\x03'), colorScheme),
                _buildKeyButton('Ctrl+D', () => _sendSpecialKey('\x04'), colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModifierButton(String text, bool active, VoidCallback onTap, ColorScheme colorScheme) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 50,
        alignment: Alignment.center,
        color: active ? colorScheme.primary.withValues(alpha: 0.2) : Colors.transparent,
        child: Text(
          text,
          style: TextStyle(
            color: active ? colorScheme.primary : colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildKeyButton(String text, VoidCallback onTap, ColorScheme colorScheme) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
