import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class SocketService {
  // Singleton pattern
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  Socket? _socket;
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();
  
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // Change to your server's IP when testing on a physical device.
  // 10.0.2.2 is the localhost alias for the Android Emulator.
  // 127.0.0.1 is for Desktop/iOS Simulator.
  final String _host = '127.0.0.1'; 
  final int _port = 5000;

  Future<void> connect(String username) async {
    try {
      _socket = await Socket.connect(_host, _port);
      print('Connected to Cipher TCP Server');

      // The Python server expects a raw TCP socket with 4-byte big-endian framing
      _socket!.listen(
        _onDataReceived,
        onError: (error) {
          print('Socket Error: $error');
          _socket?.destroy();
        },
        onDone: () {
          print('Socket Disconnected');
          _socket?.destroy();
        },
      );

      // Register with the server immediately after connecting
      sendMessage({
        'type': 'register',
        'username': username,
      });

    } catch (e) {
      print('Failed to connect to socket: $e');
    }
  }

  // Handle the 4-byte framing protocol from the Python server
  List<int> _buffer = [];

  void _onDataReceived(List<int> data) {
    _buffer.addAll(data);

    while (true) {
      if (_buffer.length < 4) return;

      // Extract 4-byte payload length (Big Endian)
      final lengthBytes = Uint8List.fromList(_buffer.sublist(0, 4));
      final payloadData = ByteData.view(lengthBytes.buffer);
      final payloadLength = payloadData.getUint32(0, Endian.big);

      if (_buffer.length < 4 + payloadLength) return;

      // Extract the JSON payload
      final payloadBytes = _buffer.sublist(4, 4 + payloadLength);
      final payloadString = utf8.decode(payloadBytes);
      
      try {
        final decodedMap = jsonDecode(payloadString);
        _messageController.add(decodedMap);
      } catch (e) {
        print('Error decoding socket JSON: $e');
      }

      // Remove the processed message from the buffer
      _buffer.removeRange(0, 4 + payloadLength);
    }
  }

  void sendMessage(Map<String, dynamic> data) {
    if (_socket == null) return;
    
    final payloadString = jsonEncode(data);
    final payloadBytes = utf8.encode(payloadString);
    
    // Prefix with 4-byte big-endian length
    final lengthData = ByteData(4)..setUint32(0, payloadBytes.length, Endian.big);
    final packet = [...lengthData.buffer.asUint8List(), ...payloadBytes];
    
    _socket!.add(packet);
  }

  void disconnect() {
    _socket?.destroy();
    _socket = null;
    _messageController.close(); // ponytail: fix BUG-7, close stream to prevent leak
  }
}
