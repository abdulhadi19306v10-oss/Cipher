import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<dynamic> _pending = [];
  List<dynamic> _accepted = [];
  bool _loading = true;
  int? _myUserId;

  final _usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getInt('user_id');
    if (_myUserId == null) { setState(() => _loading = false); return; }

    final result = await ApiService.getFriends(_myUserId!);
    if (mounted) {
      setState(() {
        _pending = result['pending'] ?? [];
        _accepted = result['accepted'] ?? [];
        _loading = false;
      });
    }
  }

  Future<void> _respond(int friendshipId, String action) async {
    await ApiService.respondToFriendRequest(_myUserId!, friendshipId, action);
    _load();
  }

  Future<void> _addByUsername() async {
    final name = _usernameController.text.trim();
    if (name.isEmpty || _myUserId == null) return;
    final res = await ApiService.addFriendByUsername(_myUserId!, name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['success'] ? 'Request sent to $name!' : (res['message'] ?? 'Error'))),
      );
      _usernameController.clear();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF202225),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1F22),
        title: const Text('Friends', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFF5865F2),
          labelColor: const Color(0xFF5865F2),
          unselectedLabelColor: Colors.white54,
          tabs: [
            Tab(text: 'Pending${_pending.isNotEmpty ? " (${_pending.length})" : ""}'),
            const Tab(text: 'Friends'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Add by username bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Add friend by username...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF383A40),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5865F2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onPressed: _addByUsername,
                  child: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF5865F2)))
                : TabBarView(
                    controller: _tabs,
                    children: [_buildPending(), _buildAccepted()],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPending() {
    if (_pending.isEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_outline, size: 64, color: Colors.white24),
          const SizedBox(height: 12),
          Text('No pending requests', style: TextStyle(color: Colors.white54)),
        ],
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _pending.length,
      itemBuilder: (ctx, i) {
        final req = _pending[i];
        final isIncoming = req['friend_id'] == _myUserId;
        final displayName = isIncoming ? (req['user_username'] ?? 'Unknown') : (req['friend_username'] ?? 'Unknown');
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2D31),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF5865F2),
                child: Text((displayName as String)[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    Text(isIncoming ? 'Wants to be your friend' : 'Request sent',
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              if (isIncoming) ...[
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Color(0xFF23A55A)),
                  onPressed: () => _respond(req['id'], 'accept'),
                  tooltip: 'Accept',
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.redAccent),
                  onPressed: () => _respond(req['id'], 'reject'),
                  tooltip: 'Reject',
                ),
              ] else
                const Chip(label: Text('Pending', style: TextStyle(color: Colors.white54, fontSize: 11)), backgroundColor: Color(0xFF383A40)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccepted() {
    if (_accepted.isEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_outline, size: 64, color: Colors.white24),
          const SizedBox(height: 12),
          const Text('No friends yet. Add someone!', style: TextStyle(color: Colors.white54)),
        ],
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _accepted.length,
      itemBuilder: (ctx, i) {
        final f = _accepted[i];
        final displayName = f['user_id'] == _myUserId ? (f['friend_username'] ?? 'Unknown') : (f['user_username'] ?? 'Unknown');
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2D31),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF00A884),
                child: Text((displayName as String)[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
              const Icon(Icons.circle, color: Color(0xFF23A55A), size: 10),
            ],
          ),
        );
      },
    );
  }
}
