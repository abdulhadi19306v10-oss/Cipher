import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/api.dart' show KeyParameter, ParametersWithRandom;

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  // ponytail: Map to hold AES session keys per username
  final Map<String, enc.Key> _sessionKeys = {};
  
  RSAPrivateKey? _myPrivateKey;
  RSAPublicKey? _myPublicKey;

  /// Generates our ephemeral RSA-2048 keypair.
  void generateRsaKeyPair() {
    final keyGen = RSAKeyGenerator();
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    
    keyGen.init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
      secureRandom
    ));
    
    final pair = keyGen.generateKeyPair();
    _myPublicKey = pair.publicKey as RSAPublicKey;
    _myPrivateKey = pair.privateKey as RSAPrivateKey;
  }

  /// Serializes our public key as a simple JSON string to bypass DER/ASN.1 packaging boilerplate.
  String? getMyPublicKeyString() {
    if (_myPublicKey == null) return null;
    return jsonEncode({
      'modulus': _myPublicKey!.modulus.toString(),
      'exponent': _myPublicKey!.publicExponent.toString(),
    });
  }

  /// Parses public key from modulus/exponent JSON string.
  RSAPublicKey parsePublicKey(String keyStr) {
    final data = jsonDecode(keyStr);
    return RSAPublicKey(
      BigInt.parse(data['modulus']),
      BigInt.parse(data['exponent']),
    );
  }

  /// Generates a new random AES session key for a chat session.
  void generateSessionKey(String username) {
    _sessionKeys[username] = enc.Key.fromSecureRandom(32); // 256-bit AES
  }

  /// Sets an AES key received securely from a peer.
  void setSessionKey(String username, String base64Key) {
    _sessionKeys[username] = enc.Key.fromBase64(base64Key);
  }

  /// Returns true if a session AES key is negotiated for this username.
  bool hasSessionKey(String username) {
    return _sessionKeys.containsKey(username);
  }

  /// Retrieves the base64 AES session key for a peer (to encrypt for them).
  String? getSessionKeyBase64(String username) {
    return _sessionKeys[username]?.base64;
  }

  /// Encrypts the local AES key with peer's RSA public key.
  String encryptSessionKey(String username, String peerPublicKeyStr) {
    final key = _sessionKeys[username];
    if (key == null) throw Exception('No session key generated for $username');
    final peerPublicKey = parsePublicKey(peerPublicKeyStr);
    final encrypter = enc.Encrypter(enc.RSA(publicKey: peerPublicKey));
    final encrypted = encrypter.encrypt(key.base64);
    return encrypted.base64;
  }

  /// Decrypts an AES session key with our RSA private key and stores it.
  void decryptAndSetSessionKey(String username, String encryptedSessionKeyBase64) {
    if (_myPrivateKey == null) throw Exception('RSA private key is not generated.');
    final encrypter = enc.Encrypter(enc.RSA(privateKey: _myPrivateKey!));
    final decryptedKeyBase64 = encrypter.decrypt(enc.Encrypted.fromBase64(encryptedSessionKeyBase64));
    setSessionKey(username, decryptedKeyBase64);
  }

  /// Encrypts a private message using the peer's AES session key.
  String encryptMessage(String username, String plainText) {
    final key = _sessionKeys[username];
    if (key == null) {
      throw Exception('Session AES key is not set for $username. Cannot encrypt.');
    }
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypts a private message using the peer's AES session key.
  String decryptMessage(String username, String encryptedPayload) {
    final key = _sessionKeys[username];
    if (key == null) {
      throw Exception('Session AES key is not set for $username. Cannot decrypt.');
    }
    final colonIdx = encryptedPayload.indexOf(':');
    if (colonIdx == -1) throw Exception('Invalid encrypted payload: missing IV separator.');
    final iv = enc.IV.fromBase64(encryptedPayload.substring(0, colonIdx));
    final encrypter = enc.Encrypter(enc.AES(key));
    return encrypter.decrypt64(encryptedPayload.substring(colonIdx + 1), iv: iv);
  }
}
