import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../services/nextcloud_service.dart';
import '../theme/app_theme.dart';

class OfflinePracticePage extends StatefulWidget {
  final String instrument;
  final String voice;
  final bool darkMode;

  const OfflinePracticePage({
    super.key,
    required this.instrument,
    required this.voice,
    this.darkMode = false,
  });

  @override
  State<OfflinePracticePage> createState() => _OfflinePracticePageState();
}

class _OfflinePracticePageState extends State<OfflinePracticePage> {
  final _nextcloudService = NextcloudService();
  final _searchController = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<ReceivedPiece> _pieces = [];

  @override
  void initState() {
    super.initState();
    _loadOfflinePieces();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOfflinePieces() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final cachedFiles = await _nextcloudService.listCachedPdfs(
        widget.instrument,
        widget.voice,
      );
      if (!mounted) return;
      if (cachedFiles.isNotEmpty) {
        setState(() {
          _pieces = _piecesFromFiles(cachedFiles);
          _isLoading = false;
        });
      }
    } on FileSystemException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }

    try {
      final files = await _nextcloudService.listAndDownloadPdfs(
        widget.instrument,
        widget.voice,
      );
      final pieces = _piecesFromFiles(files);

      if (!mounted) return;
      setState(() {
        _pieces = pieces;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (_pieces.isEmpty) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<ReceivedPiece> _piecesFromFiles(List<File> files) => files
      .map(
        (file) => ReceivedPiece(
          name: file.path.split(Platform.pathSeparator).last.split('_').first,
          path: file.path,
          receivedAt: DateTime.now(),
        ),
      )
      .toList()
    ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

  List<ReceivedPiece> get _filteredPieces {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _pieces;
    return _pieces
        .where((piece) => piece.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.darkMode ? AppTheme.dark : AppTheme.light;
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          final pieces = _filteredPieces;
          return Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Offline-Noten'),
                  Text(
                    'FÜR ${widget.instrument.toUpperCase()} · STIMME ${widget.voice}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Noten synchronisieren',
                  onPressed: _loadOfflinePieces,
                  icon: const Icon(Icons.sync_rounded),
                ),
                const SizedBox(width: 6),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Stücke durchsuchen',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Suche löschen',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                  if (!_isLoading && _error == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                      child: Row(
                        children: [
                          Icon(Icons.download_done_rounded,
                              size: 17, color: colors.secondary),
                          const SizedBox(width: 7),
                          Text(
                            '${_pieces.length} Noten lokal verfügbar',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? _OfflineState(
                                icon: Icons.cloud_off_rounded,
                                title: 'Synchronisierung fehlgeschlagen',
                                message: _error!,
                                actionLabel: 'Erneut versuchen',
                                onAction: _loadOfflinePieces,
                              )
                            : pieces.isEmpty
                                ? _OfflineState(
                                    icon: Icons.library_music_outlined,
                                    title: _pieces.isEmpty
                                        ? 'Noch keine Offline-Noten'
                                        : 'Keine Treffer',
                                    message: _pieces.isEmpty
                                        ? 'Verbinde dich mit dem Server, um die Noten für dein Pult herunterzuladen.'
                                        : 'Mit diesem Suchbegriff wurde kein Stück gefunden.',
                                    actionLabel: _pieces.isEmpty
                                        ? 'Synchronisieren'
                                        : null,
                                    onAction: _pieces.isEmpty
                                        ? _loadOfflinePieces
                                        : null,
                                  )
                                : RefreshIndicator(
                                    onRefresh: _loadOfflinePieces,
                                    child: ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(
                                          20, 0, 20, 24),
                                      itemCount: pieces.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 10),
                                      itemBuilder: (_, index) => _PieceCard(
                                        piece: pieces[index],
                                        darkMode: widget.darkMode,
                                      ),
                                    ),
                                  ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OfflineState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _OfflineState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: colors.secondary),
            const SizedBox(height: 15),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.sync_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PieceCard extends StatelessWidget {
  final ReceivedPiece piece;
  final bool darkMode;

  const _PieceCard({required this.piece, required this.darkMode});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              filePath: piece.path,
              title: piece.name,
              darkMode: darkMode,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFB43C4B).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded,
                    color: Color(0xFFB43C4B)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      piece.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _formatDate(piece.receivedAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: colors.secondary),
            ],
          ),
        ),
      ),
    );
  }
}

class ReceivedPiece {
  final String name;
  final String path;
  final DateTime receivedAt;
  final bool active;

  const ReceivedPiece({
    required this.name,
    required this.path,
    required this.receivedAt,
    this.active = false,
  });
}

class PdfViewerScreen extends StatelessWidget {
  final String filePath;
  final String title;
  final bool darkMode;

  const PdfViewerScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.darkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: darkMode ? AppTheme.dark : AppTheme.light,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SfPdfViewer.file(File(filePath)),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final localDate = date.toLocal();
  final day = localDate.day.toString().padLeft(2, '0');
  final month = localDate.month.toString().padLeft(2, '0');
  return '$day.$month.${localDate.year}';
}
