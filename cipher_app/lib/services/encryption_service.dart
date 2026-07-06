import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/asymmetric/api.dart';

class EncryptionService {
  // Singleton pattern
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  // For E2EE, we use AES for message payloads, and RSA to securely exchange the AES key.
  // This is a foundational setup for Phase 4 E2EE.
  
  enc.Key? _sessionAesKey;
  final _iv = enc.IV.fromLength(16);

  /// Generates a new random AES key for a chat session.
  void generateSessionKey() {
    _sessionAesKey = enc.Key.fromSecureRandom(32); // 256-bit AES
  }

  /// Sets an AES key received securely from a peer.
  void setSessionKey(String base64Key) {
    _sessionAesKey = enc.Key.fromBase64(base64Key);
  }

  /// Encrypts a plaintext message string.
  String encryptMessage(String plainText) {
    if (_sessionAesKey == null) {
      throw Exception('Session AES key is not set. Cannot encrypt.');
    }
    final encrypter = enc.Encrypter(enc.AES(_sessionAesKey!));
    final encrypted = encrypter.encrypt(plainText, iv: _iv);
    return encrypted.base64;
  }

  /// Decrypts a base64 encoded encrypted message string.
  String decryptMessage(String encryptedBase64) {
    if (_sessionAesKey == null) {
      throw Exception('Session AES key is not set. Cannot decrypt.');
    }
    final encrypter = enc.Encrypter(enc.AES(_sessionAesKey!));
    final decrypted = encrypter.decrypt64(encryptedBase64, iv: _iv);
    return decrypted;
  }

  // NOTE: In a full production scenario, each client generates an RSA keypair on login.
  // The public key is uploaded to the FastAPI backend.
  // When User A wants to talk to User B, User A fetches B's RSA public key, 
  // generates an AES key, encrypts the AES key with B's RSA public key, and sends it.
}
