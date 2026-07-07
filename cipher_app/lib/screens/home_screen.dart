import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../services/socket_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────
  int _selectedServerIndex = 0;
  int _selectedChatIndex = -1;
  String _myUsername = '';
  bool _isReady = false;
  bool _isDarkMode = true;

  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isEmojiVisible = false;
  String? _selectedFileName;

  // ── Live data from socket ──────────────────────────────────────────
  final SocketService _socket = SocketService();
  StreamSubscription? _socketSub;
  Set<String> _onlineUsers = {};
  Map<String, bool> _typingStatus = {}; // username -> isTyping
  Timer? _typingDebounce;
  bool _iAmTyping = false;

  // ── Typing animation ──────────────────────────────────────────────
  late AnimationController _dotController;

  // ── Chat data ─────────────────────────────────────────────────────
  final List<String> dummyServers = ['D', 'G', 'C'];

  final List<Map<String, dynamic>> allDummyChats = [
    {
      'name': 'Alice',
      'messages': [
        {'text': "Hey Alice! How's it going?", 'isMe': true, 'file': null, 'read': true, 'reactions': <String>[], 'id': 'm1'},
        {'text': "Hi! I'm doing great, just testing Cipher.", 'isMe': false, 'file': null, 'read': true, 'reactions': <String>[], 'id': 'm2'},
      ]
    },
    {
      'name': 'Bob',
      'messages': [
        {'text': "Did you see the new update?", 'isMe': false, 'file': null, 'read': true, 'reactions': <String>[], 'id': 'm3'},
        {'text': "Yeah, the new glassmorphism UI looks insanely good.", 'isMe': true, 'file': null, 'read': false, 'reactions': <String>[], 'id': 'm4'},
        {'text': "Agreed!", 'isMe': false, 'file': null, 'read': true, 'reactions': <String>[], 'id': 'm5'},
      ]
    },
    {
      'name': 'Charlie',
      'messages': [
        {'text': "Meeting at 5?", 'isMe': false, 'file': null, 'read': true, 'reactions': <String>[], 'id': 'm6'},
        {'text': "Make it 5:30.", 'isMe': true, 'file': null, 'read': false, 'reactions': <String>[], 'id': 'm7'},
      ]
    },
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _chatController.addListener(_onTextChanged);
    _loadUsernameAndConnect();
  }

  @override
  void dispose() {
    _dotController.dispose();
    _socketSub?.cancel();
    _socket.disconnect();
    _chatController.removeListener(_onTextChanged);
    _chatController.dispose();
    _scrollController.dispose();
    _typingDebounce?.cancel();
    super.dispose();
  }

  // ── Init ───────────────────────────────────────────────────────────
  void _loadUsernameAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'Unknown';
    setState(() {
      _myUsername = username;
      _isReady = true;
    });
    await _socket.connect(username);
    _socketSub = _socket.messageStream.listen(_onSocketMessage);
  }

  void _onSocketMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type'];
    if (type == 'user_list') {
      final users = (msg['users'] as List).map((u) => u['username'] as String).toSet();
      setState(() => _onlineUsers = users);
    } else if (type == 'typing') {
      final sender = msg['sender'] as String?;
      final isTyping = msg['is_typing'] as bool? ?? false;
      if (sender != null) setState(() => _typingStatus[sender] = isTyping);
    } else if (type == 'private_message') {
      final sender = msg['sender'] as String?;
      final content = msg['content'] as String? ?? '';
      if (sender != null) {
        final chatIdx = allDummyChats.indexWhere((c) => c['name'] == sender);
        if (chatIdx != -1) {
          setState(() {
            allDummyChats[chatIdx]['messages'].add({
              'text': content,
              'isMe': false,
              'file': msg['filename'],
              'read': false,
              'reactions': <String>[],
              'id': 'r_${DateTime.now().millisecondsSinceEpoch}',
            });
          });
          _scrollToBottom();
        }
      }
    } else if (type == 'read_receipt') {
      final from = msg['from'] as String?;
      final msgId = msg['message_id'] as String?;
      if (from != null && msgId != null) {
        setState(() {
          for (final chat in allDummyChats) {
            for (final m in chat['messages'] as List) {
              if (m['id'] == msgId) m['read'] = true;
            }
          }
        });
      }
    } else if (type == 'delete_message') {
      final msgId = msg['message_id'] as String?;
      if (msgId != null) {
        setState(() {
          for (final chat in allDummyChats) {
            (chat['messages'] as List).removeWhere((m) => m['id'] == msgId);
          }
        });
      }
    } else if (type == 'reaction') {
      final msgId = msg['message_id'] as String?;
      final emoji = msg['emoji'] as String?;
      if (msgId != null && emoji != null) {
        setState(() {
          for (final chat in allDummyChats) {
            for (final m in (chat['messages'] as List)) {
              if (m['id'] == msgId) {
                final reactions = m['reactions'] as List<String>;
                if (reactions.contains(emoji)) reactions.remove(emoji);
                else reactions.add(emoji);
              }
            }
          }
        });
      }
    }
  }

  // ── Typing ─────────────────────────────────────────────────────────
  void _onTextChanged() {
    final chats = _filteredChats;
    if (_selectedChatIndex < 0 || _selectedChatIndex >= chats.length) return;
    final peer = chats[_selectedChatIndex]['name'] as String;

    if (!_iAmTyping) {
      _iAmTyping = true;
      _socket.sendMessage({'type': 'typing', 'receiver': peer, 'is_typing': true});
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _iAmTyping = false;
      _socket.sendMessage({'type': 'typing', 'receiver': peer, 'is_typing': false});
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredChats {
    if (_myUsername.isEmpty) return allDummyChats;
    return allDummyChats.where((c) => c['name'] != _myUsername).toList();
  }

  void _scrollToBottom() {
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

  // ── Mark read ─────────────────────────────────────────────────────
  void _markMessagesRead(String peerName) {
    final chatIdx = allDummyChats.indexWhere((c) => c['name'] == peerName);
    if (chatIdx == -1) return;
    final messages = allDummyChats[chatIdx]['messages'] as List;
    for (final m in messages) {
      if (!(m['isMe'] as bool) && !(m['read'] as bool)) {
        m['read'] = true;
        _socket.sendMessage({'type': 'read_receipt', 'receiver': peerName, 'message_id': m['id']});
      }
    }
  }

  // ── File pick ─────────────────────────────────────────────────────
  void _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null) setState(() => _selectedFileName = result.files.single.name);
  }

  // ── Send message ──────────────────────────────────────────────────
  void _sendMessage() {
    if (_chatController.text.trim().isEmpty && _selectedFileName == null) return;
    final chats = _filteredChats;
    if (_selectedChatIndex == -1 || _selectedChatIndex >= chats.length) return;

    final targetName = chats[_selectedChatIndex]['name'] as String;
    final actualIdx = allDummyChats.indexWhere((c) => c['name'] == targetName);
    final msgId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
    final text = _chatController.text.trim();

    setState(() {
      allDummyChats[actualIdx]['messages'].add({
        'text': text,
        'isMe': true,
        'file': _selectedFileName,
        'read': false,
        'reactions': <String>[],
        'id': msgId,
      });
      _chatController.clear();
      _selectedFileName = null;
      if (_isEmojiVisible) _isEmojiVisible = false;
    });

    _socket.sendMessage({
      'type': 'private_message',
      'receiver': targetName,
      'content': text,
      'content_type': _selectedFileName != null ? 'file' : 'text',
      'filename': _selectedFileName,
    });

    _scrollToBottom();
  }

  // ── Delete message ─────────────────────────────────────────────────
  void _deleteMessage(String chatName, String msgId) {
    final chatIdx = allDummyChats.indexWhere((c) => c['name'] == chatName);
    if (chatIdx == -1) return;
    setState(() {
      (allDummyChats[chatIdx]['messages'] as List).removeWhere((m) => m['id'] == msgId);
    });
    _socket.sendMessage({'type': 'delete_message', 'receiver': chatName, 'message_id': msgId});
  }

  // ── Add reaction ──────────────────────────────────────────────────
  void _addReaction(String chatName, String msgId, String emoji) {
    final chatIdx = allDummyChats.indexWhere((c) => c['name'] == chatName);
    if (chatIdx == -1) return;
    setState(() {
      final msg = (allDummyChats[chatIdx]['messages'] as List).firstWhere((m) => m['id'] == msgId, orElse: () => null);
      if (msg != null) {
        final reactions = msg['reactions'] as List<String>;
        if (reactions.contains(emoji)) {
          reactions.remove(emoji);
        } else {
          reactions.add(emoji);
        }
      }
    });
    _socket.sendMessage({'type': 'reaction', 'receiver': chatName, 'message_id': msgId, 'emoji': emoji});
  }

  void _showReactionPicker(String chatName, String msgId) {
    const quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2B2D31),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: quickEmojis.map((e) => GestureDetector(
            onTap: () { Navigator.pop(ctx); _addReaction(chatName, msgId, e); },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(e, style: const TextStyle(fontSize: 24)),
            ),
          )).toList(),
        ),
      ),
    );
  }

  void _toggleEmojiPicker() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isEmojiVisible = !_isEmojiVisible);
  }

  // ── Theme ──────────────────────────────────────────────────────────
  Color get _bg => _isDarkMode ? const Color(0xFF202225) : const Color(0xFFF2F3F5);
  Color get _surface => _isDarkMode ? const Color(0xFF2B2D31) : const Color(0xFFFFFFFF);
  Color get _chatBg => _isDarkMode ? const Color(0xFF313338) : const Color(0xFFE3E5E8);
  Color get _inputBg => _isDarkMode ? const Color(0xFF383A40) : const Color(0xFFD9DADE);
  Color get _textPrimary => _isDarkMode ? Colors.white : const Color(0xFF060607);
  Color get _textSecondary => _isDarkMode ? Colors.white54 : Colors.black45;
  Color get _sidebarBg => _isDarkMode ? const Color(0xFF1E1F22) : const Color(0xFFE3E5E8);

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(
        backgroundColor: Color(0xFF1E1F22),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF5865F2))),
      );
    }
    return Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          _buildSidebar(),
          if (MediaQuery.of(context).size.width > 600) _buildChatList(),
          Expanded(child: _buildChatArea()),
        ],
      ),
    );
  }

  // ── Sidebar ────────────────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      width: 72,
      color: _sidebarBg,
      child: Column(
        children: [
          const SizedBox(height: 12),
          _buildServerIcon(Icons.chat_bubble, 0, isIcon: true),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Divider(color: _isDarkMode ? Colors.white12 : Colors.black12, height: 1),
          ),
          ...List.generate(dummyServers.length, (i) => _buildServerIcon(dummyServers[i], i + 1)),
          const Spacer(),
          // Theme toggle
          IconButton(
            icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode, color: const Color(0xFF5865F2)),
            onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
            tooltip: _isDarkMode ? 'Light Mode' : 'Dark Mode',
          ),
          IconButton(
            icon: const Icon(Icons.people, color: Color(0xFF5865F2)),
            onPressed: () => Navigator.pushNamed(context, '/friends'),
            tooltip: 'Friends',
          ),
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
    final isSelected = _selectedServerIndex == index;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedServerIndex = index;
        _selectedChatIndex = -1;
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
                decoration: BoxDecoration(
                  color: _textPrimary,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF5865F2) : (_isDarkMode ? const Color(0xFF313338) : const Color(0xFFD9DADE)),
                  borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
                  boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF5865F2).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : [],
                ),
                child: Center(
                  child: isIcon
                      ? Icon(content as IconData, color: isSelected ? Colors.white : _textSecondary)
                      : Text(content as String, style: TextStyle(color: isSelected ? Colors.white : _textSecondary, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Chat List ──────────────────────────────────────────────────────
  Widget _buildChatList() {
    final chats = _filteredChats;
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: _surface,
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(2, 0))],
      ),
      child: Column(
        children: [
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Text('Direct Messages', style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: chats.length,
              itemBuilder: (ctx, i) {
                final chat = chats[i];
                final chatName = chat['name'] as String;
                final isSelected = _selectedChatIndex == i;
                final isOnline = _onlineUsers.contains(chatName);
                final msgs = chat['messages'] as List;
                String lastMsg = msgs.isEmpty ? '' : (msgs.last['text'] as String? ?? '');
                if (lastMsg.isEmpty && msgs.isNotEmpty && msgs.last['file'] != null) {
                  lastMsg = '📎 ${msgs.last['file']}';
                }
                final unread = msgs.where((m) => !(m['isMe'] as bool) && !(m['read'] as bool)).length;

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF404249) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFF5865F2),
                          child: Text(chatName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        // Online indicator dot
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFF23A55A) : Colors.grey,
                              shape: BoxShape.circle,
                              border: Border.all(color: _surface, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(chatName, style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w600))),
                        if (unread > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFF5865F2), borderRadius: BorderRadius.circular(10)),
                            child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    subtitle: _typingStatus[chatName] == true
                        ? _buildTypingIndicator()
                        : Text(lastMsg, style: TextStyle(color: _textSecondary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      setState(() => _selectedChatIndex = i);
                      _markMessagesRead(chatName);
                    },
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

  Widget _buildTypingIndicator() {
    return AnimatedBuilder(
      animation: _dotController,
      builder: (_, __) {
        final t = _dotController.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (t - i * 0.2).clamp(0.0, 1.0);
            final y = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            return Transform.translate(
              offset: Offset(0, -4 * y),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 6, height: 6,
                decoration: const BoxDecoration(color: Color(0xFF00A884), shape: BoxShape.circle),
              ),
            );
          }),
        );
      },
    );
  }

  // ── Chat Area ──────────────────────────────────────────────────────
  Widget _buildChatArea() {
    final chats = _filteredChats;
    if (_selectedChatIndex == -1 || _selectedChatIndex >= chats.length) {
      return Container(
        color: _chatBg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 80, color: _textSecondary.withOpacity(0.3)),
              const SizedBox(height: 16),
              Text('Select a chat to start messaging', style: TextStyle(color: _textSecondary, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    final currentChat = chats[_selectedChatIndex];
    final chatName = currentChat['name'] as String;
    final messages = currentChat['messages'] as List;
    final isOnline = _onlineUsers.contains(chatName);
    final isPeerTyping = _typingStatus[chatName] == true;

    return Container(
      color: _chatBg,
      child: Column(
        children: [
          // Chat Header
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _chatBg,
              border: const Border(bottom: BorderSide(color: Colors.black12, width: 1)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF5865F2),
                      child: Text(chatName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    Positioned(
                      right: 0, bottom: 0,
                      child: Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFF23A55A) : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: _chatBg, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chatName, style: TextStyle(color: _textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                    Text(isOnline ? 'Online' : 'Offline', style: TextStyle(color: isOnline ? const Color(0xFF23A55A) : _textSecondary, fontSize: 12)),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.call, color: _textSecondary),
                  onPressed: () => Navigator.pushNamed(context, '/call', arguments: {'peer': chatName, 'callType': 'voice'}),
                  tooltip: 'Voice Call',
                ),
                IconButton(
                  icon: Icon(Icons.videocam, color: _textSecondary),
                  onPressed: () => Navigator.pushNamed(context, '/call', arguments: {'peer': chatName, 'callType': 'video'}),
                  tooltip: 'Video Call',
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(24),
              itemCount: messages.length,
              itemBuilder: (ctx, i) {
                final msg = messages[i];
                return _buildMessageBubble(chatName, msg);
              },
            ),
          ),
          // Peer typing banner
          if (isPeerTyping)
            Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 4),
              child: Row(
                children: [
                  _buildTypingIndicator(),
                  const SizedBox(width: 8),
                  Text('$chatName is typing...', style: TextStyle(color: _textSecondary, fontSize: 12)),
                ],
              ),
            ),
          // File Preview
          if (_selectedFileName != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _sidebarBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file, color: Color(0xFF5865F2), size: 20),
                  const SizedBox(width: 8),
                  Text(_selectedFileName!, style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(width: 8),
                  InkWell(onTap: () => setState(() => _selectedFileName = null), child: Icon(Icons.close, color: _textSecondary, size: 18)),
                ],
              ),
            ),
          // Input
          Container(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20, top: 4),
            child: Row(
              children: [
                IconButton(icon: Icon(Icons.add_circle_outline, color: _textSecondary), onPressed: _pickFile, tooltip: 'Share File'),
                IconButton(icon: Icon(Icons.emoji_emotions_outlined, color: _textSecondary), onPressed: _toggleEmojiPicker, tooltip: 'Emojis'),
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    onTap: () { if (_isEmojiVisible) setState(() => _isEmojiVisible = false); },
                    onSubmitted: (_) => _sendMessage(),
                    style: TextStyle(color: _textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Message @$chatName',
                      hintStyle: TextStyle(color: _textSecondary),
                      filled: true,
                      fillColor: _inputBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      suffixIcon: GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Color(0xFF5865F2), shape: BoxShape.circle),
                          child: const Icon(Icons.send, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isEmojiVisible)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: (_, emoji) => setState(() => _chatController.text += emoji.emoji),
                config: Config(
                  emojiViewConfig: EmojiViewConfig(
                    backgroundColor: _surface,
                    columns: 10,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    backgroundColor: _sidebarBg,
                    indicatorColor: const Color(0xFF5865F2),
                    iconColorSelected: const Color(0xFF5865F2),
                  ),
                  bottomActionBarConfig: BottomActionBarConfig(
                    backgroundColor: _sidebarBg,
                    buttonColor: _sidebarBg,
                    buttonIconColor: _textPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Message Bubble ─────────────────────────────────────────────────
  Widget _buildMessageBubble(String chatName, Map<String, dynamic> msg) {
    final isMe = msg['isMe'] as bool;
    final text = msg['text'] as String? ?? '';
    final fileName = msg['file'] as String?;
    final isRead = msg['read'] as bool? ?? false;
    final reactions = (msg['reactions'] as List<String>?) ?? [];
    final msgId = msg['id'] as String;

    return GestureDetector(
      onLongPress: () => _showMessageOptions(chatName, msgId, isMe),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isMe)
                  IconButton(
                    icon: Icon(Icons.shortcut, color: _textSecondary, size: 20),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Forwarding message...'))),
                    tooltip: 'Forward',
                  ),
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: isMe
                          ? const LinearGradient(colors: [Color(0xFF00A884), Color(0xFF00C698)])
                          : LinearGradient(colors: [_surface, _surface]),
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
                            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
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
                        // Read receipt
                        if (isMe)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.done_all, size: 14, color: isRead ? const Color(0xFF53BDEB) : Colors.white54),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!isMe)
                  IconButton(
                    icon: Icon(Icons.shortcut, color: _textSecondary, size: 20),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Forwarding message...'))),
                    tooltip: 'Forward',
                  ),
              ],
            ),
            // Reactions row
            if (reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 8, right: 8),
                child: Wrap(
                  spacing: 4,
                  children: reactions.map((e) => GestureDetector(
                    onTap: () => _addReaction(chatName, msgId, e),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF5865F2).withOpacity(0.4)),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 14)),
                    ),
                  )).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMessageOptions(String chatName, String msgId, bool isMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Text('👍', style: TextStyle(fontSize: 20)),
              title: Text('React', style: TextStyle(color: _textPrimary)),
              onTap: () { Navigator.pop(ctx); _showReactionPicker(chatName, msgId); },
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                onTap: () { Navigator.pop(ctx); _deleteMessage(chatName, msgId); },
              ),
            ListTile(
              leading: Icon(Icons.shortcut, color: _textSecondary),
              title: Text('Forward', style: TextStyle(color: _textPrimary)),
              onTap: () { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Forwarding...'))); },
            ),
          ],
        ),
      ),
    );
  }
}
