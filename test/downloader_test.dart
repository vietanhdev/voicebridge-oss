import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicebridge/downloader.dart';

void main() {
  test('formatBytes thresholds', () {
    expect(ModelDownload.fmtBytes(512), '512 B');
    expect(ModelDownload.fmtBytes(2048), '2.0 KB');
    expect(ModelDownload.fmtBytes(5 * 1024 * 1024), '5.0 MB');
    expect(ModelDownload.fmtBytes(2 * 1024 * 1024 * 1024), '2.00 GB');
  });

  test('fetch streams real bytes from a local HTTP server', () async {
    // Spin up a tiny HTTP server serving 1 MB of zeros with Content-Length.
    final server = await HttpServer.bind('127.0.0.1', 0);
    final payload = List<int>.filled(1024 * 1024, 0);
    server.listen((req) {
      req.response.contentLength = payload.length;
      req.response.add(payload);
      req.response.close();
    });
    final dl = ModelDownload();
    final tmp = await Directory.systemTemp.createTemp('dl_');
    final f = await dl.fetch(Uri.parse('http://127.0.0.1:${server.port}/test.bin'),
        File('${tmp.path}/out.bin'));
    expect(f, isNotNull);
    expect(await f!.length(), payload.length);
    expect(dl.progress.total, payload.length);
    expect(dl.progress.received, payload.length);
    expect(dl.progress.fraction, 1.0);
    await server.close();
  });

  test('ETA computed from smoothed throughput', () {
    final p = DownloadProgress(1024 * 1024, 10 * 1024 * 1024, 1024 * 1024, const Duration(seconds: 1));
    expect(p.fraction, closeTo(0.1, 1e-6));
    expect(p.etaRemaining.inSeconds, 9);
  });
}
