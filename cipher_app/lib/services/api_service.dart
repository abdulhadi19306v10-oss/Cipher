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
        await _saveSession(data['id'], data['username'], data['qr_code_string']);
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
        await _saveSession(data['id'], data['username'], data['qr_code_string']);
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'message': jsonDecode(response.body)['detail']};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network Error: Cannot connect to server.'};
    }
  }

  static Future<void> _saveSession(int id, String username, String qrCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', id);
    await prefs.setString('username', username);
    await prefs.setString('qr_code', qrCode);
  }
}
