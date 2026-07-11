import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Real progress for bundled-model downloads — bytes received, total bytes
/// (from Content-Length), throughput (bytes/s), ETA. Streams updates so the
/// UI can show a real LinearProgressIndicator value + MB/s + remaining seconds.
class DownloadProgress {
  final int received;
  final int total;          // 0 if server didn't report Content-Length
  final double bytesPerSec; // smoothed
  final Duration elapsed;
  const DownloadProgress(this.received, this.total, this.bytesPerSec, this.elapsed);
  double get fraction => total > 0 ? received / total : 0;
  Duration get etaRemaining => (bytesPerSec <= 0 || total <= 0)
      ? Duration.zero
      : Duration(seconds: ((total - received) / bytesPerSec).round());
}

class ModelDownload extends ChangeNotifier {
  DownloadProgress progress = const DownloadProgress(0, 0, 0, Duration.zero);
  bool downloading = false;
  String? error;

  Future<File?> fetch(Uri url, File dest) async {
    downloading = true;
    error = null;
    progress = const DownloadProgress(0, 0, 0, Duration.zero);
    notifyListeners();
    final sw = Stopwatch()..start();
    final client = HttpClient();
    try {
      final req = await client.getUrl(url);
      final resp = await req.close();
      final total = resp.contentLength; // -1 if unknown
      final sink = dest.openWrite();
      var received = 0;
      var lastReport = 0;
      var lastReportElapsed = 0;
      var smoothed = 0.0;
      await resp.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        final el = sw.elapsedMilliseconds;
        // Report ~5x/sec to keep UI smooth without thrashing.
        if (el - lastReportElapsed > 200 || received == total) {
          final dt = (el - lastReportElapsed) / 1000.0;
          final inst = dt > 0 ? (received - lastReport) / dt : 0;
          // EMA smoothing of throughput.
          smoothed = smoothed == 0 ? inst.toDouble() : smoothed * 0.6 + inst * 0.4;
          progress = DownloadProgress(received, total < 0 ? 0 : total, smoothed,
              Duration(milliseconds: el));
          lastReport = received;
          lastReportElapsed = el;
          notifyListeners();
        }
      }).asFuture<void>();
      await sink.close();
      downloading = false;
      progress = DownloadProgress(received, total < 0 ? received : total, smoothed,
          Duration(milliseconds: sw.elapsedMilliseconds));
      notifyListeners();
      return dest;
    } catch (e) {
      error = '$e';
      downloading = false;
      notifyListeners();
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
