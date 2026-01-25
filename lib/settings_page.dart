import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsPage extends StatefulWidget {
  final String instrument;
  final String voice;

  const SettingsPage({
    super.key,
    required this.instrument,
    required this.voice,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _selectedInstrument;
  late String _selectedVoice;
  bool _darkMode = false;
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
  ];

  final List<String> _voices = ['1', '2', '3', '4'];

  @override
  void initState() {
    super.initState();
    _selectedInstrument = widget.instrument;
    _selectedVoice = widget.voice;
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _appVersion = info.version);
  }

  bool get _hasInstrumentOrVoiceChanged =>
      _selectedInstrument != widget.instrument ||
      _selectedVoice != widget.voice;

  Future<void> _onSavePressed() async {
    if (_hasInstrumentOrVoiceChanged) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Änderung bestätigen'),
          content: Text(
            'Möchtest du wirklich von\n\n'
            '• ${widget.instrument} – Stimme ${widget.voice}\n\n'
            'zu\n\n'
            '• $_selectedInstrument – Stimme $_selectedVoice\n\n'
            'wechseln?',
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey.shade900,
                foregroundColor: Colors.white,
              ),
              child: const Text('Ja, wechseln'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    Navigator.of(context).pop({
      'instrument': _selectedInstrument,
      'voice': _selectedVoice,
      'darkMode': _darkMode,
    });
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Instrument & Stimme',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: ListTile(
                leading:
                    const Icon(Icons.music_note, color: Colors.blueGrey),
                title: const Text('Instrument'),
                trailing: DropdownButton<String>(
                  value: _selectedInstrument,
                  items: _instruments
                      .map((i) =>
                          DropdownMenuItem(value: i, child: Text(i)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedInstrument = val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.mic, color: Colors.blueGrey),
                title: const Text('Stimme'),
                trailing: DropdownButton<String>(
                  value: _selectedVoice,
                  items: _voices
                      .map((v) =>
                          DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedVoice = val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
