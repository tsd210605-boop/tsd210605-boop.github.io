import 'dart:typed_data';
import 'dart:convert';

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  
  // For image uploads
  final bool isImage;
  final String? imagePath;
  final Uint8List? imageBytes;
  
  // For AI analysis results
  final bool isAnalysis;
  final Map<String, dynamic>? analysisData;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    this.isImage = false,
    this.imagePath,
    this.imageBytes,
    this.isAnalysis = false,
    this.analysisData,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isUser': isUser,
      'isImage': isImage,
      'imagePath': imagePath,
      'imageBytes': imageBytes != null ? base64Encode(imageBytes!) : null,
      'isAnalysis': isAnalysis,
      'analysisData': analysisData,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      text: json['text'],
      isUser: json['isUser'],
      isImage: json['isImage'] ?? false,
      imagePath: json['imagePath'],
      imageBytes: json['imageBytes'] != null ? base64Decode(json['imageBytes']) : null,
      isAnalysis: json['isAnalysis'] ?? false,
      analysisData: json['analysisData'],
    );
  }
}
