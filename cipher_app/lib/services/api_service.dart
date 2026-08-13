import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Use 10.0.2.2 for Android Emulator connecting to localhost
  // Or your machine's IP for physical device
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  static Future<Map<String, dynamic>> register(String username, String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
          'device_fingerprint': 'flutter_client',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveSession(data['id'], data['username'], data['qr_code_string'], data['access_token']);
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': jsonDecode(response.body)['detail']};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network Error: Cannot connect to server.'};
    }
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveSession(data['id'], data['username'], data['qr_code_string'], data['access_token']);
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': jsonDecode(response.body)['detail']};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network Error: Cannot connect to server.'};
    }
  }

  static Future<void> _saveSession(int id, String username, String qrCode, String? token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', id);
    await prefs.setString('username', username);
    await prefs.setString('qr_code', qrCode);
    if (token != null) {
      await prefs.setString('jwt_token', token);
    }
  }

  // ponytail: retrieve Bearer authentication headers
  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ponytail: fix BUG-3 — this was missing, QR scanner calls it
  static Future<Map<String, dynamic>> addFriendByQr(int userId, String qrValue) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/add_friend?target_identifier=${Uri.encodeComponent(qrValue)}&by_qr=true'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        return {'success': false, 'message': jsonDecode(response.body)['detail']};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network Error: Cannot connect to server.'};
    }
  }

  static Future<Map<String, dynamic>> addFriendByUsername(int userId, String username) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/add_friend?target_identifier=${Uri.encodeComponent(username)}&by_qr=false'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        return {'success': false, 'message': jsonDecode(response.body)['detail']};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network Error: Cannot connect to server.'};
    }
  }

  static Future<Map<String, dynamic>> getFriends(int userId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/friends'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true, ...jsonDecode(response.body) as Map<String, dynamic>};
      } else {
        return {'success': false, 'pending': [], 'accepted': []};
      }
    } catch (e) {
      return {'success': false, 'pending': [], 'accepted': []};
    }
  }

  static Future<void> respondToFriendRequest(int userId, int friendshipId, String action) async {
    try {
      final headers = await _getHeaders();
      await http.patch(
        Uri.parse('$baseUrl/friends/$friendshipId?action=$action'),
        headers: headers,
      );
    } catch (_) {}
  }

  // ponytail: Phase 5 push notification fcm token register
  static Future<Map<String, dynamic>> updateFcmToken(int userId, String fcmToken) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/users/fcm_token?fcm_token=${Uri.encodeComponent(fcmToken)}'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return {'success': true};
      } else {
        return {'success': false, 'message': jsonDecode(response.body)['detail']};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network Error: Cannot connect to server.'};
    }
  }
}

