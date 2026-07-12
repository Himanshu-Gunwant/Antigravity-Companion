import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/appearance_provider.dart';

class AppearanceCard extends ConsumerStatefulWidget {
  const AppearanceCard({super.key});

  @override
  ConsumerState<AppearanceCard> createState() => _AppearanceCardState();
}

class _AppearanceCardState extends ConsumerState<AppearanceCard> {
  // Utility to parse hex string safely for the preview chip
  Color _parseHex(String hex) {
    String clean = hex.replaceAll('#', '');
    if (clean.length == 6 || clean.length == 7) clean = 'FF$clean';
    try {
      return Color(int.parse(clean, radix: 16));
    } catch (_) {
      return Colors.transparent;
    }
  }

  Widget _buildDropdownRow(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
          ),
          DropdownButton<String>(
            value: value,
            underline: const SizedBox(),
            dropdownColor: colorScheme.surfaceContainerHighest,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildColorInputRow(String label, String hexValue, ValueChanged<String> onSubmitted) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: hexValue);
    final previewColor = _parseHex(hexValue);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: previewColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colorScheme.outline, width: 1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontFamily: 'JetBrains Mono'),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: onSubmitted,
                      onTapOutside: (_) => onSubmitted(controller.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appearanceProvider);
    final colorScheme = Theme.of(context).colorScheme;

    String modeStr = 'System';
    if (settings.themeMode == ThemeMode.light) modeStr = 'Light';
    if (settings.themeMode == ThemeMode.dark) modeStr = 'Dark';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- APPEARANCE SECTION ---
        Text('Appearance', style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDropdownRow('Appearance', modeStr, ['System', 'Dark', 'Light'], (v) {
                ThemeMode m = ThemeMode.system;
                if (v == 'Dark') m = ThemeMode.dark;
                if (v == 'Light') m = ThemeMode.light;
                ref.read(appearanceProvider.notifier).updateSettings(settings.copyWith(themeMode: m));
              }),
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 12),
                child: Text('Select light, dark, or inherit system settings.', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // --- LIGHT THEME SECTION ---
        Text('Light Theme', style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              _buildDropdownRow('Preset', 'Default Light', ['Default Light'], (v) {}),
              Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.1)),
              _buildColorInputRow('Background', settings.lightBg, (hex) {
                ref.read(appearanceProvider.notifier).updateSettings(settings.copyWith(lightBg: hex));
              }),
              Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.1)),
              _buildColorInputRow('Foreground', settings.lightFg, (hex) {
                ref.read(appearanceProvider.notifier).updateSettings(settings.copyWith(lightFg: hex));
              }),
              Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.1)),
              _buildColorInputRow('Accent', settings.lightAccent, (hex) {
                ref.read(appearanceProvider.notifier).updateSettings(settings.copyWith(lightAccent: hex));
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // --- DARK THEME SECTION ---
        Text('Dark Theme', style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              _buildDropdownRow('Preset', 'Default Dark', ['Default Dark'], (v) {}),
              Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.1)),
              _buildColorInputRow('Background', settings.darkBg, (hex) {
                ref.read(appearanceProvider.notifier).updateSettings(settings.copyWith(darkBg: hex));
              }),
              Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.1)),
              _buildColorInputRow('Foreground', settings.darkFg, (hex) {
                ref.read(appearanceProvider.notifier).updateSettings(settings.copyWith(darkFg: hex));
              }),
              Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.1)),
              _buildColorInputRow('Accent', settings.darkAccent, (hex) {
                ref.read(appearanceProvider.notifier).updateSettings(settings.copyWith(darkAccent: hex));
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}
