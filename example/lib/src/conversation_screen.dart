import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';

import 'harness.dart';
import 'test_files.dart';

/// One conversation: messages and paging (C4), sending, typing (C5), read state (C6)
/// and media (D1, D4, D5).
class ConversationScreen extends StatefulWidget {
  const ConversationScreen(this.conversation, {super.key});

  final Conversation conversation;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  static const _pageSize = 30;

  late final Harness _harness = HarnessScope.of(context);
  late final TwilioConversationsClient _client = _harness.client!;
  late final StreamSubscription<ConversationsEvent> _events = _client.events.listen(_onEvent);
  final _text = TextEditingController();
  final _messages = <Message>[];
  final _typing = <String>{};
  int? _unread;
  bool _loading = false;
  bool _started = false;

  String get _sid => widget.conversation.sid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs again whenever the harness changes, so load the first page only once.
    if (!_started) {
      _started = true;
      _events; // starts listening before the first page loads
      _loadOlder();
      _refreshUnread();
    }
  }

  @override
  void dispose() {
    _events.cancel();
    super.dispose();
  }

  void _onEvent(ConversationsEvent event) {
    switch (event) {
      case MessageAdded(:final message) when message.conversationSid == _sid:
        if (!_messages.any((m) => m.sid == message.sid)) setState(() => _messages.add(message));
      case TypingStarted(:final conversationSid, :final participant) when conversationSid == _sid:
        setState(() => _typing.add(participant.identity ?? participant.sid));
      case TypingEnded(:final conversationSid, :final participant) when conversationSid == _sid:
        setState(() => _typing.remove(participant.identity ?? participant.sid));
      default:
    }
  }

  Future<void> _loadOlder() async {
    setState(() => _loading = true);
    final stopwatch = Stopwatch()..start();
    try {
      final page = _messages.isEmpty
          ? await _client.getLastMessages(_sid, count: _pageSize)
          : await _client.getMessagesBefore(_sid, index: _messages.first.index - 1, count: _pageSize);
      _harness.addLog('page of ${page.length} loaded in ${stopwatch.elapsedMilliseconds} ms');
      setState(() => _messages.insertAll(0, page.where((m) => !_messages.any((old) => old.sid == m.sid))));
    } catch (e) {
      _harness.addLog('paging failed: $e (${e.runtimeType})');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshUnread() async {
    final unread = await _client.getUnreadMessagesCount(_sid);
    _harness.addLog('C6: unread in $_sid is ${unread ?? 'null (never read)'}');
    if (mounted) setState(() => _unread = unread);
  }

  Future<void> _markRead() async {
    if (_messages.isEmpty) return;
    final unread = await _client.setLastReadMessageIndex(_sid, _messages.last.index);
    _harness.addLog('C6: read up to #${_messages.last.index}; unread now $unread');
    setState(() => _unread = unread);
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    _text.clear();
    try {
      await _client.sendText(_sid, body);
    } catch (e) {
      _harness.addLog('send failed: $e (${e.runtimeType})');
    }
  }

  Future<void> _sendFile(TestFile? testFile) async {
    // null sends a path that doesn't exist, which must fail with MediaUploadException (D4).
    final path = testFile == null ? '/no/such/file.jpg' : (await testFile.create()).path;
    final upload = MediaUpload(
      filePath: path,
      contentType: testFile?.contentType ?? 'image/jpeg',
      filename: testFile?.filename,
    );
    _harness.trackUpload(testFile?.label ?? 'missing file', _client.sendMedia(_sid, upload));
  }

  Future<void> _download(Message message, Media media) async {
    final stopwatch = Stopwatch()..start();
    try {
      final url = await _client.getMediaTemporaryUrl(
        conversationSid: _sid,
        messageIndex: message.index,
        mediaSid: media.sid,
      );
      final http = HttpClient();
      var bytes = 0;
      try {
        final response = await (await http.getUrl(url)).close();
        await for (final chunk in response) {
          bytes += chunk.length;
        }
      } finally {
        http.close();
      }
      _harness.addLog(
        'D5: downloaded ${media.filename} in ${stopwatch.elapsedMilliseconds} ms: $bytes bytes, '
        'expected ${media.size} (${bytes == media.size ? 'match' : 'MISMATCH'})',
      );
    } catch (e) {
      _harness.addLog('D5: download failed: $e (${e.runtimeType})');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.uniqueName ?? c.friendlyName ?? c.sid),
        actions: [
          TextButton(onPressed: _refreshUnread, child: Text('unread ${_unread ?? 'null'}')),
          IconButton(tooltip: 'Mark all read (C6)', icon: const Icon(Icons.done_all), onPressed: _markRead),
          PopupMenuButton<TestFile?>(
            tooltip: 'Send a test file',
            icon: const Icon(Icons.attach_file),
            onSelected: _sendFile,
            itemBuilder: (_) => [
              for (final file in TestFile.all) PopupMenuItem(value: file, child: Text(file.label)),
              const PopupMenuItem(child: Text('A missing file (D4)')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          TextButton(
            onPressed: _loading || (_messages.isNotEmpty && _messages.first.index == 0) ? null : _loadOlder,
            child: Text(_loading ? 'Loading…' : 'Load $_pageSize older'),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final m in _messages)
                  ListTile(
                    dense: true,
                    title: Text(m.body ?? (m.media.isEmpty ? '' : '${m.media.length} media')),
                    subtitle: Text('#${m.index} · ${m.author} · ${m.dateCreated?.toLocal()}'),
                    trailing: m.media.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Download (D5)',
                            icon: const Icon(Icons.download),
                            onPressed: () => _download(m, m.media.first),
                          ),
                  ),
              ],
            ),
          ),
          if (_typing.isNotEmpty)
            Padding(padding: const EdgeInsets.all(4), child: Text('${_typing.join(', ')} typing…')),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('composer'),
                      controller: _text,
                      decoration: const InputDecoration(hintText: 'Message'),
                      onChanged: (_) => _client.typing(_sid).ignore(),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send), onPressed: _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
