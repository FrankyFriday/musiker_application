import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'musician_page.dart';
import 'theme/app_theme.dart';

class MusicianSetupPage extends StatefulWidget {
  const MusicianSetupPage({super.key});

  @override
  State<MusicianSetupPage> createState() => _MusicianSetupPageState();
}

class _MusicianSetupPageState extends State<MusicianSetupPage> {
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

  static const _voices = ['1. Stimme', '2. Stimme', '3. Stimme', '4. Stimme'];

  String? _selectedInstrument;
  String? _selectedVoice;
  bool _darkMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final voiceNumber = prefs.getString('voice');
    setState(() {
      _selectedInstrument = prefs.getString('instrument');
      final savedVoice = _voices.firstWhere(
        (voice) => voice.startsWith('${voiceNumber ?? ''}.'),
        orElse: () => '',
      );
      _selectedVoice = savedVoice.isEmpty ? null : savedVoice;
      _darkMode = prefs.getBool('darkMode') ?? false;
      _loading = false;
    });
  }

  Future<void> _openMusician() async {
    final instrument = _selectedInstrument;
    final voice = _selectedVoice;
    if (instrument == null || voice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Instrument und Stimme auswählen.')),
      );
      return;
    }

    final voiceNumber = voice.split('.').first;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('instrument', instrument);
    await prefs.setString('voice', voiceNumber);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MusicianPage(
          instrument: instrument,
          voice: voiceNumber,
          darkMode: _darkMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _BrandHeader(),
                  const SizedBox(height: 28),
                  Text(
                    'Dein Platz im\nMusikverein',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Wähle Instrument und Stimme. Danach bist du direkt mit dem Dirigentenpult verbunden.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 24),
                  _SelectionCard(
                    number: '01',
                    title: 'Instrument',
                    subtitle: 'Was spielst du?',
                    icon: Icons.piano,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_selectedInstrument),
                      initialValue: _selectedInstrument,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Instrument auswählen',
                      ),
                      items: _instruments
                          .map(
                            (instrument) => DropdownMenuItem(
                              value: instrument,
                              child: Text(instrument),
                            ),
                          )
                          .toList(),
                      onChanged: _loading
                          ? null
                          : (value) =>
                              setState(() => _selectedInstrument = value),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SelectionCard(
                    number: '02',
                    title: 'Stimme',
                    subtitle: 'Welche Noten gehören zu dir?',
                    icon: Icons.graphic_eq,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_selectedVoice),
                      initialValue: _selectedVoice,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Stimme auswählen',
                      ),
                      items: _voices
                          .map(
                            (voice) => DropdownMenuItem(
                              value: voice,
                              child: Text(voice),
                            ),
                          )
                          .toList(),
                      onChanged: _loading
                          ? null
                          : (value) => setState(() => _selectedVoice = value),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _loading ? null : _openMusician,
                    icon: Icon(
                        _loading ? Icons.hourglass_top : Icons.arrow_forward),
                    label: Text(
                        _loading ? 'Einstellungen laden …' : 'Zum Musikerpult'),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 16, color: colors.onSurfaceVariant),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'Deine Auswahl wird nur auf diesem Gerät gespeichert.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.midnight, Color(0xFF0B5961)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppTheme.midnight.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(Icons.music_note, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MARSCHPAD',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white70,
                        letterSpacing: 2.1,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Musikverein Scharrel',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _SelectionCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
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
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Text(
                  number,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.secondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 17),
            child,
          ],
        ),
      ),
    );
  }
}
