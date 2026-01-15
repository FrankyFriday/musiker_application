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
    'Schlagzeug',
    'Bariton',
  ];

  final _voices = ['1. Stimme', '2. Stimme', '3. Stimme', '4. Stimme'];

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
        _selectedVoice = _voices.firstWhere(
          (v) => v.startsWith(voiceNumber),
          orElse: () => "",
        );
      }
    });
  }

  Future<void> _savePrefs(String voiceNumber) async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedInstrument != null) {
      await prefs.setString('instrument', _selectedInstrument!);
    }
    await prefs.setString('voice', voiceNumber);
  }

  void _openMusician() async {
    if (_selectedInstrument == null || _selectedVoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Instrument und Stimme wählen.')),
      );
      return;
    }

    final voiceNumber = _selectedVoice!.split('.').first;
    await _savePrefs(voiceNumber);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MusicianPage(
          instrument: _selectedInstrument!,
          voice: voiceNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final iconSize = screenWidth * 0.18; // Icon proportional
    final cardPadding = screenWidth * 0.05;

    return Scaffold(
      body: Container(
        width: screenWidth,
        height: screenHeight,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                    horizontal: cardPadding, vertical: screenHeight * 0.04),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - screenHeight * 0.08,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            padding: EdgeInsets.all(screenWidth * 0.06),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.music_note,
                                size: iconSize, color: Colors.white),
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.03),
                        Text(
                          'Deine Einstellungen',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            fontSize: screenWidth * 0.065,
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.05),
                        // Instrument Card
                        _SelectionCard(
                          title: 'Instrument',
                          subtitle: 'Wähle dein Instrument',
                          icon: Icons.queue_music,
                          child: _buildDropdown(
                            value: _selectedInstrument,
                            items: _instruments,
                            onChanged: (v) =>
                                setState(() => _selectedInstrument = v),
                          ),
                        ),
                        SizedBox(height: screenHeight * 0.025),
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
                        SizedBox(height: screenHeight * 0.05),
                        ElevatedButton.icon(
                          onPressed: _openMusician,
                          icon: const Icon(Icons.arrow_forward,
                              color: Colors.blueAccent),
                          label: Text(
                            'Weiter als Musiker',
                            style: TextStyle(
                              fontSize: screenWidth * 0.045,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                                vertical: screenHeight * 0.02),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                            elevation: 6,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              );
            },
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
      hint: const Text('Bitte wählen', style: TextStyle(color: Colors.white70)),
      isExpanded: true,
      dropdownColor: Colors.blue.shade700.withOpacity(0.95),
      iconEnabledColor: Colors.white,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Card(
      color: Colors.white.withOpacity(0.15),
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.white24,
        onTap: () {},
        child: Padding(
          padding: EdgeInsets.all(screenWidth * 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: screenWidth * 0.08,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Icon(icon, color: Colors.white, size: screenWidth * 0.08),
                  ),
                  SizedBox(width: screenWidth * 0.04),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: screenWidth * 0.045,
                              fontWeight: FontWeight.bold)),
                      Text(subtitle,
                          style: TextStyle(
                              color: Colors.white70, fontSize: screenWidth * 0.032)),
                    ],
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.02),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
