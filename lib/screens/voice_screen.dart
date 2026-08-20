import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    // Automatically start listening when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ChatProvider>();
      if (!provider.isListening) {
        provider.startListening();
        _animationController.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        final isListening = chatProvider.isListening;
        final userSpokenText = chatProvider.spokenText;

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E4670), // Dark blue at top
              Color(0xFF3EA38A), // Green in middle
              Color(0xFF133658), // Dark blue at bottom
            ],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // User text bubble (hiển thị khi đã có chữ)
              if (userSpokenText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40.0, right: 20, left: 60),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      child: Text(
                        userSpokenText,
                        style: const TextStyle(color: Colors.black87, fontSize: 16, height: 1.4),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 100),

              const Spacer(flex: 2),

              // Sound Wave Animation
              if (isListening) _buildSoundWave() else const SizedBox(height: 80),

              const Spacer(flex: 1),

              // AI Text Bubble (Ẩn đi vì đang tập trung thu âm User)
              const SizedBox(height: 100),

              // Bottom Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.mic, color: Colors.white70, size: 16),
                        SizedBox(width: 8),
                        Text('GIỮ ĐỂ NÓI', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                        SizedBox(width: 16),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: 0.3,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 16),
                        Icon(Icons.volume_up, color: Colors.white, size: 24),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildBottomButton(Icons.close, 'Đóng', () => Navigator.pop(context)),
                        
                        // Main Mic Button
                        GestureDetector(
                          onTap: () {
                            if (isListening) {
                              chatProvider.stopListening();
                              _animationController.stop();
                              Navigator.pop(context); // Close after speaking
                            } else {
                              chatProvider.startListening();
                              _animationController.repeat(reverse: true);
                            }
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: isListening ? Colors.redAccent : Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isListening ? Icons.stop : Icons.mic, 
                                  color: isListening ? Colors.white : const Color(0xFF1E4670), 
                                  size: 32
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isListening ? "ĐANG LẮNG NGHE..." : "CHẠM ĐỂ NÓI",
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        
                        _buildBottomButton(Icons.keyboard, 'Gõ', () => Navigator.pop(context)),
                      ],
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
    },
  );
}

  Widget _buildSoundWave() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(11, (index) {
            // Create a fake wave pattern based on index and animation
            double height = 20.0;
            if (index == 5) height = 80.0; // Center is tallest
            else if (index == 4 || index == 6) height = 60.0;
            else if (index == 3 || index == 7) height = 40.0;
            
            // Add some animation variance
            height = height + (_animationController.value * (index % 2 == 0 ? 10 : -10));
            
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6,
              height: height,
              decoration: BoxDecoration(
                color: index == 5 || index == 4 || index == 6 ? Colors.white : Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildBottomButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
