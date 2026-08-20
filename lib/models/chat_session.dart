import 'chat_message.dart';

class ChatSession {
  final String sessionId;
  final String title;
  final List<ChatMessage> messages;
  final DateTime updatedAt;

  ChatSession({
    required this.sessionId,
    required this.title,
    required this.messages,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'title': title,
      'messages': messages.map((m) => m.toJson()).toList(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    var list = json['messages'] as List? ?? [];
    List<ChatMessage> msgs = list.map((i) => ChatMessage.fromJson(i as Map<String, dynamic>)).toList();

    return ChatSession(
      sessionId: json['sessionId'],
      title: json['title'],
      messages: msgs,
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}
