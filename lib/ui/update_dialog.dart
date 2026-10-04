import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import '../models/update_info.dart';
import '../providers/update_providers.dart';
import '../services/update_service.dart';
import '../utils/logger.dart';

class UpdateDialog extends ConsumerWidget {
  final UpdateInfo updateInfo;
  const UpdateDialog({super.key, required this.updateInfo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(downloadProgressProvider);
    final downloading = ref.watch(downloadInProgressProvider);
    return AlertDialog(
      title: const Text('Update verfügbar'),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Neue Version: ${updateInfo.version}'),
            const SizedBox(height: 8),
            Text('Änderungen: ${updateInfo.notes}'),
            if (updateInfo.mandatory) ...[
              const SizedBox(height: 8),
              const Text(
                'Dieses Update ist erforderlich.',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ],
            if (downloading) ...[
              const SizedBox(height: 16),
              const Text('Herunterladen...'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
              Text('${(progress * 100).toStringAsFixed(1)}%'),
            ],
          ]),
      actions: [
        if (!updateInfo.mandatory && !downloading)
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Später')),
        ElevatedButton(
            onPressed: downloading ? null : () => _download(context, ref),
            child: Text(downloading ? 'Lädt...' : 'Herunterladen')),
      ],
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    if (ref.read(downloadInProgressProvider)) return;

    final downloadingNotifier = ref.read(downloadInProgressProvider.notifier);
    final progressNotifier = ref.read(downloadProgressProvider.notifier);
    downloadingNotifier.state = true;
    final controller = StreamController<double>();
    final subscription = controller.stream.listen(
      progressNotifier.updateProgress,
      onError: (Object error, StackTrace stackTrace) {
        UpdateLogger.error('Download-Fortschritt konnte nicht gelesen werden',
            error, stackTrace);
      },
    );
    try {
      final path = await UpdateService.retry(() async {
        final downloadedPath = await ref
            .read(updateServiceProvider)
            .downloadUpdate(updateInfo, controller);
        if (downloadedPath == null) {
          throw StateError(
              'Update konnte nicht heruntergeladen oder verifiziert werden.');
        }
        return downloadedPath;
      }, 3, const Duration(seconds: 2));
      if (!context.mounted) return;
      final result = await OpenFilex.open(path);
      if (!context.mounted) return;
      if (result.type != ResultType.done) {
        UpdateLogger.error(
            'Installer konnte nicht geöffnet werden: ${result.message}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Installer konnte nicht geöffnet werden: ${result.message}')));
        return;
      }
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      UpdateLogger.error(
          'Fehler beim Öffnen des Installers', error, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $error')));
      }
    } finally {
      await subscription.cancel();
      await controller.close();
      progressNotifier.reset();
      downloadingNotifier.state = false;
    }
  }
}
