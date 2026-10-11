// Proof-of-concept criteria that need two phones: C1 delivery time, C2 events for every
// conversation, C3 order, C5 typing. Start the responder first, then the measurer, with
// the same PAIR value:
//
//   phone 1: --dart-define=ROLE=responder --dart-define=PAIR=<id>
//   phone 2: --dart-define=ROLE=measurer  --dart-define=PAIR=<id>
//
// They talk through messages in two conversations, `<id>-main` and `<id>-other`, which
// `python3 tool/twilio_rest.py pair <id>` creates first with both identities in them.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';

import 'poc/poc.dart';

const role = String.fromEnvironment('ROLE');
const pair = String.fromEnvironment('PAIR');

void main() {
  setUpPoc();

  testWidgets('pair: $role', (tester) async {
    expect(role, anyOf('responder', 'measurer'), reason: 'pass --dart-define=ROLE=…');
    expect(pair, isNotEmpty, reason: 'pass --dart-define=PAIR=…');
    if (role == 'responder') {
      await _respond();
    } else {
      await _measure();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

/// Joins both conversations, then answers requests until the measurer says `done`.
Future<void> _respond() async {
  final client = await TwilioConversationsClient.connect(token: await fetchToken('$pair-responder'));
  final log = EventLog(client);
  await client.waitUntilSynced();
  final main = await _open(client, '$pair-main');
  final other = await _open(client, '$pair-other');
  await client.sendText(main.sid, 'responder ready');

  final done = Completer<void>();
  final subscription = client.events.listen((event) async {
    if (event is! MessageAdded || event.message.author == client.myIdentity) return;
    final words = (event.message.body ?? '').split(' ');
    switch (words.first) {
      case 'ping':
        await client.sendText(main.sid, 'pong ${words.skip(1).join(' ')}');
      case 'burst-request':
        final count = int.parse(words[1]);
        await Future.wait([for (var i = 0; i < count; i++) client.sendText(main.sid, 'burst ${words[2]} $i')]);
      case 'type-request':
        for (var i = 0; i < 6; i++) {
          await client.typing(main.sid);
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      case 'other-request':
        await client.sendText(other.sid, 'hello in the other conversation');
      case 'done':
        if (!done.isCompleted) done.complete();
    }
  });
  await done.future.timeout(const Duration(minutes: 12));
  report('pair-responder', pass: true, data: {'identity': client.myIdentity});
  await subscription.cancel();
  await log.cancel();
  await client.shutdown();
}

Future<void> _measure() async {
  var client = await TwilioConversationsClient.connect(token: await fetchToken('$pair-measurer'));
  var log = EventLog(client);
  await client.waitUntilSynced();
  final main = await _open(client, '$pair-main');
  final other = await _open(client, '$pair-other');
  await log
      .waitFor<MessageAdded>((e) => e.message.body == 'responder ready', timeout: const Duration(minutes: 5))
      .catchError((Object _) async {
        // The responder may have joined first and said ready before this client listened.
        final last = await client.getLastMessages(main.sid, count: 5);
        if (!last.any((m) => m.body == 'responder ready')) throw TimeoutException('responder not ready');
        return MessageAdded(last.last, main);
      });

  // C1: 20 pings, half of each round trip, timed on this phone's clock only.
  final oneWay = <double>[];
  for (var seq = 0; seq < 20; seq++) {
    final stopwatch = Stopwatch()..start();
    await client.sendText(main.sid, 'ping $seq');
    await log.waitFor<MessageAdded>((e) => e.message.body == 'pong $seq', timeout: const Duration(seconds: 10));
    oneWay.add(stopwatch.elapsedMicroseconds / 2000);
  }
  final c1Pass = median(oneWay) < 1000 && percentile(oneWay, 95) < 2000;
  report(
    'C1',
    pass: c1Pass,
    data: {
      'medianMs': median(oneWay).round(),
      'p95Ms': percentile(oneWay, 95).round(),
      'rawMs': [for (final v in oneWay) v.round()],
    },
  );

  // C3: 50 messages sent at once by the other phone arrive once each, and history returns them in
  // index order. Arrival order is only recorded: Twilio may deliver a burst out of index order.
  final burstId = DateTime.now().millisecondsSinceEpoch.toString();
  await client.sendText(main.sid, 'burst-request 50 $burstId');
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  bool isBurst(Message m) => (m.body ?? '').startsWith('burst $burstId ');
  List<MessageAdded> burst() => log.events.whereType<MessageAdded>().where((e) => isBurst(e.message)).toList();
  while (burst().length < 50 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final received = burst();
  final numbers = received.map((e) => e.message.body!.split(' ').last).toList();
  final indexes = received.map((e) => e.message.index).toList();
  bool increasing(List<int> values) =>
      [for (var i = 1; i < values.length; i++) values[i] > values[i - 1]].every((x) => x);
  final history = (await client.getLastMessages(main.sid, count: 60)).where(isBurst).map((m) => m.index).toList();
  final historyInOrder = history.length == 50 && increasing(history);
  final c3Pass = numbers.toSet().length == 50 && numbers.length == 50 && historyInOrder;
  report(
    'C3',
    pass: c3Pass,
    data: {
      'received': numbers.length,
      'distinct': numbers.toSet().length,
      'historyInIndexOrder': historyInOrder,
      'arrivedInIndexOrder': increasing(indexes),
      if (!increasing(indexes)) 'indexesInArrivalOrder': indexes,
    },
  );

  // C5: typing reaches this phone, then ends.
  final typingStopwatch = Stopwatch()..start();
  await client.sendText(main.sid, 'type-request');
  final requestSentMs = typingStopwatch.elapsedMilliseconds;
  final started = await log
      .waitFor<TypingStarted>((e) => e.conversationSid == main.sid, timeout: const Duration(seconds: 15))
      .then((_) => typingStopwatch.elapsedMilliseconds)
      .catchError((Object _) => -1);
  final ended = await log
      .waitFor<TypingEnded>((e) => e.conversationSid == main.sid, timeout: const Duration(seconds: 30))
      .then((_) => typingStopwatch.elapsedMilliseconds)
      .catchError((Object _) => -1);
  // Request delivery takes about one C1 one-way time; what's left is typing's own delay.
  final typingDelay = started < 0 ? -1 : started - requestSentMs - median(oneWay).round();
  report(
    'C5',
    pass: started >= 0 && ended > started && typingDelay < 1000,
    data: {
      'typingStartedAfterRequestMs': started,
      'estimatedTypingDelayMs': typingDelay,
      'typingEndedAfterRequestMs': ended,
    },
  );

  // C2: reconnect, so listeners exist only for what sync reports, then receive a message
  // in a conversation this client never opened.
  await log.cancel();
  await client.shutdown();
  client = await TwilioConversationsClient.connect(token: await fetchToken('$pair-measurer'));
  log = EventLog(client);
  await client.waitUntilSynced();
  await client.sendText(main.sid, 'other-request');
  final otherMessage = await log
      .waitFor<MessageAdded>((e) => e.conversation.sid == other.sid, timeout: const Duration(seconds: 30))
      .then((e) => e.message.body)
      .catchError((Object _) => null);
  report('C2', pass: otherMessage != null, data: {'receivedInUnopenedConversation': otherMessage});

  await client.sendText(main.sid, 'done');
  await log.cancel();
  await client.shutdown();
  expect(c1Pass && c3Pass && otherMessage != null, isTrue);
}

/// A conversation tool/twilio_rest.py already made this identity a participant of.
Future<Conversation> _open(TwilioConversationsClient client, String uniqueName) => client.getConversation(uniqueName);
