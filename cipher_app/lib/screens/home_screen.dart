import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedServerIndex = 0;
  int _selectedChatIndex = -1;
  String _myUsername = '';

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  void _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myUsername = prefs.getString('username') ?? 'Unknown';
    });
  }

  final List<String> dummyServers = ['D', 'G', 'C'];
  
  // Dynamic dummy data structure with full message history
  final List<Map<String, dynamic>> allDummyChats = [
    {
      'name': 'Alice', 
      'messages': [
        {'text': "Hey Alice! How's it going?", 'isMe': true},
        {'text': "Hi! I'm doing great, just testing Cipher.", 'isMe': false},
      ]
    },
    {
      'name': 'Bob', 
      'messages': [
        {'text': "Did you see the new update?", 'isMe': false},
        {'text': "Yeah, the new glassmorphism UI looks insanely good.", 'isMe': true},
        {'text': "Agreed!", 'isMe': false},
      ]
    },
    {
      'name': 'Charlie', 
      'messages': [
        {'text': "Meeting at 5?", 'isMe': false},
        {'text': "Make it 5:30.", 'isMe': true},
      ]
    },
  ];

  // Prevent talking to yourself by filtering out your own username
  List<Map<String, dynamic>> get _filteredChats {
    return allDummyChats.where((chat) => chat['name'] != _myUsername).toList();
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
      onTap: () => setState(() => _selectedServerIndex = index),
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
                const Icon(Icons.call, color: Colors.white54),
                const SizedBox(width: 16),
                const Icon(Icons.videocam, color: Colors.white54),
              ],
            ),
          ),
          // Chat Messages
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                return _buildMessageBubble(msg['text'], isMe: msg['isMe']);
              },
            ),
          ),
          // Chat Input Area
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Colors.white54),
                  onPressed: () {},
                  tooltip: 'Share File',
                ),
                IconButton(
                  icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white54),
                  onPressed: () {},
                  tooltip: 'Emojis',
                ),
                Expanded(
                  child: TextField(
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
                      suffixIcon: Container(
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String text, {required bool isMe}) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isMe) 
            IconButton(
              icon: const Icon(Icons.shortcut, color: Colors.white38, size: 20),
              onPressed: () {},
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
              child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
            ),
          ),
          if (!isMe)
            IconButton(
              icon: const Icon(Icons.shortcut, color: Colors.white38, size: 20),
              onPressed: () {},
              tooltip: 'Forward',
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
