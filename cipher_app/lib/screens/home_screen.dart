import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedServerIndex = 0;
  int _selectedChatIndex = -1;
  String _myUsername = '';
  bool _isReady = false;

  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isEmojiVisible = false;
  String? _selectedFileName;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  @override
  void dispose() {
    _chatController.dispose(); // ponytail: fix — prevent controller memory leak
    _scrollController.dispose();
    super.dispose();
  }

  void _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myUsername = prefs.getString('username') ?? 'Unknown';
      _isReady = true;
    });
  }

  final List<String> dummyServers = ['D', 'G', 'C'];
  
  final List<Map<String, dynamic>> allDummyChats = [
    {
      'name': 'Alice', 
      'messages': [
        {'text': "Hey Alice! How's it going?", 'isMe': true, 'file': null},
        {'text': "Hi! I'm doing great, just testing Cipher.", 'isMe': false, 'file': null},
      ]
    },
    {
      'name': 'Bob', 
      'messages': [
        {'text': "Did you see the new update?", 'isMe': false, 'file': null},
        {'text': "Yeah, the new glassmorphism UI looks insanely good.", 'isMe': true, 'file': null},
        {'text': "Agreed!", 'isMe': false, 'file': null},
      ]
    },
    {
      'name': 'Charlie', 
      'messages': [
        {'text': "Meeting at 5?", 'isMe': false, 'file': null},
        {'text': "Make it 5:30.", 'isMe': true, 'file': null},
      ]
    },
  ];

  List<Map<String, dynamic>> get _filteredChats {
    // ponytail: fix BUG-5 — only filter when username is loaded
    if (_myUsername.isEmpty) return allDummyChats;
    return allDummyChats.where((chat) => chat['name'] != _myUsername).toList();
  }

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      setState(() {
        _selectedFileName = result.files.single.name;
      });
    }
  }

  void _sendMessage() {
    if (_chatController.text.trim().isEmpty && _selectedFileName == null) return;
    
    final chats = _filteredChats;
    if (_selectedChatIndex == -1 || _selectedChatIndex >= chats.length) return;

    // We must find the actual chat object in allDummyChats so we mutate the original state
    final targetChatName = chats[_selectedChatIndex]['name'];
    final actualChatIndex = allDummyChats.indexWhere((c) => c['name'] == targetChatName);

    setState(() {
      allDummyChats[actualChatIndex]['messages'].add({
        'text': _chatController.text.trim(),
        'isMe': true,
        'file': _selectedFileName,
      });
      _chatController.clear();
      _selectedFileName = null;
      if (_isEmojiVisible) _isEmojiVisible = false;
    });

    // Auto-scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleEmojiPicker() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isEmojiVisible = !_isEmojiVisible;
    });
  }

  Widget _buildSidebar() {
    return Container(
      width: 72,
      color: const Color(0xFF1E1F22),
      child: Column(
        children: [
          const SizedBox(height: 12),
          _buildServerIcon(Icons.chat_bubble, 0, isIcon: true),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Divider(color: Colors.white12, height: 1),
          ),
          ...List.generate(dummyServers.length, (index) {
            return _buildServerIcon(dummyServers[index], index + 1);
          }),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF00A884)),
            onPressed: () => Navigator.pushNamed(context, '/qr_scanner'),
            tooltip: 'Add via QR',
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildServerIcon(dynamic content, int index, {bool isIcon = false}) {
    bool isSelected = _selectedServerIndex == index;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedServerIndex = index;
        _selectedChatIndex = -1; // ponytail: fix — reset chat when switching servers
      }),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 4,
                height: isSelected ? 40 : 0,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF5865F2) : const Color(0xFF313338),
                  borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
                  boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF5865F2).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : [],
                ),
                child: Center(
                  child: isIcon
                      ? Icon(content as IconData, color: isSelected ? Colors.white : Colors.white70)
                      : Text(
                          content as String,
                          style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatList() {
    final chats = _filteredChats;
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: Color(0xFF2B2D31),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(2, 0)),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: const Text(
              'Direct Messages',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: chats.length,
              itemBuilder: (context, index) {
                bool isSelected = _selectedChatIndex == index;
                String lastMsg = chats[index]['messages'].last['text'];
                if (lastMsg.isEmpty && chats[index]['messages'].last['file'] != null) {
                  lastMsg = '📎 ${chats[index]['messages'].last['file']}';
                }
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF404249) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF5865F2),
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(chats[index]['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text(lastMsg, style: const TextStyle(color: Colors.white54, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => setState(() => _selectedChatIndex = index),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea() {
    final chats = _filteredChats;
    if (_selectedChatIndex == -1 || _selectedChatIndex >= chats.length) {
      return Container(
        color: const Color(0xFF313338),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 80, color: Colors.white12),
              SizedBox(height: 16),
              Text('Select a chat to start messaging', style: TextStyle(color: Colors.white38, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    final currentChat = chats[_selectedChatIndex];
    String chatName = currentChat['name'];
    List<dynamic> messages = currentChat['messages'];

    return Container(
      color: const Color(0xFF313338),
      child: Column(
        children: [
          // Chat Header
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF313338),
              border: Border(bottom: BorderSide(color: Colors.black12, width: 1)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Row(
              children: [
                const Icon(Icons.alternate_email, color: Colors.grey),
                const SizedBox(width: 8),
                Text(chatName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.call, color: Colors.white54),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Calling $chatName...'))),
                  tooltip: 'Voice Call',
                ),
                IconButton(
                  icon: const Icon(Icons.videocam, color: Colors.white54),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Starting video call with $chatName...'))),
                  tooltip: 'Video Call',
                ),
              ],
            ),
          ),
          // Chat Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(24),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                return _buildMessageBubble(msg['text'], isMe: msg['isMe'], fileName: msg['file']);
              },
            ),
          ),
          // File Preview Pill
          if (_selectedFileName != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1F22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file, color: Color(0xFF5865F2), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _selectedFileName!,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => setState(() => _selectedFileName = null),
                    child: const Icon(Icons.close, color: Colors.white54, size: 18),
                  )
                ],
              ),
            ),
          // Chat Input Area
          Container(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20, top: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Colors.white54),
                  onPressed: _pickFile,
                  tooltip: 'Share File',
                ),
                IconButton(
                  icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white54),
                  onPressed: _toggleEmojiPicker,
                  tooltip: 'Emojis',
                ),
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    onTap: () {
                      if (_isEmojiVisible) setState(() => _isEmojiVisible = false);
                    },
                    onSubmitted: (_) => _sendMessage(),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Message @$chatName',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF383A40),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      suffixIcon: GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF5865F2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.send, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Emoji Picker Drawer
          if (_isEmojiVisible)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) {
                  _chatController.text = _chatController.text + emoji.emoji;
                },
                config: const Config(
                  emojiViewConfig: EmojiViewConfig(
                    backgroundColor: Color(0xFF2B2D31),
                    columns: 10,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    backgroundColor: Color(0xFF1E1F22),
                    indicatorColor: Color(0xFF5865F2),
                    iconColorSelected: Color(0xFF5865F2),
                  ),
                  bottomActionBarConfig: BottomActionBarConfig(
                    backgroundColor: Color(0xFF1E1F22),
                    buttonColor: Color(0xFF1E1F22),
                    buttonIconColor: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String text, {required bool isMe, String? fileName}) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isMe) 
            IconButton(
              icon: const Icon(Icons.shortcut, color: Colors.white38, size: 20),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Forwarding message...'))),
              tooltip: 'Forward',
            ),
          Flexible(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: isMe 
                  ? const LinearGradient(colors: [Color(0xFF00A884), Color(0xFF00C698)])
                  : const LinearGradient(colors: [Color(0xFF2B2D31), Color(0xFF2B2D31)]),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (fileName != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.insert_drive_file, color: Colors.white70, size: 18),
                          const SizedBox(width: 6),
                          Text(fileName, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  if (text.isNotEmpty)
                    Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
                ],
              ),
            ),
          ),
          if (!isMe)
            IconButton(
              icon: const Icon(Icons.shortcut, color: Colors.white38, size: 20),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Forwarding message...'))),
              tooltip: 'Forward',
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(
        backgroundColor: Color(0xFF1E1F22),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF5865F2))),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(), 
          if (MediaQuery.of(context).size.width > 600) _buildChatList(),
          Expanded(child: _buildChatArea()),
        ],
      ),
    );
  }
}
