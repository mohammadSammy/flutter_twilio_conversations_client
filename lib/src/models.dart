import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'generated/conversations_api.g.dart';

// Immutable snapshots. Dart never holds a native object; changes arrive as events
// carrying a fresh snapshot (api-design §1, §9).

enum ConversationStatus { joined, notParticipating }

enum MediaCategory { media, body, history }

final class Conversation {
  const Conversation({
    required this.sid,
    required this.status,
    this.uniqueName,
    this.friendlyName,
    this.attributesJson,
    this.lastMessageIndex,
    this.lastMessageDate,
    this.lastReadMessageIndex,
    this.dateCreated,
    this.createdBy,
  });

  factory Conversation.fromPlatform(ConversationData data) => Conversation(
    sid: data.sid,
    status: ConversationStatus.values.byName(data.status.name),
    uniqueName: data.uniqueName,
    friendlyName: data.friendlyName,
    attributesJson: data.attributesJson,
    lastMessageIndex: data.lastMessageIndex,
    lastMessageDate: _date(data.lastMessageDateMillis),
    lastReadMessageIndex: data.lastReadMessageIndex,
    dateCreated: _date(data.dateCreatedMillis),
    createdBy: data.createdBy,
  );

  final String sid;
  final ConversationStatus status;
  final String? uniqueName;
  final String? friendlyName;

  /// The attributes as Twilio stores them: JSON text, or null when there are none.
  final String? attributesJson;

  /// Index of the newest message, or null when there are no messages.
  final int? lastMessageIndex;
  final DateTime? lastMessageDate;

  /// My read position; null until I've read something.
  final int? lastReadMessageIndex;
  final DateTime? dateCreated;
  final String? createdBy;

  /// The attributes decoded: a Map, List, String, num, bool, or null.
  Object? get attributes => _decode(attributesJson);

  @override
  bool operator ==(Object other) =>
      other is Conversation &&
      other.sid == sid &&
      other.status == status &&
      other.uniqueName == uniqueName &&
      other.friendlyName == friendlyName &&
      other.attributesJson == attributesJson &&
      other.lastMessageIndex == lastMessageIndex &&
      other.lastMessageDate == lastMessageDate &&
      other.lastReadMessageIndex == lastReadMessageIndex &&
      other.dateCreated == dateCreated &&
      other.createdBy == createdBy;

  @override
  int get hashCode => Object.hash(
    sid,
    status,
    uniqueName,
    friendlyName,
    attributesJson,
    lastMessageIndex,
    lastMessageDate,
    lastReadMessageIndex,
    dateCreated,
    createdBy,
  );

  @override
  String toString() => 'Conversation($sid, ${uniqueName ?? friendlyName ?? ''}, $status)';
}

final class Message {
  const Message({
    required this.conversationSid,
    required this.sid,
    required this.index,
    this.media = const [],
    this.author,
    this.body,
    this.dateCreated,
    this.attributesJson,
    this.participantSid,
  });

  factory Message.fromPlatform(MessageData data) => Message(
    conversationSid: data.conversationSid,
    sid: data.sid,
    index: data.index,
    media: List.unmodifiable(data.media.map(Media.fromPlatform)),
    author: data.author,
    body: data.body,
    dateCreated: _date(data.dateCreatedMillis),
    attributesJson: data.attributesJson,
    participantSid: data.participantSid,
  );

  final String conversationSid;
  final String sid;
  final int index;
  final List<Media> media;

  /// The sender's identity.
  final String? author;
  final String? body;
  final DateTime? dateCreated;

  /// The attributes as Twilio stores them: JSON text, or null when there are none.
  final String? attributesJson;
  final String? participantSid;

  /// The attributes decoded: a Map, List, String, num, bool, or null.
  Object? get attributes => _decode(attributesJson);

  @override
  bool operator ==(Object other) =>
      other is Message &&
      other.conversationSid == conversationSid &&
      other.sid == sid &&
      other.index == index &&
      listEquals(other.media, media) &&
      other.author == author &&
      other.body == body &&
      other.dateCreated == dateCreated &&
      other.attributesJson == attributesJson &&
      other.participantSid == participantSid;

  @override
  int get hashCode => Object.hash(
    conversationSid,
    sid,
    index,
    Object.hashAll(media),
    author,
    body,
    dateCreated,
    attributesJson,
    participantSid,
  );

  @override
  String toString() => 'Message($conversationSid #$index, $author, ${media.length} media)';
}

final class Media {
  const Media({
    required this.sid,
    required this.category,
    required this.contentType,
    required this.size,
    this.filename,
  });

  factory Media.fromPlatform(MediaData data) => Media(
    sid: data.sid,
    category: MediaCategory.values.byName(data.category.name),
    contentType: data.contentType,
    size: data.size,
    filename: data.filename,
  );

  final String sid;
  final MediaCategory category;
  final String contentType;

  /// Bytes.
  final int size;
  final String? filename;

  @override
  bool operator ==(Object other) =>
      other is Media &&
      other.sid == sid &&
      other.category == category &&
      other.contentType == contentType &&
      other.size == size &&
      other.filename == filename;

  @override
  int get hashCode => Object.hash(sid, category, contentType, size, filename);

  @override
  String toString() => 'Media($sid, $contentType, $size bytes)';
}

final class Participant {
  const Participant({
    required this.sid,
    this.identity,
    this.dateCreated,
    this.lastReadMessageIndex,
    this.attributesJson,
  });

  factory Participant.fromPlatform(ParticipantData data) => Participant(
    sid: data.sid,
    identity: data.identity,
    dateCreated: _date(data.dateCreatedMillis),
    lastReadMessageIndex: data.lastReadMessageIndex,
    attributesJson: data.attributesJson,
  );

  final String sid;
  final String? identity;

  /// When they joined.
  final DateTime? dateCreated;
  final int? lastReadMessageIndex;

  /// The attributes as Twilio stores them: JSON text, or null when there are none.
  final String? attributesJson;

  /// The attributes decoded: a Map, List, String, num, bool, or null.
  Object? get attributes => _decode(attributesJson);

  @override
  bool operator ==(Object other) =>
      other is Participant &&
      other.sid == sid &&
      other.identity == identity &&
      other.dateCreated == dateCreated &&
      other.lastReadMessageIndex == lastReadMessageIndex &&
      other.attributesJson == attributesJson;

  @override
  int get hashCode => Object.hash(sid, identity, dateCreated, lastReadMessageIndex, attributesJson);

  @override
  String toString() => 'Participant($sid, $identity)';
}

DateTime? _date(int? millis) => millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

Object? _decode(String? json) => json == null ? null : jsonDecode(json);
