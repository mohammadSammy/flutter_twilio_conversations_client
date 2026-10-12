// Proof-of-concept criteria that need one phone (docs/poc-success-criteria.md).
// Needs tool/token_server.py running; see poc/poc.dart for how the phone reaches it.
//
//   flutter test integration_test/poc_single_test.dart -d <device> [--dart-define=TOKEN_SERVER=…]
//     [--dart-define=C7_SID=<sid> --dart-define=C7_IDENTITY=<identity>]   (from tool/twilio_rest.py)
//     [--dart-define=ONLY=B4,D1]   runs only those tests (flutter test --name doesn't reach the device)
//
// Every result is printed as `POC {json}` for docs/poc-results.md.

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';
import 'package:flutter_twilio_conversations_client_example/src/test_files.dart';

import 'poc/poc.dart';

const only = String.fromEnvironment('ONLY');

/// Written by E3 before the Mac kills the app; on the relaunch only E3's second half runs.
final e3Marker = File('${Directory.systemTemp.path}/poc-e3-identity');
final e3Relaunched = e3Marker.existsSync();

/// True when ONLY names other tests.
bool skipped(String id) => e3Relaunched ? id != 'E3' : only.isNotEmpty && !only.split(',').contains(id);

/// Long or hands-on tests run only when ONLY names them.
bool notNamed(String id) => e3Relaunched ? id != 'E3' : !only.split(',').contains(id);

void main() {
  setUpPoc();
  final run = runName('poc');

  Future<T> withClient<T>(
    String identity,
    Future<T> Function(TwilioConversationsClient client, EventLog log) body, {
    int ttl = 3600,
    TokenProvider? tokenProvider,
  }) async {
    // --dart-define=SDK_LOG=debug turns on the native SDKs' own logging (logcat / console).
    const sdkLog = String.fromEnvironment('SDK_LOG');
    if (sdkLog.isNotEmpty) await TwilioConversationsClient.setLogLevel(LogLevel.values.byName(sdkLog));
    final client = await TwilioConversationsClient.connect(
      token: await fetchToken(identity, ttl: ttl),
      tokenProvider: tokenProvider,
    );
    final log = EventLog(client);
    try {
      return await body(client, log);
    } finally {
      await log.cancel();
      await client.shutdown();
    }
  }

  testWidgets('B2 bad and expired tokens', (tester) async {
    Future<Map<String, Object?>> attempt(String token) async {
      try {
        final client = await TwilioConversationsClient.connect(token: token);
        await client.shutdown();
        return {'outcome': 'connected'};
      } on ConversationsException catch (e) {
        return {'type': '${e.runtimeType}', 'twilioCode': e.twilioCode, 'message': e.message};
      }
    }

    final malformed = await attempt('not-a-valid-token');
    final expired = await attempt(await fetchToken('$run-b2', ttl: -120));
    final pass = malformed['type'] == 'TokenException' && expired['type'] == 'TokenException';
    report('B2', pass: pass, data: {'malformed': malformed, 'expired': expired});
    expect(pass, isTrue, reason: 'malformed: $malformed, expired: $expired');
  }, skip: skipped('B2'));

  testWidgets('B6 logout and login as someone else', (tester) async {
    final first = await TwilioConversationsClient.connect(token: await fetchToken('$run-b6-first'));
    await first.waitUntilSynced();
    final private = await first.createConversation(uniqueName: '$run-b6-private');
    await first.join(private.sid);
    Object? secondConnect;
    try {
      await TwilioConversationsClient.connect(token: await fetchToken('$run-b6-second'));
    } catch (e) {
      secondConnect = e;
    }
    await first.shutdown();

    await withClient('$run-b6-second', (client, log) async {
      await client.waitUntilSynced();
      final mine = await client.myConversations();
      final leaked = mine.any((c) => c.sid == private.sid);
      final otherEvents = log.events.whereType<ConversationAdded>().where((e) => e.conversation.sid == private.sid);
      final pass = secondConnect is ClientAlreadyConnectedException && !leaked && otherEvents.isEmpty;
      report(
        'B6',
        pass: pass,
        data: {
          'secondConnect': '${secondConnect.runtimeType}',
          'identityAfterLogin': client.myIdentity,
          'firstUsersConversationVisible': leaked,
        },
      );
      expect(pass, isTrue);
    });
  }, skip: skipped('B6'));

  testWidgets(
    'B4 manual token mode',
    (tester) async {
      // A 200 s token: Twilio warns about 3 minutes before expiry, so the warning comes quickly.
      await withClient('$run-b4', ttl: 200, (client, log) async {
        final conversation = await client.createConversation(uniqueName: '$run-b4');
        await client.join(conversation.sid);
        final start = DateTime.now();
        // Wait well past the token's expiry (200 s): Android sends nothing within 30 s of it.
        try {
          await log.waitFor<TokenExpired>((_) => true, timeout: const Duration(minutes: 10));
        } on TimeoutException {
          // Reported below as expiredSeen: false.
        }
        String describe(ConversationsEvent e) => switch (e) {
          TokenAboutToExpire() => 'aboutToExpire',
          TokenExpired() => 'expired',
          ConnectionStateChanged(:final state) => 'connection:${state.name}',
          _ => e.runtimeType.toString(),
        };
        final timeline = [for (final e in log.events) describe(e)];
        final warned = log.events.any((e) => e is TokenAboutToExpire);
        final expired = log.events.any((e) => e is TokenExpired);
        await client.updateToken(await fetchToken('$run-b4'));
        // Sending after the update proves the session survived the expiry.
        final sent = await client.sendText(conversation.sid, 'still alive after updateToken');
        final pass = warned && expired && sent.body != null;
        report(
          'B4',
          pass: pass,
          data: {
            'aboutToExpireSeen': warned,
            'expiredSeen': expired,
            'sentAfterUpdate': sent.body != null,
            'secondsWatched': DateTime.now().difference(start).inSeconds,
            'events': timeline,
            'connectionAfter': client.connectionState.name,
          },
        );
        expect(pass, isTrue);
      });
    },
    skip: skipped('B4'),
    timeout: const Timeout(Duration(minutes: 15)),
  );

  testWidgets('B5 token provider fails three times, then recovers', (tester) async {
    var calls = 0;
    await withClient(
      '$run-b5',
      ttl: 200,
      tokenProvider: () async {
        calls++;
        if (calls <= 3) throw StateError('simulated failure $calls');
        return fetchToken('$run-b5');
      },
      (client, log) async {
        final refreshed = await log.waitFor<TokenRefreshed>((_) => true, timeout: const Duration(seconds: 180));
        final failures = log.events.whereType<TokenRefreshFailed>().length;
        final pass = failures == 3 && calls == 4 && refreshed.expiresAt != null;
        report(
          'B5',
          pass: pass,
          data: {'failures': failures, 'providerCalls': calls, 'newExpiry': '${refreshed.expiresAt}'},
        );
        expect(pass, isTrue);
      },
    );
  }, skip: skipped('B5'));

  testWidgets('C4 paging 500+ messages, C6 read state, C8 create and join', (tester) async {
    late String sid;
    await withClient('$run-c4', (client, log) async {
      final created = await client.createConversation(uniqueName: '$run-c4');
      final joined = await client.join(created.sid);
      sid = created.sid;
      report('C8', pass: joined.status == ConversationStatus.joined, data: {'conversation': sid});

      final unreadBefore = await client.getUnreadMessagesCount(sid);
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 520; i++) {
        await client.sendText(sid, 'seed $i');
      }
      final seedSeconds = stopwatch.elapsed.inSeconds;
      final unreadAfterRead = await client.setLastReadMessageIndex(sid, 9);
      report(
        'C6',
        pass: unreadBefore == null && unreadAfterRead != null,
        data: {
          'unreadBeforeAnyRead': unreadBefore,
          'unreadAfterReadingTo9': unreadAfterRead,
          'seededMessages': 520,
          'seedSeconds': seedSeconds,
        },
      );
    });

    // Page from a fresh client, so nothing is cached from sending.
    await withClient('$run-c4', (client, log) async {
      await client.waitUntilSynced();
      final stopwatch = Stopwatch()..start();
      var page = await client.getLastMessages(sid, count: 30);
      final firstPageMs = stopwatch.elapsedMilliseconds;
      final indexes = [...page.map((m) => m.index)];
      while (page.isNotEmpty && page.first.index > 0) {
        page = await client.getMessagesBefore(sid, index: page.first.index - 1, count: 30);
        indexes.insertAll(0, page.map((m) => m.index));
      }
      final unique = indexes.toSet();
      final gaps = indexes.isEmpty ? 0 : (indexes.last - indexes.first + 1) - unique.length;
      final pass = indexes.first == 0 && gaps == 0 && unique.length == indexes.length && firstPageMs < 1500;
      report(
        'C4',
        pass: pass,
        data: {
          'messages': indexes.length,
          'firstPageMs': firstPageMs,
          'totalMs': stopwatch.elapsedMilliseconds,
          'duplicates': indexes.length - unique.length,
          'missing': gaps,
        },
      );
      expect(pass, isTrue);
    });
  }, skip: skipped('C4'));

  testWidgets('D1 media types, D2 memory, D4 bad file, D5 download', (tester) async {
    await withClient('$run-d', (client, log) async {
      final conversation = await client.createConversation(uniqueName: '$run-d');
      await client.join(conversation.sid);

      final d1 = <Map<String, Object?>>[];
      var d1Pass = true;
      var memoryRiseMb = 0.0;
      Message? sample;
      for (final testFile in TestFile.all) {
        final file = await testFile.create();
        final baseline = ProcessInfo.currentRss;
        var peak = baseline;
        final sampler = Timer.periodic(const Duration(milliseconds: 100), (_) {
          final rss = ProcessInfo.currentRss;
          if (rss > peak) peak = rss;
        });
        final progress = <int>[];
        final stopwatch = Stopwatch()..start();
        final send = client.sendMedia(
          conversation.sid,
          MediaUpload(filePath: file.path, contentType: testFile.contentType, filename: testFile.filename),
        );
        send.bytesSent.listen(progress.add);
        Message message;
        try {
          message = await send.message;
        } on ConversationsException catch (e) {
          sampler.cancel();
          d1Pass = false;
          d1.add({
            'file': testFile.label,
            'ok': false,
            'error': '${e.runtimeType}',
            'twilioCode': e.twilioCode,
            'message': e.message,
            'seconds': stopwatch.elapsedMilliseconds / 1000,
            'lastProgress': progress.isEmpty ? null : progress.last,
          });
          continue;
        }
        sampler.cancel();
        final media = message.media.single;
        final increasing = [for (var i = 1; i < progress.length; i++) progress[i] >= progress[i - 1]].every((x) => x);
        final ok =
            media.contentType == testFile.contentType &&
            media.filename == testFile.filename &&
            media.size == testFile.bytes &&
            increasing &&
            progress.isNotEmpty &&
            progress.last == testFile.bytes;
        d1Pass &= ok;
        if (testFile.bytes == 50 * 1024 * 1024) memoryRiseMb = (peak - baseline) / (1024 * 1024);
        sample ??= message;
        d1.add({
          'file': testFile.label,
          'ok': ok,
          'seconds': stopwatch.elapsedMilliseconds / 1000,
          'progressEvents': progress.length,
          'lastProgress': progress.isEmpty ? null : progress.last,
          'size': media.size,
        });
      }
      report('D1', pass: d1Pass, data: {'uploads': d1});
      report('D2', pass: memoryRiseMb < 30, data: {'memoryRiseMbDuring50MbUpload': memoryRiseMb.toStringAsFixed(1)});

      final badStart = Stopwatch()..start();
      Object? badError;
      try {
        await client
            .sendMedia(conversation.sid, const MediaUpload(filePath: '/no/such/file', contentType: 'image/jpeg'))
            .message;
      } catch (e) {
        badError = e;
      }
      report(
        'D4',
        pass: badError is MediaUploadException,
        data: {'error': '${badError.runtimeType}', 'ms': badStart.elapsedMilliseconds},
      );

      Future<int> download(Uri url) async {
        final http = HttpClient();
        try {
          final response = await (await http.getUrl(url)).close();
          var bytes = 0;
          await for (final chunk in response) {
            bytes += chunk.length;
          }
          return bytes;
        } finally {
          http.close();
        }
      }

      if (sample == null) {
        report('D5', pass: false, data: {'skipped': 'no upload succeeded'});
        fail('no upload succeeded: $d1');
      }
      final media = sample.media.single;
      Future<Uri> freshUrl() => client.getMediaTemporaryUrl(
        conversationSid: conversation.sid,
        messageIndex: sample!.index,
        mediaSid: media.sid,
      );
      final first = await download(await freshUrl());
      await Future<void>.delayed(const Duration(seconds: 60));
      final second = await download(await freshUrl());
      final d5Pass = first == media.size && second == media.size;
      report('D5', pass: d5Pass, data: {'expected': media.size, 'firstDownload': first, 'secondUrlAfter60s': second});

      expect(d1Pass && memoryRiseMb < 30 && badError is MediaUploadException && d5Pass, isTrue);
    });
  }, skip: skipped('D1'));

  testWidgets('C7 removed from a conversation', (tester) async {
    const sid = String.fromEnvironment('C7_SID');
    const identity = String.fromEnvironment('C7_IDENTITY');
    if (sid.isEmpty) {
      report('C7', pass: false, data: {'skipped': 'run tool/twilio_rest.py removed-conversation first'});
      return;
    }
    await withClient(identity, (client, log) async {
      await client.waitUntilSynced();
      Object? error;
      try {
        await client.getConversation(sid);
      } catch (e) {
        error = e;
      }
      final pass = error is ConversationNotFoundException;
      report(
        'C7',
        pass: pass,
        data: {
          'error': '${error.runtimeType}',
          'twilioCode': error is ConversationsException ? error.twilioCode : null,
          'message': error is ConversationsException ? error.message : '$error',
        },
      );
      expect(pass, isTrue);
    });
  }, skip: skipped('C7'));

  testWidgets('B1 sync time, 5 connects', (tester) async {
    const identity = String.fromEnvironment('B1_IDENTITY');
    if (identity.isEmpty) {
      report('B1', pass: false, data: {'skipped': 'run tool/twilio_rest.py conversations <identity> 20 first'});
      return;
    }
    final syncMs = <int>[];
    var conversations = 0;
    for (var i = 0; i < 5; i++) {
      final token = await fetchToken(identity);
      final stopwatch = Stopwatch()..start();
      final client = await TwilioConversationsClient.connect(token: token);
      await client.waitUntilSynced();
      syncMs.add(stopwatch.elapsedMilliseconds);
      conversations = (await client.myConversations()).length;
      await client.shutdown();
    }
    final pass = median(syncMs) < 5000 && conversations >= 20;
    report(
      'B1',
      pass: pass,
      data: {
        'medianMs': median(syncMs).round(),
        'rawMs': syncMs,
        'conversations': conversations,
        'note': 'five connects in one app process; only the first starts with a fresh process',
      },
    );
    expect(pass, isTrue);
  }, skip: skipped('B1'));

  testWidgets(
    'B3 automatic refresh with 3-minute tokens for 15 minutes',
    (tester) async {
      final start = DateTime.now();
      int seconds() => DateTime.now().difference(start).inSeconds;
      await withClient('$run-b3', ttl: 180, tokenProvider: () => fetchToken('$run-b3', ttl: 180), (client, log) async {
        final refreshedAt = <int>[];
        final subscription = client.events.listen((e) {
          if (e is TokenRefreshed) refreshedAt.add(seconds());
        });
        final conversation = await client.createConversation(uniqueName: '$run-b3');
        await client.join(conversation.sid);
        var sent = 0;
        final failures = <String>[];
        while (DateTime.now().difference(start) < const Duration(minutes: 15)) {
          try {
            await client.sendText(conversation.sid, 'b3 $sent');
            sent++;
          } on ConversationsException catch (e) {
            failures.add('${seconds()}s $e');
          }
          await Future<void>.delayed(const Duration(seconds: 30));
        }
        await subscription.cancel();
        final states = [
          for (final e in log.events)
            if (e is ConnectionStateChanged) e.state.name,
        ];
        const visible = {'disconnected', 'denied', 'error', 'fatalError'};
        final pass = failures.isEmpty && refreshedAt.length >= 4 && !states.any(visible.contains);
        report(
          'B3',
          pass: pass,
          data: {
            'minutes': 15,
            'sent': sent,
            'failures': failures,
            'refreshedAtSeconds': refreshedAt,
            'refreshFailures': log.events.whereType<TokenRefreshFailed>().length,
            'connectionStates': states,
          },
        );
        expect(pass, isTrue);
      });
    },
    skip: notNamed('B3'),
    timeout: const Timeout(Duration(minutes: 20)),
  );

  testWidgets(
    'E1 network drop',
    (tester) async {
      await withClient('$run-e1', (client, log) async {
        final conversation = await client.createConversation(uniqueName: '$run-e1');
        await client.join(conversation.sid);
        final mark = log.events.length;
        bool after(ConversationsEvent e, int index) => log.events.indexOf(e) >= index;
        await instruct(tester, 'E1', 'Turn ON airplane mode, with Wi-Fi off too.');
        final dropped = await log.waitFor<ConnectionStateChanged>(
          (e) => e.state != ClientConnectionState.connected && after(e, mark),
          timeout: const Duration(minutes: 5),
        );
        final droppedAt = DateTime.now();
        // The Mac sends three messages into the conversation while this phone is offline.
        debugPrint('POC-SEND ${conversation.sid} e1-offline');
        await instruct(tester, 'E1', 'Offline seen. Wait 30 seconds, then turn airplane mode OFF and Wi-Fi back on.');
        final back = log.events.length;
        await log.waitFor<ConnectionStateChanged>(
          (e) => e.state == ClientConnectionState.connected && after(e, back),
          timeout: const Duration(minutes: 5),
        );
        final offlineSeconds = DateTime.now().difference(droppedAt).inSeconds;
        await instruct(tester, 'E1', 'Back online. Checking the messages; nothing to do.');
        List<String> received() => [
          for (final e in log.events)
            if (e is MessageAdded && (e.message.body ?? '').startsWith('e1-offline')) e.message.body!,
        ];
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (received().toSet().length < 3 && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        await Future<void>.delayed(const Duration(seconds: 10)); // room for duplicates to show up
        final got = received();
        final pass = got.length == 3 && got.toSet().length == 3;
        report(
          'E1',
          pass: pass,
          data: {'droppedTo': dropped.state.name, 'secondsOffline': offlineSeconds, 'messagesReceived': got},
        );
        expect(pass, isTrue);
      });
    },
    skip: notNamed('E1'),
    timeout: const Timeout(Duration(minutes: 15)),
  );

  testWidgets(
    'E2 ten minutes in the background',
    (tester) async {
      await withClient('$run-e2', (client, log) async {
        final conversation = await client.createConversation(uniqueName: '$run-e2');
        await client.join(conversation.sid);
        final lifecycle = LifecycleLog();
        await instruct(
          tester,
          'E2',
          'Press Home now. Leave this app in the background for 10 minutes, then reopen it.',
        );
        final pausedAt = await lifecycle.waitFor(AppLifecycleState.paused, const Duration(minutes: 5));
        // The Mac sends three messages into the conversation while the app is in the background.
        debugPrint('POC-SEND ${conversation.sid} e2-background');
        final resumedAt = await lifecycle.waitFor(
          AppLifecycleState.resumed,
          const Duration(minutes: 30),
          after: pausedAt,
        );
        final mark = log.events.length;
        await instruct(tester, 'E2', 'Welcome back. Checking the messages; nothing to do.');
        int? reconnectMs;
        int? messagesMs;
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (messagesMs == null && DateTime.now().isBefore(deadline)) {
          final ms = DateTime.now().difference(resumedAt).inMilliseconds;
          final events = log.events.sublist(mark);
          if (reconnectMs == null &&
              events.any((e) => e is ConnectionStateChanged && e.state == ClientConnectionState.connected)) {
            reconnectMs = ms;
          }
          final bodies = {
            for (final e in log.events)
              if (e is MessageAdded && (e.message.body ?? '').startsWith('e2-background')) e.message.body,
          };
          if (bodies.length == 3) messagesMs = ms;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        lifecycle.dispose();
        final dropped = log.events.sublist(mark).any((e) => e is ConnectionStateChanged);
        // No connection event after resuming means the connection never dropped.
        final pass = (reconnectMs ?? 0) <= 5000 && messagesMs != null;
        report(
          'E2',
          pass: pass,
          data: {
            'minutesInBackground': (resumedAt.difference(pausedAt).inSeconds / 60).toStringAsFixed(1),
            'connectionEventsAfterResume': dropped,
            'reconnectMsAfterResume': reconnectMs,
            'messagesMsAfterResume': messagesMs,
          },
        );
        expect(pass, isTrue);
      });
    },
    skip: notNamed('E2'),
    timeout: const Timeout(Duration(minutes: 40)),
  );

  testWidgets(
    'E3 killed and relaunched',
    (tester) async {
      if (!e3Relaunched) {
        final identity = '$run-e3';
        e3Marker.writeAsStringSync(identity);
        await withClient(identity, (client, log) async {
          final conversation = await client.createConversation(uniqueName: identity);
          await client.join(conversation.sid);
          await client.sendText(conversation.sid, 'before kill');
          await instruct(tester, 'E3', 'Nothing to do: the Mac kills and relaunches this app now.');
          await Future<void>.delayed(const Duration(minutes: 5));
        });
        e3Marker.deleteSync();
        report('E3', pass: false, data: {'skipped': 'the app was not killed within 5 minutes'});
        fail('the app was not killed');
      }
      final identity = e3Marker.readAsStringSync();
      e3Marker.deleteSync();
      final stopwatch = Stopwatch()..start();
      await withClient(identity, (client, log) async {
        await client.waitUntilSynced();
        final syncMs = stopwatch.elapsedMilliseconds;
        final conversation = (await client.myConversations()).where((c) => c.uniqueName == identity).firstOrNull;
        final last = conversation == null
            ? null
            : (await client.getLastMessages(conversation.sid, count: 1)).firstOrNull?.body;
        final sent = conversation == null ? null : await client.sendText(conversation.sid, 'after relaunch');
        final pass = conversation != null && last == 'before kill' && sent != null;
        report(
          'E3',
          pass: pass,
          data: {
            'syncMsAfterRelaunchWithTokenFetch': syncMs,
            'conversationFound': conversation != null,
            'lastMessage': last,
          },
        );
        expect(pass, isTrue);
      });
    },
    skip: notNamed('E3'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
