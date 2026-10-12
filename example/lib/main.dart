// A minimal chat screen: connect, show one conversation's messages as they arrive, send text.
//
//   flutter run --dart-define=TWILIO_TOKEN=<access token> --dart-define=CONVERSATION=<sid or unique name>
//
// A real app fetches the token from its own backend and passes a tokenProvider to connect,
// so the token renews itself. The proof-of-concept harness is lib/harness_app.dart.

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';

const token = String.fromEnvironment('TWILIO_TOKEN');
const conversationName = String.fromEnvironment('CONVERSATION');

void main() => runApp(const MaterialApp(home: ChatScreen()));

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  TwilioConversationsClient? _client;
  String? _conversationSid;
  String _title = 'Connecting…';
  final _input = TextEditingController();

  /// Keyed by index: messages sent in a burst can arrive out of order, and history and
  /// live events can overlap.
  final _messages = SplayTreeMap<int, Message>();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (token.isEmpty || conversationName.isEmpty) {
      setState(() => _title = 'Pass TWILIO_TOKEN and CONVERSATION with --dart-define');
      return;
    }
    try {
      final client = await TwilioConversationsClient.connect(token: token);
      _client = client;
      await client.waitUntilSynced();
      final conversation = await client.getConversation(conversationName);
      // Listen before loading history, so nothing sent in between is missed.
      client.events.listen((event) {
        if (event case MessageAdded(:final message) when message.conversationSid == conversation.sid) {
          setState(() => _messages[message.index] = message);
        }
      });
      final history = await client.getLastMessages(conversation.sid, count: 30);
      setState(() {
        _conversationSid = conversation.sid;
        _title = conversation.friendlyName ?? conversation.uniqueName ?? conversation.sid;
        for (final message in history) {
          _messages[message.index] = message;
        }
      });
    } on ConversationsException catch (e) {
      setState(() => _title = 'Failed: ${e.message}');
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _conversationSid == null) return;
    _input.clear();
    // The sent message comes back as a MessageAdded event, which adds it to the list.
    await _client!.sendText(_conversationSid!, text);
  }

  @override
  void dispose() {
    _client?.shutdown();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages.values.toList();
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: messages.length,
              itemBuilder: (context, i) =>
                  ListTile(title: Text(messages[i].body ?? '[media]'), subtitle: Text(messages[i].author ?? '')),
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(controller: _input, onSubmitted: (_) => _send()),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), tooltip: 'Send', onPressed: _send),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
