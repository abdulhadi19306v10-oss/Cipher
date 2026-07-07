import 'dart:async';
import 'package:flutter/material.dart';
import '../services/socket_service.dart';

/// Full call screen — handles both outgoing (caller) and incoming (callee) states.
/// Navigate here with: Navigator.pushNamed(context, '/call', arguments: {'peer': 'Alice', 'callType': 'voice'})
/// Or the HomeScreen pushes here automatically on an incoming_call socket event.
class CallScreen extends StatefulWidget {
  final String peer;
  final String callType; // 'voice' | 'video'
  final String? callId;  // null = outgoing (we initiate), non-null = incoming
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.peer,
    required this.callType,
    this.callId,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  final SocketService _socket = SocketService();
  StreamSubscription? _sub;

  String _status = '';
  String? _callId;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCameraOff = false;
  bool _callConnected = false;
  int _callSeconds = 0;
  Timer? _callTimer;

  // Pulse animation for ringing state
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _callId = widget.callId;
    _status = widget.isIncoming ? 'Incoming ${widget.callType} call...' : 'Calling ${widget.peer}...';

    _sub = _socket.messageStream.listen(_onMessage);

    if (!widget.isIncoming) _initiateCall();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _callTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _onMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type'];
    if (type == 'call_initiated') {
      setState(() { _callId = msg['call_id']; _status = 'Ringing...'; });
    } else if (type == 'call_accepted') {
      _onCallConnected();
    } else if (type == 'call_connected') {
      _onCallConnected();
    } else if (type == 'call_rejected') {
      setState(() => _status = 'Call declined');
      Future.delayed(const Duration(seconds: 2), _hangUp);
    } else if (type == 'call_ended') {
      setState(() => _status = 'Call ended');
      Future.delayed(const Duration(seconds: 1), _hangUp);
    }
  }

  void _initiateCall() {
    _socket.sendMessage({
      'type': widget.callType == 'voice' ? 'voice_call' : 'video_call',
      'receiver': widget.peer,
    });
  }

  void _onCallConnected() {
    setState(() { _callConnected = true; _status = 'Connected'; });
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  void _acceptCall() {
    if (_callId == null) return;
    _socket.sendMessage({'type': 'call_response', 'call_id': _callId, 'response': 'accept'});
  }

  void _rejectCall() {
    if (_callId != null) {
      _socket.sendMessage({'type': 'call_response', 'call_id': _callId, 'response': 'reject'});
    }
    Navigator.pop(context);
  }

  void _hangUp() {
    if (_callId != null) {
      _socket.sendMessage({'type': 'end_call', 'call_id': _callId});
    }
    if (mounted) Navigator.pop(context);
  }

  String get _formattedDuration {
    final m = _callSeconds ~/ 60;
    final s = _callSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Call type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.callType == 'voice' ? Icons.call : Icons.videocam, color: const Color(0xFF5865F2), size: 16),
                    const SizedBox(width: 6),
                    Text(widget.callType == 'voice' ? 'Voice Call' : 'Video Call',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // Avatar with pulse
              ScaleTransition(
                scale: _callConnected ? const AlwaysStoppedAnimation(1.0) : _pulseAnim,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [Color(0xFF5865F2), Color(0xFF00A884)]),
                    boxShadow: [BoxShadow(color: const Color(0xFF5865F2).withOpacity(0.5), blurRadius: 40, spreadRadius: 10)],
                  ),
                  child: Center(
                    child: Text(
                      widget.peer[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(widget.peer, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                _callConnected ? _formattedDuration : _status,
                style: TextStyle(color: _callConnected ? const Color(0xFF23A55A) : Colors.white54, fontSize: 16),
              ),
              const Spacer(),
              // Controls
              if (_callConnected) _buildActiveControls(),
              if (widget.isIncoming && !_callConnected) _buildIncomingControls(),
              if (!widget.isIncoming && !_callConnected) _buildOutgoingControls(),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveControls() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _controlButton(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              label: _isMuted ? 'Unmute' : 'Mute',
              onTap: () => setState(() => _isMuted = !_isMuted),
              active: _isMuted,
            ),
            _controlButton(
              icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
              label: 'Speaker',
              onTap: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
              active: _isSpeakerOn,
            ),
            if (widget.callType == 'video')
              _controlButton(
                icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                label: 'Camera',
                onTap: () => setState(() => _isCameraOff = !_isCameraOff),
                active: _isCameraOff,
              ),
          ],
        ),
        const SizedBox(height: 32),
        // End call button
        GestureDetector(
          onTap: _hangUp,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 20)],
            ),
            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
          ),
        ),
      ],
    );
  }

  Widget _buildIncomingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Reject
        GestureDetector(
          onTap: _rejectCall,
          child: Container(
            width: 70, height: 70,
            decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 20)]),
            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
          ),
        ),
        // Accept
        GestureDetector(
          onTap: _acceptCall,
          child: Container(
            width: 70, height: 70,
            decoration: BoxDecoration(color: const Color(0xFF23A55A), shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: const Color(0xFF23A55A).withOpacity(0.5), blurRadius: 20)]),
            child: const Icon(Icons.call, color: Colors.white, size: 32),
          ),
        ),
      ],
    );
  }

  Widget _buildOutgoingControls() {
    return GestureDetector(
      onTap: _hangUp,
      child: Container(
        width: 70, height: 70,
        decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 20)]),
        child: const Icon(Icons.call_end, color: Colors.white, size: 32),
      ),
    );
  }

  Widget _controlButton({required IconData icon, required String label, required VoidCallback onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: active ? const Color(0xFF5865F2) : Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}
