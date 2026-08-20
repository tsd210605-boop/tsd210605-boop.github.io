import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

class ChatProvider extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  String? _sessionId;
  final String _baseUrl = 'https://aithue.thinkdiff.us/api/v1/chat';

  // Voice State
  final AudioPlayer _audioPlayer = AudioPlayer();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;
  String _spokenText = '';
  List<ChatSession> _history = [];

  List<ChatMessage> get messages => _messages;
  bool get isTyping => _isTyping;
  bool get isListening => _isListening;
  String get spokenText => _spokenText;
  List<ChatSession> get history => _history;

  ChatProvider() {
    _initStt();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('chat_history');
    if (historyJson != null) {
      final List decoded = jsonDecode(historyJson);
      _history = decoded.map((i) => ChatSession.fromJson(i as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  Future<void> saveHistory() async {
    if (_sessionId == null && _messages.isEmpty) return;

    final currentSessionId = _sessionId ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
    if (_sessionId == null) _sessionId = currentSessionId;

    final existingIndex = _history.indexWhere((s) => s.sessionId == currentSessionId);
    
    // Find first user message for title
    final firstUserMsgIdx = _messages.indexWhere((m) => m.isUser);
    String title = 'Cuộc trò chuyện mới';
    if (firstUserMsgIdx >= 0) {
      title = _messages[firstUserMsgIdx].text;
      if (title.length > 30) title = '${title.substring(0, 30)}...';
    }

    final session = ChatSession(
      sessionId: currentSessionId,
      title: title,
      messages: List.from(_messages),
      updatedAt: DateTime.now(),
    );

    if (existingIndex >= 0) {
      _history[existingIndex] = session;
    } else {
      _history.insert(0, session);
    }

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_history.map((s) => s.toJson()).toList());
    await prefs.setString('chat_history', encoded);
    
    notifyListeners();
  }

  void loadSession(String id) async {
    await saveHistory();
    final session = _history.firstWhere((s) => s.sessionId == id);
    _messages.clear();
    _messages.addAll(session.messages);
    _sessionId = session.sessionId;
    notifyListeners();
  }

  void startNewChat() async {
    await saveHistory();
    _messages.clear();
    _sessionId = null;
    notifyListeners();
  }

  void _initStt() async {
    await _speechToText.initialize();
  }

  void speak(String text) async {
    // Dừng âm thanh cũ nếu đang phát
    await _audioPlayer.stop();
    
    // Mã hóa chuỗi tiếng Việt thành định dạng an toàn cho URL
    String encodedText = Uri.encodeComponent(text);
    
    // Ghép vào URL của Server (_baseUrl đã chứa /api/v1/chat)
    String url = "$_baseUrl/tts?text=$encodedText";
    
    // Bật loa phát âm thanh trực tiếp từ URL
    await _audioPlayer.play(UrlSource(url));
  }

  void stopSpeaking() async {
    await _audioPlayer.stop();
  }

  void startListening() async {
    if (!_isListening) {
      print("Đang khởi tạo Mic...");
      try {
        bool available = await _speechToText.initialize(
          onStatus: (val) => print('onStatus: $val'),
          onError: (val) => print('onError: $val'),
          debugLogging: true,
        );
        print("Trạng thái Mic: $available");
        
        if (available) {
          _isListening = true;
          _spokenText = '';
          notifyListeners();
          
          print("Bắt đầu nghe...");
          _speechToText.listen(
            onResult: (val) {
              print("Kết quả nghe: ${val.recognizedWords}");
              _spokenText = val.recognizedWords;
              notifyListeners();
            },
            localeId: 'vi-VN', // Đổi thử sang vi-VN thay vì vi_VN
          );
        } else {
          print("Mic không available.");
        }
      } catch (e) {
        print("Lỗi khởi tạo Mic: $e");
      }
    }
  }

  void stopListening() {
    if (_isListening) {
      _speechToText.stop();
      _isListening = false;
      notifyListeners();
      
      if (_spokenText.trim().isNotEmpty) {
        sendMessage(_spokenText);
      }
      _spokenText = '';
    }
  }

  void sendMessage(String text) {
    if (text.trim().isEmpty) return;

    // Add user message
    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
    );
    _messages.add(userMsg);
    notifyListeners();
    saveHistory();

    _callAIApi(text);
  }

  void sendImage(Uint8List imageBytes, String filename) async {
    // Add user image message
    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: 'Ảnh đã tải lên',
      isUser: true,
      isImage: true,
      imageBytes: imageBytes,
    );
    _messages.add(userMsg);
    
    _isTyping = true;
    notifyListeners();
    saveHistory();

    try {
      // 1. Nếu chưa có session_id thật từ server thì gọi /sessions để khởi tạo
      if (_sessionId == null || _sessionId!.startsWith('local_')) {
        final sessionRes = await http.post(
          Uri.parse('$_baseUrl/sessions'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'workflow_code': 'PHAN_TICH_HOA_DON'}),
        ).timeout(const Duration(seconds: 10));
        
        if (sessionRes.statusCode == 200) {
          final sData = jsonDecode(utf8.decode(sessionRes.bodyBytes));
          
          // Nếu trước đó đang dùng local ID, cập nhật lại lịch sử với ID thật
          if (_sessionId != null && _sessionId!.startsWith('local_')) {
            final oldIdx = _history.indexWhere((s) => s.sessionId == _sessionId);
            if (oldIdx >= 0) {
              final oldSession = _history[oldIdx];
              _history[oldIdx] = ChatSession(
                sessionId: sData['session_id'],
                title: oldSession.title,
                messages: oldSession.messages,
                updatedAt: oldSession.updatedAt,
              );
            }
          }
          
          _sessionId = sData['session_id'];
          saveHistory(); // Lưu lại ID mới
        } else {
          throw Exception("Không thể tạo Session");
        }
      }

      // 2. Gửi file ảnh dạng Base64 vào API /vision-chat
      final base64Image = base64Encode(imageBytes);
      
      final response = await http.post(
        Uri.parse('$_baseUrl/vision-chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': _sessionId,
          'user_message': '', // Truyền chuỗi rỗng để Server không bị lỗi None.strip()
          'image_base64': base64Image,
        }),
      ).timeout(const Duration(minutes: 5));

      _isTyping = false;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        // Trích xuất kết quả từ API
        final reply = data['ai_response'] ?? data['reply'] ?? data['message'] ?? data['response'] ?? data['answer'] ?? data['text'] ?? response.body; 
        
        final aiMsg = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: reply,
          isUser: false,
          isAnalysis: data.containsKey('date') || data.containsKey('steps'), // Fallback if server returns structured data like the mock did
          analysisData: data,
        );
        _messages.add(aiMsg);
      } else {
        final aiMsg = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: 'Lỗi upload ảnh: ${response.statusCode}',
          isUser: false,
        );
        _messages.add(aiMsg);
      }
    } catch (e) {
      _isTyping = false;
      final aiMsg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: 'Không thể tải ảnh lên Server AI ($e).',
        isUser: false,
      );
      _messages.add(aiMsg);
    }
    
    notifyListeners();
    saveHistory();
  }

  void _callAIApi(String userText) async {
    _isTyping = true;
    notifyListeners();

    try {
      // Đổi sang gọi API /ask (Hỏi đáp tự do RAG) thay vì bị kẹt trong luồng Khai Thuế
      final response = await http.post(
        Uri.parse('$_baseUrl/ask'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'question': userText
        }),
      ).timeout(const Duration(minutes: 5));

      _isTyping = false;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        // Trích xuất kết quả từ API /ask
        final reply = data['answer'] ?? data['ai_response'] ?? data['reply'] ?? data['response'] ?? response.body; 
        
        final aiMsg = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: reply,
          isUser: false,
        );
        _messages.add(aiMsg);
      } else {
        final aiMsg = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: 'Lỗi máy chủ: ${response.statusCode}',
          isUser: false,
        );
        _messages.add(aiMsg);
      }
    } catch (e) {
      _isTyping = false;
      final aiMsg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: 'Không thể kết nối đến Server AI. Vui lòng thử lại sau. ($e)',
        isUser: false,
      );
      _messages.add(aiMsg);
    }

    notifyListeners();
    saveHistory();
  }

  // Pre-populate with the initial design data
  void loadInitialData() {
    _messages.clear();
    _sessionId = null; // Reset session on load

    
    _messages.add(ChatMessage(
      id: '1',
      text: 'Ảnh hóa đơn',
      isUser: true,
      isImage: true,
      imagePath: 'mock_invoice.jpg',
    ));

    _messages.add(ChatMessage(
      id: '2',
      text: '',
      isUser: false,
      isAnalysis: true,
      analysisData: {
        'date': '15/07/2026',
        'seller': 'CTY ABC (0123456789)',
        'total': '15.000.000đ',
        'tax': '1.500.000đ',
        'steps': [
          '1. Kê khai thuế GTGT quý 3/2026',
          '2. Bổ sung chứng từ kèm theo',
          '3. Hạn nộp: 31/10/2026'
        ]
      },
    ));

    _messages.add(ChatMessage(
      id: '3',
      text: 'Vậy, thuế TNCN mình cần đóng bao nhiêu?',
      isUser: true,
    ));

    _messages.add(ChatMessage(
      id: '4',
      text: 'Dựa trên thu nhập và các khoản giảm trừ của bạn, thuế TNCN ước tính của năm 2026 là 12.500.000đ. Tôi đã lưu kết quả.',
      isUser: false,
    ));

    notifyListeners();
  }
}
