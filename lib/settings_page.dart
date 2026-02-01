import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

  final List<String> _instruments = [
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
  final List<String> _voices = ['1', '2', '3', '4'];

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
    setState(() => _appVersion = info.version);
  }

  bool get _hasChanges =>
      _selectedInstrument != widget.instrument ||
      _selectedVoice != widget.voice ||
      _darkMode != widget.darkMode;

  Future<void> _onSavePressed() async {
    Navigator.of(context).pop({
      'instrument': _selectedInstrument,
      'voice': _selectedVoice,
      'darkMode': _darkMode,
    });
  }

  Widget _buildDropdownCard({
    required IconData icon,
    required String title,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonFormField<String>(
          value: value,
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            icon: Icon(icon, color: Colors.blueGrey),
            labelText: title,
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildDropdownCard(
              icon: Icons.music_note,
              title: 'Instrument',
              value: _selectedInstrument,
              options: _instruments,
              onChanged: (val) => setState(() => _selectedInstrument = val!),
            ),
            const SizedBox(height: 12),
            _buildDropdownCard(
              icon: Icons.mic,
              title: 'Stimme',
              value: _selectedVoice,
              options: _voices,
              onChanged: (val) => setState(() => _selectedVoice = val!),
            ),
            const SizedBox(height: 24),
            Card(
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: SwitchListTile(
                title: const Text('Dunkles Theme'),
                secondary:
                    const Icon(Icons.brightness_6, color: Colors.blueGrey),
                value: _darkMode,
                onChanged: (val) => setState(() => _darkMode = val),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _onSavePressed,
                icon: const Icon(Icons.save),
                label: const Text('Speichern'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _appVersion.isEmpty ? 'Version …' : 'Version $_appVersion',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
