import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../services/nextcloud_service.dart';
import 'package:intl/intl.dart';

class OfflinePracticePage extends StatefulWidget {
  final String instrument;
  final String voice;

  const OfflinePracticePage({
    super.key,
    required this.instrument,
    required this.voice,
  });

  @override
  State<OfflinePracticePage> createState() => _OfflinePracticePageState();
}

class _OfflinePracticePageState extends State<OfflinePracticePage> {
  final NextcloudService _nextcloudService = NextcloudService();
  bool _isLoading = true;
  List<ReceivedPiece> _pieces = [];

  @override
  void initState() {
    super.initState();
    _loadOfflinePieces();
  }

  Future<void> _loadOfflinePieces() async {
    setState(() => _isLoading = true);
    try {
      final files = await _nextcloudService
          .listAndDownloadPdfs(widget.instrument, widget.voice);

      final pieces = files
          .map((file) => ReceivedPiece(
                name: file.path.split('/').last.split('_').first,
                path: file.path,
                receivedAt: DateTime.now(),
              ))
          .toList();

      setState(() => _pieces = pieces);
    } catch (e) {
      print('Fehler beim Laden der Noten: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden der Noten: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatDate(DateTime dt) {
    return DateFormat('dd.MM.yyyy – HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline üben'),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pieces.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.music_off, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        'Keine Noten gefunden',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Versuche andere Instrumente oder Stimmen.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadOfflinePieces,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pieces.length,
                    itemBuilder: (_, index) {
                      final piece = _pieces[index];
                      final color = Colors.grey.shade200;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.picture_as_pdf,
                                color: Colors.redAccent),
                          ),
                          title: Text(
                            piece.name,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Empfangen: ${_formatDate(piece.receivedAt)}',
                            style:
                                TextStyle(color: Colors.grey.shade700, fontSize: 13),
                          ),
                          trailing: const Icon(Icons.chevron_right,
                              color: Colors.grey),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PdfViewerScreen(
                                  filePath: piece.path,
                                  title: piece.name,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class ReceivedPiece {
  final String name;
  final String path;
  final DateTime receivedAt;

  ReceivedPiece({
    required this.name,
    required this.path,
    required this.receivedAt,
  });
}

/// PDF Viewer
class PdfViewerScreen extends StatelessWidget {
  final String filePath;
  final String title;

  const PdfViewerScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SfPdfViewer.file(File(filePath)),
    );
  }
}
