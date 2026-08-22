import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import 'voice_screen.dart';

class ChatScreen extends StatefulWidget {
  final String? sessionId;
  const ChatScreen({super.key, this.sessionId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    if (widget.sessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<ChatProvider>().loadSessionFromServer(widget.sessionId!);
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      try {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } catch (e) {
        // Bỏ qua lỗi tính toán vị trí cuộn trên Web
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(),
      endDrawer: _buildHistoryDrawer(),
      body: Listener(
        onPointerHover: (_) => context.read<ChatProvider>().clearBadge(),
        onPointerDown: (_) => context.read<ChatProvider>().clearBadge(),
        child: Column(
          children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, child) {
                // Auto scroll when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                
                return SelectionArea(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    itemCount: chatProvider.messages.length + (chatProvider.isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == chatProvider.messages.length && chatProvider.isTyping) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 8),
                                Text("AI đang suy nghĩ...", style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                              ],
                            ),
                          ),
                        );
                      }
                      
                      final msg = chatProvider.messages[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: _buildMessageItem(msg),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          _buildSuggestedPrompts(),
          _buildInputBar(context),
        ],
      ),
    ),
  );
  }

  Widget _buildMessageItem(ChatMessage msg) {
    if (msg.isUser) {
      if (msg.isImage) {
        return _buildUserImageMessage(msg);
      } else {
        return _buildUserTextMessage(msg.text);
      }
    } else {
      if (msg.isAnalysis) {
        return _buildAiAnalysisMessage(msg);
      } else {
        return _buildAiTextMessage(msg.text);
      }
    }
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: const Icon(Icons.person, color: Colors.blue),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TaxMate AI',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          Text(
            'Trợ lý Thuế AI',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: OutlinedButton.icon(
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
            icon: const Icon(Icons.history, size: 16, color: Colors.black54),
            label: const Text('History', style: TextStyle(color: Colors.black54)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Lịch sử trò chuyện',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, provider, _) {
                  if (provider.history.isEmpty) {
                    return const Center(child: Text('Chưa có lịch sử trò chuyện', style: TextStyle(color: Colors.grey)));
                  }
                  return ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: provider.history.length,
                    itemBuilder: (context, index) {
                      final session = provider.history[index];
                      // Just a simple format for time
                      final timeStr = '${session.updatedAt.day}/${session.updatedAt.month} ${session.updatedAt.hour}:${session.updatedAt.minute.toString().padLeft(2, '0')}';
                      return _buildHistoryItem(
                        session.title, 
                        timeStr, 
                        false, // isSelected can be improved later
                        () {
                          Navigator.pop(context);
                          provider.loadSession(session.sessionId);
                        }
                      );
                    },
                  );
                }
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // Close drawer
                  context.read<ChatProvider>().startNewChat();
                },
                icon: const Icon(Icons.add),
                label: const Text('Cuộc trò chuyện mới'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(String title, String time, bool isSelected, VoidCallback onTap) {
    return ListTile(
      leading: const Icon(Icons.chat_bubble_outline, size: 20),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.black87,
        ),
      ),
      subtitle: Text(
        time,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      onTap: onTap,
    );
  }

  Widget _buildUserImageMessage(ChatMessage msg) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 40),
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              height: 120,
              width: 250,
              color: Colors.white,
              child: msg.imageBytes != null
                  ? Image.memory(msg.imageBytes!, fit: BoxFit.cover)
                  : const Center(child: Text("Hình ảnh")),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '[Ảnh đã tải]',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      minimumSize: const Size(0, 24),
                    ),
                    child: const Text('PHÂN TÍCH...', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAiAnalysisMessage(ChatMessage msg) {
    final data = msg.analysisData ?? {};
    final steps = (data['steps'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: const Icon(Icons.smart_toy, size: 14, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.description, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text('AI PHÂN TÍCH HÓA ĐƠN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  GestureDetector(
                    onTap: () {
                      final allText = [
                        'AI PHÂN TÍCH HÓA ĐƠN',
                        'Ngày: ${data['date'] ?? ''}',
                        'Bên bán: ${data['seller'] ?? ''}',
                        'Tổng cộng: ${data['total'] ?? ''}',
                        'Thuế: ${data['tax'] ?? ''}',
                        'Bước tiếp theo:',
                        ...steps
                      ].join('. ');
                      context.read<ChatProvider>().speak(allText);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.volume_up, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text('ĐỌC LẠI', style: TextStyle(color: Colors.white, fontSize: 10)),
                        ],
                      ),
                    ),
                  )
                ],
                ),
                const SizedBox(height: 12),
                _buildAnalysisRow('📅', 'Ngày:', data['date'] ?? ''),
                _buildAnalysisRow('🏢', 'Bên bán:', data['seller'] ?? ''),
                _buildAnalysisRow('💰', 'Tổng cộng:', data['total'] ?? ''),
                _buildAnalysisRow('🧾', 'Thuế GTGT:', data['tax'] ?? ''),
                const SizedBox(height: 16),
                const Text('📌 BƯỚC TIẾP THEO CẦN LÀM:', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                for (var step in steps) _buildChecklistItem(step),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      child: const Text('Nộp tờ khai'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      child: const Text('Đặt lịch nhắc'),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisRow(String emoji, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 4),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2.0),
            child: Icon(Icons.check_box_outline_blank, color: Colors.white70, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildUserTextMessage(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 40),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(text, style: const TextStyle(color: Colors.black87)),
      ),
    );
  }

  Widget _buildAiTextMessage(String text) {
    final cleanText = text.replaceAll('**', '');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: const Icon(Icons.smart_toy, size: 14, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cleanText, style: const TextStyle(color: Colors.white, height: 1.4)),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () {
                      context.read<ChatProvider>().speak(cleanText);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.volume_up, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text('Nghe lại', style: TextStyle(color: Colors.white, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _buildSuggestedPrompts() {
    return Container(
      padding: const EdgeInsets.only(bottom: 12, left: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildPromptChip('Kiểm tra thuế TNCN'),
            const SizedBox(width: 8),
            _buildPromptChip('Tính thuế hoàn trả'),
            const SizedBox(width: 8),
            _buildPromptChip('Tải mẫu tờ khai'),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptChip(String label) {
    return GestureDetector(
      onTap: () {
        context.read<ChatProvider>().sendMessage(label);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined),
              color: Colors.grey.shade600,
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (BuildContext bottomSheetContext) {
                    return SafeArea(
                      child: Wrap(
                        children: <Widget>[
                          ListTile(
                            leading: const Icon(Icons.camera_alt),
                            title: const Text('Chụp ảnh trực tiếp'),
                            onTap: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(source: ImageSource.camera);
                              
                              if (bottomSheetContext.mounted) {
                                Navigator.of(bottomSheetContext).pop();
                              }
                              
                              if (pickedFile != null) {
                                final bytes = await pickedFile.readAsBytes();
                                if (context.mounted) {
                                  context.read<ChatProvider>().sendImage(bytes, pickedFile.name);
                                }
                              }
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.photo_library),
                            title: const Text('Chọn ảnh từ thư viện'),
                            onTap: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                              
                              if (bottomSheetContext.mounted) {
                                Navigator.of(bottomSheetContext).pop();
                              }
                              
                              if (pickedFile != null) {
                                final bytes = await pickedFile.readAsBytes();
                                if (context.mounted) {
                                  context.read<ChatProvider>().sendImage(bytes, pickedFile.name);
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  }
                );
              },
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _textController,
                  onSubmitted: (value) {
                    context.read<ChatProvider>().sendMessage(value);
                    _textController.clear();
                  },
                  decoration: InputDecoration(
                    hintText: 'Gõ câu hỏi của bạn...',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send, size: 20),
                      onPressed: () {
                        context.read<ChatProvider>().sendMessage(_textController.text);
                        _textController.clear();
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Consumer<ChatProvider>(
              builder: (context, chatProvider, child) {
                return IconButton(
                  icon: Icon(
                    chatProvider.isListening ? Icons.mic : Icons.mic_none, 
                  ),
                  color: chatProvider.isListening ? Colors.red.shade700 : Colors.green.shade700,
                  style: IconButton.styleFrom(
                    backgroundColor: chatProvider.isListening ? Colors.red.shade100 : Colors.green.shade100,
                  ),
                  onPressed: () {
                    // Open the voice screen overlay
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const VoiceScreen(),
                    );
                  },
                );
              }
            ),
          ],
        ),
      ),
    );
  }
}
