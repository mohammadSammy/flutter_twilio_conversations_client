import 'dart:async';
import 'dart:io';

import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';

import 'harness.dart';

/// The proof-of-concept measurements (docs/poc-success-criteria.md). Results go to the
/// harness log and to [results], raw numbers included.
class Measurements {
  Measurements(this._harness);

  final Harness _harness;
  final results = <String>[];

  /// C1 echo mode: this device answers every `ping` from another identity with a `pong`.
  bool echo = false;

  final _pendingPongs = <String, Completer<void>>{};
  final _bursts = <String, _BurstCheck>{};

  void onEvent(ConversationsEvent event) {
    if (event is! MessageAdded) return;
    final body = event.message.body ?? '';
    final client = _harness.client;
    final fromMe = event.message.author == client?.myIdentity;
    final words = body.split(' ');
    if (words.first == 'ping' && words.length == 3 && echo && !fromMe && client != null) {
      unawaited(client.sendText(event.message.conversationSid, 'pong ${words[1]} ${words[2]}'));
    } else if (words.first == 'pong' && words.length == 3 && !fromMe) {
      _pendingPongs.remove('${words[1]} ${words[2]}')?.complete();
    } else if (words.first == 'burst' && words.length == 3) {
      _bursts.putIfAbsent(words[1], () => _BurstCheck(words[1])).add(words[2], event.message.index);
    }
  }

  /// C1: sends [count] pings one after another to a device in echo mode, and reports
  /// half of each round trip, timed on this device's clock only.
  Future<void> measureLatency(String conversationSid, {int count = 20}) async {
    final client = _harness.client!;
    final runId = DateTime.now().millisecondsSinceEpoch.toString();
    final oneWayMs = <double>[];
    for (var seq = 0; seq < count; seq++) {
      final pong = Completer<void>();
      _pendingPongs['$runId $seq'] = pong;
      final stopwatch = Stopwatch()..start();
      await client.sendText(conversationSid, 'ping $runId $seq');
      try {
        await pong.future.timeout(const Duration(seconds: 10));
        oneWayMs.add(stopwatch.elapsedMicroseconds / 2000);
      } on TimeoutException {
        _pendingPongs.remove('$runId $seq');
        _harness.addLog('latency: no pong for ping $seq within 10 s');
      }
    }
    _report(
      'C1 latency ($count pings, ${oneWayMs.length} answered): median ${_ms(_percentile(oneWayMs, 50))}, '
      'p95 ${_ms(_percentile(oneWayMs, 95))}; raw ms ${oneWayMs.map((v) => v.round()).join(', ')}',
    );
  }

  /// C3: sends [count] numbered messages as fast as possible. The receiving device
  /// reports order, gaps and duplicates with [reportBursts].
  Future<void> sendBurst(String conversationSid, {int count = 50}) async {
    final client = _harness.client!;
    final runId = DateTime.now().millisecondsSinceEpoch.toString();
    final stopwatch = Stopwatch()..start();
    await Future.wait([for (var i = 0; i < count; i++) client.sendText(conversationSid, 'burst $runId $i')]);
    _report('C3 burst $runId: sent $count messages in ${stopwatch.elapsedMilliseconds} ms');
  }

  void reportBursts() {
    if (_bursts.isEmpty) _report('C3: no burst messages received yet');
    for (final burst in _bursts.values) {
      _report(burst.summary());
    }
  }

  /// C4: pages back to the first message, 30 at a time, checking for gaps and duplicates.
  Future<void> pageToStart(String conversationSid, {int pageSize = 30}) async {
    final client = _harness.client!;
    final stopwatch = Stopwatch()..start();
    var page = await client.getLastMessages(conversationSid, count: pageSize);
    final firstPageMs = stopwatch.elapsedMilliseconds;
    final indexes = <int>[...page.map((m) => m.index)];
    var pages = 1;
    while (page.isNotEmpty && page.first.index > 0) {
      page = await client.getMessagesBefore(conversationSid, index: page.first.index - 1, count: pageSize);
      indexes.insertAll(0, page.map((m) => m.index));
      pages++;
    }
    final unique = indexes.toSet();
    final gaps = indexes.isEmpty ? 0 : (indexes.last - indexes.first + 1) - unique.length;
    _report(
      'C4 paging: ${indexes.length} messages in $pages pages of $pageSize, first page $firstPageMs ms, '
      'total ${stopwatch.elapsedMilliseconds} ms, starts at ${indexes.isEmpty ? '-' : indexes.first}, '
      'duplicates ${indexes.length - unique.length}, missing $gaps',
    );
  }

  // D2: memory while uploads run.
  Timer? _memoryTimer;
  int _memoryBaseline = 0;
  int _memoryPeak = 0;

  void startMemorySampling() {
    _memoryTimer?.cancel();
    _memoryBaseline = _memoryPeak = ProcessInfo.currentRss;
    _memoryTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final rss = ProcessInfo.currentRss;
      if (rss > _memoryPeak) _memoryPeak = rss;
    });
  }

  void stopMemorySampling() {
    _memoryTimer?.cancel();
    _memoryTimer = null;
    _report(
      'D2 memory: baseline ${_mb(_memoryBaseline)}, peak ${_mb(_memoryPeak)}, '
      'rise ${_mb(_memoryPeak - _memoryBaseline)} (process resident memory)',
    );
  }

  void _report(String line) {
    results.insert(0, line);
    _harness.addLog(line);
  }

  static double _percentile(List<double> values, int p) {
    if (values.isEmpty) return double.nan;
    final sorted = [...values]..sort();
    final rank = (p / 100 * (sorted.length - 1)).round();
    return sorted[rank];
  }

  static String _ms(double v) => v.isNaN ? '-' : '${v.round()} ms';
  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// What the receiving device saw of one burst.
class _BurstCheck {
  _BurstCheck(this.runId);

  final String runId;
  final _seen = <String>{};
  int duplicates = 0;
  int outOfOrder = 0;
  int _lastIndex = -1;

  void add(String number, int messageIndex) {
    if (!_seen.add(number)) duplicates++;
    if (messageIndex < _lastIndex) outOfOrder++;
    _lastIndex = messageIndex;
  }

  String summary() =>
      'C3 burst $runId received: ${_seen.length} distinct, $duplicates duplicates, '
      '$outOfOrder out of index order';
}
