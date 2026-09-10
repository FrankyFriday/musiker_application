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
    final downloading = progress > 0 && progress < 1;
    return AlertDialog(
      title: const Text('Update verfügbar'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Neue Version: ${updateInfo.version}'),
        const SizedBox(height: 8),
        Text('Änderungen: ${updateInfo.notes}'),
        if (downloading) ...[
          const SizedBox(height: 16),
          const Text('Herunterladen...'),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
          Text('${(progress * 100).toStringAsFixed(1)}%'),
        ],
      ]),
      actions: [
        if (!updateInfo.mandatory) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Später')),
        ElevatedButton(onPressed: downloading ? null : () => _download(context, ref), child: Text(downloading ? 'Lädt...' : 'Herunterladen')),
      ],
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final controller = StreamController<double>();
    final notifier = ref.read(downloadProgressProvider.notifier);
    final subscription = controller.stream.listen(notifier.updateProgress);
    try {
      final path = await UpdateService.retry(
        () => ref.read(updateServiceProvider).downloadUpdate(updateInfo, controller),
        3, const Duration(seconds: 2));
      if (!context.mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download fehlgeschlagen')));
        return;
      }
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        UpdateLogger.error('Installer konnte nicht geöffnet werden: ${result.message}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Installer konnte nicht geöffnet werden: ${result.message}')));
        return;
      }
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      UpdateLogger.error('Fehler beim Öffnen des Installers', error, stackTrace);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $error')));
    } finally {
      await subscription.cancel();
      await controller.close();
      notifier.reset();
    }
  }
}
