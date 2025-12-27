import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'musician_page.dart';

class MusicianSetupPage extends StatefulWidget {
  const MusicianSetupPage({super.key});

  @override
  State<MusicianSetupPage> createState() => _MusicianSetupPageState();
}

class _MusicianSetupPageState extends State<MusicianSetupPage> {
  final _instruments = [
    'Flöte',
    'Klarinette',
    'Trompete',
    'Horn',
    'Posaune',
    'Saxophon',
    'Tuba',
    'Tenorhorn',
  ];

  final _voices = ['1. Stimme', '2. Stimme', '3. Stimme'];

  String? _selectedInstrument;
  String? _selectedVoice;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedInstrument = prefs.getString('instrument');
      final voiceNumber = prefs.getString('voice');
      if (voiceNumber != null) {
        // Anzeige im Dropdown korrekt setzen
        _selectedVoice = _voices.firstWhere(
            (v) => v.startsWith(voiceNumber),
            orElse: () => '');
      }
    });
  }

  Future<void> _savePrefs(String voiceNumber) async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedInstrument != null) {
      await prefs.setString('instrument', _selectedInstrument!);
    }
    await prefs.setString('voice', voiceNumber); // nur Zahl speichern
  }

  void _openMusician() async {
    if (_selectedInstrument == null || _selectedVoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Instrument und Stimme wählen.')),
      );
      return;
    }

    // Stimme nur als Zahl extrahieren
    final voiceNumber = _selectedVoice!.split('.').first;

    await _savePrefs(voiceNumber);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MusicianPage(
          instrument: _selectedInstrument!,
          voice: voiceNumber, // nur Zahl übergeben
          conductorPort: 4041,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Musiker – Einrichtung'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF0D47A1),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0D47A1),
              Color(0xFF1565C0),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Kopfbereich
                const Icon(Icons.music_note, size: 64, color: Colors.white),
                const SizedBox(height: 16),
                Text(
                  'Deine Einstellungen',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),

                // Instrument Card
                _SelectionCard(
                  title: 'Instrument',
                  subtitle: 'Wähle dein Instrument',
                  icon: Icons.queue_music,
                  child: _buildDropdown(
                    value: _selectedInstrument,
                    items: _instruments,
                    onChanged: (v) => setState(() => _selectedInstrument = v),
                  ),
                ),

                const SizedBox(height: 20),

                // Stimme Card
                _SelectionCard(
                  title: 'Stimme',
                  subtitle: 'Wähle deine Stimme',
                  icon: Icons.record_voice_over,
                  child: _buildDropdown(
                    value: _selectedVoice,
                    items: _voices,
                    onChanged: (v) => setState(() => _selectedVoice = v),
                  ),
                ),

                const SizedBox(height: 40),

                // Weiter Button
                ElevatedButton.icon(
                  onPressed: _openMusician,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text(
                    'Weiter als Musiker',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      hint: const Text('Bitte wählen'),
      isExpanded: true,
      dropdownColor: Colors.blue.shade700,
      iconEnabledColor: Colors.white,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      items: items
          .map(
            (s) => DropdownMenuItem(
              value: s,
              child: Text(s, style: const TextStyle(color: Colors.white)),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _SelectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withOpacity(0.12),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
