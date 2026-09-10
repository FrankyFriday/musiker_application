import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/download_service.dart';
import '../services/update_service.dart';

final dioProvider = Provider<Dio>((ref) => Dio());
final downloadServiceProvider = Provider<DownloadService>((ref) => DownloadService(ref.watch(dioProvider)));
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService(ref.watch(downloadServiceProvider)));
final downloadProgressProvider = StateNotifierProvider<DownloadProgressNotifier, double>((ref) => DownloadProgressNotifier());

class DownloadProgressNotifier extends StateNotifier<double> {
  DownloadProgressNotifier() : super(0);
  void updateProgress(double progress) => state = progress;
  void reset() => state = 0;
}
