import 'dart:developer' as developer;
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class UpdateLogger {
  static const _logFileName = 'update_log.txt';

  static void info(String message) => _log('INFO', message);
  static void warning(String message) => _log('WARNING', message);
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log('ERROR', message);
    if (error != null) _log('ERROR', 'Error: $error');
    if (stackTrace != null) _log('ERROR', 'StackTrace: $stackTrace');
  }

  static void _log(String level, String message) {
    final line = '[${DateTime.now().toIso8601String()}] [$level] $message';
    developer.log(line, name: 'marschpad');
    if (const bool.fromEnvironment('dart.vm.product')) _writeToFile(line);
  }

  static Future<void> _writeToFile(String message) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      await File('${directory.path}/$_logFileName')
          .writeAsString('$message\n', mode: FileMode.append);
    } catch (error) {
      developer.log('Failed to write update log: $error', name: 'marschpad');
    }
  }
}
