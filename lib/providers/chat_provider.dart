import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;
import 'package:flutter_app_badger/flutter_app_badger.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

class ChatProvider extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  String? _sessionId;
  final String _baseUrl = 'https://aithue.thinkdiff.us/api/v1/chat';

  // Voice State
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _notificationPlayer = AudioPlayer();
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

  void clearBadge() {
    if (kIsWeb) {
      html.document.title = 'TaxMate AI';
      _updateFavicon('favicon.png', 'image/png');
    } else {
      FlutterAppBadger.removeBadge();
    }
  }

  void setBadge() {
    if (kIsWeb) {
      html.document.title = '(1) Tin nhắn mới - TaxMate AI';
      final String svgRedDot = 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMDAgMTAwIj48Y2lyY2xlIGN4PSI1MCIgY3k9IjUwIiByPSI1MCIgZmlsbD0iI2ZmMDAwMCIvPjx0ZXh0IHg9IjUwIiB5PSI3MCIgZm9udC1mYW1pbHk9IkFyaWFsIiBmb250LXNpemU9IjYwIiBmb250LXdlaWdodD0iYm9sZCIgZmlsbD0id2hpdGUiIHRleHQtYW5jaG9yPSJtaWRkbGUiPjE8L3RleHQ+PC9zdmc+';
      _updateFavicon(svgRedDot, 'image/svg+xml');
    } else {
      try {
        FlutterAppBadger.updateBadgeCount(1);
      } catch (e) {
        print("Badger error: $e");
      }
    }
    _playNotificationSound();
  }

  void _playNotificationSound() async {
    try {
      await _notificationPlayer.play(AssetSource('sounds/notification.mp3'));
    } catch (e) {
      print("Cannot play notification: $e");
    }
  }

  void _updateFavicon(String url, String type) {
    // Xóa toàn bộ các thẻ favicon cũ để trình duyệt không bị cache hoặc nhầm lẫn
    var oldLinks = html.document.querySelectorAll("link[rel*='icon']");
    for (var oldLink in oldLinks) {
      oldLink.remove();
    }
    // Tạo mới hoàn toàn thẻ favicon và nhúng vào head
    var newLink = html.LinkElement()
      ..rel = 'icon'
      ..type = type
      ..href = url;
    html.document.head?.append(newLink);
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
    _updateUrlWithSession(id);
    notifyListeners();
  }

  void startNewChat() async {
    await saveHistory();
    _messages.clear();
    _sessionId = null;
    if (kIsWeb) {
      html.window.history.pushState(null, 'TaxMate AI', '/#/');
    }
    notifyListeners();
  }

  void _updateUrlWithSession(String sessionId) {
    if (kIsWeb) {
      html.window.history.pushState(null, 'TaxMate AI', '/#/chat/$sessionId');
    }
  }

  Future<void> loadSessionFromServer(String id) async {
    _sessionId = id;
    _messages.clear();
    notifyListeners();
    
    try {
      final response = await http.get(Uri.parse('$_baseUrl/sessions/$id'));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        // Đôi khi backend lưu history dưới dạng chuỗi JSON trong MySQL, ta cần parse lại
        var historyData = data['history'];
        if (historyData is String) {
          try {
            historyData = jsonDecode(historyData);
          } catch (_) {}
        }
        
        final historyList = historyData as List?;
        
        if (historyList != null && historyList.isNotEmpty) {
          for (var item in historyList) {
            final role = item['role'];
            final content = item['content'] ?? '';
            final isUser = role == 'user';
            
            // Nếu content rỗng hoặc là ảnh, tạo bong bóng ảnh (tạm mô phỏng)
            final isImage = isUser && content.contains('[Uploaded Image]');
            
            // Chỉ những tin nhắn AI có chứa "AI PHÂN TÍCH HÓA ĐƠN" mới được coi là kết quả phân tích
            final isAnalysisMsg = !isUser && data.containsKey('filled_slots') && content.contains('AI PHÂN TÍCH HÓA ĐƠN');
            
            // Xử lý dữ liệu hóa đơn (nếu có) để truyền vào giao diện
            Map<String, dynamic>? analysisData;
            if (isAnalysisMsg) {
              final invoiceData = data['filled_slots']['invoice_data'];
              if (invoiceData != null) {
                analysisData = {
                  'date': invoiceData['ngay_lap_hoa_don'] ?? invoiceData['ngay'] ?? '',
                  'seller': invoiceData['ten_ben_ban'] ?? invoiceData['ben_ban'] ?? '',
                  'total': invoiceData['tong_tien_thanh_toan'] ?? invoiceData['tong_cong'] ?? '',
                  'tax': invoiceData['tien_thue_gtgt'] ?? invoiceData['thue_gtgt'] ?? '',
                  'steps': invoiceData['buoc_tiep_theo'] ?? ['Kiểm tra lại số liệu trước khi kê khai'],
                };
              } else {
                analysisData = data['filled_slots'];
              }
            }
            
            _messages.add(ChatMessage(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              text: isImage ? 'Ảnh đã tải lên' : content,
              isUser: isUser,
              isImage: isImage,
              isAnalysis: isAnalysisMsg,
              analysisData: analysisData,
            ));
          }
        } else {
          // Lịch sử trống hoặc null
          _messages.add(ChatMessage(
            id: 'empty',
            text: 'Server trả về lịch sử trống cho phiên này.',
            isUser: false,
          ));
        }
        _updateUrlWithSession(id);
      } else {
        _messages.add(ChatMessage(
          id: 'error',
          text: 'Không thể tải lịch sử (Lỗi ${response.statusCode}): ${response.body}',
          isUser: false,
        ));
      }
    } catch (e) {
      print("Lỗi tải lịch sử từ Server: $e");
      _messages.add(ChatMessage(
        id: 'error_exception',
        text: 'Đã xảy ra lỗi kết nối hoặc xử lý dữ liệu: $e',
        isUser: false,
      ));
    }
    await saveHistory(); // Đảm bảo lưu vào Sidebar History ở Local
    notifyListeners();
  }

  Future<void> _ensureSessionId() async {
    if (_sessionId == null || _sessionId!.startsWith('local_')) {
      final sessionRes = await http.post(
        Uri.parse('$_baseUrl/sessions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'workflow_code': 'PHAN_TICH_HOA_DON'}),
      ).timeout(const Duration(seconds: 10));
      
      if (sessionRes.statusCode == 200) {
        final sData = jsonDecode(utf8.decode(sessionRes.bodyBytes));
        
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
        _updateUrlWithSession(_sessionId!);
        saveHistory();
      } else {
        throw Exception("Không thể tạo Session");
      }
    }
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
      await _ensureSessionId();

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
        setBadge();
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
      await _ensureSessionId();

      // Gọi /chat/ thay vì /ask hoặc gửi kèm session_id nếu API yêu cầu
      // Tạm thời mình gửi kèm session_id vào /ask (hoặc tuỳ Server của bạn)
      final response = await http.post(
        Uri.parse('$_baseUrl/ask'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': _sessionId, // Thêm session_id để Server lưu lịch sử
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
        setBadge();
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
