import 'package:encrypt/encrypt.dart' as enc;
// ponytail: fix DEAD-2 — pointycastle removed until RSA is actually implemented

class EncryptionService {
  // Singleton pattern
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  // For E2EE, we use AES for message payloads, and RSA to securely exchange the AES key.
  // This is a foundational setup for Phase 4 E2EE.
  
  enc.Key? _sessionAesKey;
  // ponytail: fix BUG-8 — no static IV; random IV generated per message

  /// Generates a new random AES key for a chat session.
  void generateSessionKey() {
    _sessionAesKey = enc.Key.fromSecureRandom(32); // 256-bit AES
  }

  /// Sets an AES key received securely from a peer.
  void setSessionKey(String base64Key) {
    _sessionAesKey = enc.Key.fromBase64(base64Key);
  }

  /// Encrypts a plaintext message string. Returns 'ivBase64:ciphertextBase64'.
  String encryptMessage(String plainText) {
    if (_sessionAesKey == null) {
      throw Exception('Session AES key is not set. Cannot encrypt.');
    }
    final iv = enc.IV.fromSecureRandom(16); // ponytail: fix BUG-8 — random IV per message
    final encrypter = enc.Encrypter(enc.AES(_sessionAesKey!));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypts a message string in 'ivBase64:ciphertextBase64' format.
  String decryptMessage(String encryptedPayload) {
    if (_sessionAesKey == null) {
      throw Exception('Session AES key is not set. Cannot decrypt.');
    }
    final parts = encryptedPayload.split(':');
    if (parts.length != 2) throw Exception('Invalid encrypted payload format.');
    final iv = enc.IV.fromBase64(parts[0]); // ponytail: fix BUG-8 — extract IV from payload
    final encrypter = enc.Encrypter(enc.AES(_sessionAesKey!));
    return encrypter.decrypt64(parts[1], iv: iv);
  }

  // NOTE: In a full production scenario, each client generates an RSA keypair on login.
  // The public key is uploaded to the FastAPI backend.
  // When User A wants to talk to User B, User A fetches B's RSA public key, 
  // generates an AES key, encrypts the AES key with B's RSA public key, and sends it.
}
