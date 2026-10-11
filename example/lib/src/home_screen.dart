import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';

import 'conversation_screen.dart';
import 'harness.dart';

/// Connected: conversations, the event log, and the measurement tools.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final harness = HarnessScope.of(context);
    final client = harness.client!;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(client.myIdentity),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: Column(
              children: [
                Text(
                  '${client.connectionState.name} · sync ${client.syncStatus?.name ?? '-'} · '
                  'token until ${_time(client.tokenExpiresAt)}',
                ),
                const TabBar(
                  tabs: [
                    Tab(text: 'Conversations'),
                    Tab(text: 'Events'),
                    Tab(text: 'Tools'),
                  ],
                ),
              ],
            ),
          ),
          actions: [IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: harness.shutdown)],
        ),
        body: const TabBarView(children: [_ConversationsTab(), _EventsTab(), _ToolsTab()]),
      ),
    );
  }

  static String _time(DateTime? t) =>
      t == null ? '-' : TimeOfDay.fromDateTime(t.toLocal()).toString().substring(10, 15);
}

class _ConversationsTab extends StatefulWidget {
  const _ConversationsTab();

  @override
  State<_ConversationsTab> createState() => _ConversationsTabState();
}

class _ConversationsTabState extends State<_ConversationsTab> {
  final _lookup = TextEditingController();
  Future<List<Conversation>>? _conversations;

  void _reload() {
    final conversations = HarnessScope.of(context).client!.myConversations();
    setState(() {
      _conversations = conversations;
    });
  }

  Future<void> _create() async {
    final name = await _askText(context, 'New conversation', 'Unique name');
    if (name == null || !mounted) return;
    final harness = HarnessScope.of(context);
    await _report(harness, () async {
      final created = await harness.client!.createConversation(uniqueName: name, friendlyName: name);
      await harness.client!.join(created.sid);
      harness.addLog('C8: created and joined ${created.sid}');
    });
    if (mounted) _reload();
  }

  Future<void> _open(String sidOrName) async {
    final harness = HarnessScope.of(context);
    await _report(harness, () async {
      final conversation = await harness.client!.getConversation(sidOrName);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ConversationScreen(conversation)));
    });
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    _conversations ??= HarnessScope.of(context).client!.myConversations();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lookup,
                  decoration: const InputDecoration(labelText: 'Open by SID or unique name (C7)'),
                ),
              ),
              IconButton(icon: const Icon(Icons.search), onPressed: () => _open(_lookup.text.trim())),
              IconButton(tooltip: 'Create and join (C8)', icon: const Icon(Icons.add), onPressed: _create),
              IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _reload),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: _conversations,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
              final conversations = snapshot.data;
              if (conversations == null) return const Center(child: CircularProgressIndicator());
              return ListView(
                children: [
                  for (final c in conversations)
                    ListTile(
                      title: Text(c.uniqueName ?? c.friendlyName ?? c.sid),
                      subtitle: Text(
                        '${c.status.name} · last #${c.lastMessageIndex ?? '-'} · read #${c.lastReadMessageIndex ?? '-'}',
                      ),
                      trailing: _UnreadCount(c.sid),
                      onTap: () => _open(c.sid),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UnreadCount extends StatelessWidget {
  const _UnreadCount(this.conversationSid);

  final String conversationSid;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: HarnessScope.of(context).client!.getUnreadMessagesCount(conversationSid),
    builder: (context, snapshot) =>
        Text(snapshot.connectionState != ConnectionState.done ? '' : 'unread ${snapshot.data ?? 'null'}'),
  );
}

class _EventsTab extends StatelessWidget {
  const _EventsTab();

  @override
  Widget build(BuildContext context) {
    final harness = HarnessScope.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text: harness.log.reversed.map((e) => '${e.time.toIso8601String()} ${e.text}').join('\n'),
                ),
              ),
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () {
                harness.log.clear();
                harness.addLog('log cleared');
              },
              child: const Text('Clear'),
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: harness.log.length,
            itemBuilder: (context, i) {
              final entry = harness.log[i];
              return ListTile(
                dense: true,
                title: Text(entry.text),
                subtitle: Text(entry.time.toIso8601String().substring(11, 23)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ToolsTab extends StatefulWidget {
  const _ToolsTab();

  @override
  State<_ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<_ToolsTab> {
  final _conversation = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final harness = HarnessScope.of(context);
    final client = harness.client!;
    final measurements = harness.measurements;
    String target() => _conversation.text.trim();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const _Heading('Tokens'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(onPressed: () => _report(harness, client.refreshToken), child: const Text('Refresh now')),
            OutlinedButton(
              onPressed: () => _report(harness, harness.applyNewToken),
              child: const Text('Fetch and apply (manual, B4)'),
            ),
            OutlinedButton(
              onPressed: () => setState(() => harness.providerFailuresLeft = 3),
              child: Text('Fail provider 3× (B5) · left ${harness.providerFailuresLeft}'),
            ),
          ],
        ),
        const _Heading('Messaging measurements'),
        TextField(
          controller: _conversation,
          decoration: const InputDecoration(labelText: 'Conversation SID or unique name for the tests'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Echo mode (C1)'),
          subtitle: const Text('Answer every ping from another identity'),
          value: measurements.echo,
          onChanged: (value) => setState(() => measurements.echo = value),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _report(harness, () => _resolve(harness, target()).then(measurements.measureLatency)),
              child: const Text('Latency ×20 (C1)'),
            ),
            OutlinedButton(
              onPressed: () => _report(harness, () => _resolve(harness, target()).then(measurements.sendBurst)),
              child: const Text('Burst ×50 (C3)'),
            ),
            OutlinedButton(onPressed: measurements.reportBursts, child: const Text('Bursts received')),
            OutlinedButton(
              onPressed: () => _report(
                harness,
                () => _resolve(harness, target()).then((sid) => measurements.sendBurst(sid, count: 500)),
              ),
              child: const Text('Seed 500 messages'),
            ),
            OutlinedButton(
              onPressed: () => _report(harness, () => _resolve(harness, target()).then(measurements.pageToStart)),
              child: const Text('Page to start (C4)'),
            ),
          ],
        ),
        const _Heading('Uploads (kept after their screen closes, D3)'),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(onPressed: measurements.startMemorySampling, child: const Text('Start memory sampling')),
            OutlinedButton(onPressed: measurements.stopMemorySampling, child: const Text('Stop and report (D2)')),
          ],
        ),
        for (final upload in harness.uploads)
          ListTile(
            dense: true,
            title: Text(upload.label),
            subtitle: LinearProgressIndicator(
              value: upload.send.totalBytes == 0 ? null : upload.bytesSent / upload.send.totalBytes,
            ),
            trailing: Text(
              upload.error != null
                  ? 'failed'
                  : upload.done
                  ? 'sent'
                  : '${upload.bytesSent} / ${upload.send.totalBytes}',
            ),
          ),
        const _Heading('Results'),
        for (final line in measurements.results) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(line)),
      ],
    );
  }

  Future<String> _resolve(Harness harness, String sidOrName) async =>
      (await harness.client!.getConversation(sidOrName)).sid;
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// Runs an action and logs its failure with the exception type, which the criteria check.
Future<void> _report(Harness harness, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    harness.addLog('failed: $e (${e.runtimeType})');
  }
}

Future<String?> _askText(BuildContext context, String title, String label) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}
