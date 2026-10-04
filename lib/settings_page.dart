import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'theme/app_theme.dart';

class SettingsPage extends StatefulWidget {
  final String instrument;
  final String voice;
  final bool darkMode;

  const SettingsPage({
    super.key,
    required this.instrument,
    required this.voice,
    this.darkMode = false,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _selectedInstrument;
  late String _selectedVoice;
  late bool _darkMode;
  String _appVersion = '';

  static const _instruments = [
    'Flöte',
    'Klarinette',
    'Trompete',
    'Horn',
    'Posaune',
    'Saxophon',
    'Tuba',
    'Tenorhorn',
    'Schlagzeug',
    'Bariton',
    'Oboe',
  ];
  static const _voices = ['1', '2', '3', '4'];

  @override
  void initState() {
    super.initState();
    _selectedInstrument = widget.instrument;
    _selectedVoice = widget.voice;
    _darkMode = widget.darkMode;
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersion = info.version);
  }

  bool get _hasChanges =>
      _selectedInstrument != widget.instrument ||
      _selectedVoice != widget.voice ||
      _darkMode != widget.darkMode;

  void _save() {
    Navigator.of(context).pop({
      'instrument': _selectedInstrument,
      'voice': _selectedVoice,
      'darkMode': _darkMode,
    });
  }

  Widget _profileDropdown({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final colors = (_darkMode ? AppTheme.dark : AppTheme.light).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: colors.secondary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: value,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(16),
              items: options
                  .map((option) => DropdownMenuItem(
                        value: option,
                        child: Text(option),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = (_darkMode ? AppTheme.dark : AppTheme.light).colorScheme;
    return Theme(
      data: _darkMode ? AppTheme.dark : AppTheme.light,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Einstellungen'),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                'Dein Musikerprofil',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                'Passe deine Notenansicht an.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              _profileDropdown(
                title: 'Instrument',
                subtitle: 'Dein Instrument im Verein',
                icon: Icons.piano,
                value: _selectedInstrument,
                options: _instruments,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedInstrument = value);
                  }
                },
              ),
              const SizedBox(height: 10),
              _profileDropdown(
                title: 'Stimme',
                subtitle: 'Dein Notensatz',
                icon: Icons.graphic_eq,
                value: _selectedVoice,
                options: _voices,
                onChanged: (value) {
                  if (value != null) setState(() => _selectedVoice = value);
                },
              ),
              const SizedBox(height: 22),
              Text(
                'Darstellung',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 17, vertical: 7),
                  secondary: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      _darkMode
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      color: colors.secondary,
                    ),
                  ),
                  title: const Text('Dunkles Design',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Augenschonend bei wenig Licht'),
                  value: _darkMode,
                  onChanged: (value) => setState(() => _darkMode = value),
                ),
              ),
              const SizedBox(height: 22),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(Icons.info_outline_rounded,
                            color: colors.secondary),
                      ),
                      const SizedBox(width: 13),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Marschpad Musiker',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            SizedBox(height: 3),
                            Text('Musikverein Scharrel'),
                          ],
                        ),
                      ),
                      Text(
                        _appVersion.isEmpty ? '…' : 'v$_appVersion',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_hasChanges ? 'Änderungen speichern' : 'Fertig'),
          ),
        ),
      ),
    );
  }
}
