# Cipher Codebase Review

> Reviewed: 2026-07-07 | Mode: ponytail ultra

---

## Summary

| Layer | Files | Bugs | Security | Dead Code |
|---|---|---|---|---|
| Python API (`api/`) | 3 | 3 | 3 | 1 |
| Python Server (`chat_server.py`) | 1 | 3 | 1 | 1 |
| Flutter App (`cipher_app/`) | 7 | 6 | 2 | 2 |
| **Total** | **11** | **12** | **6** | **4** |

---

## 🔴 Critical Bugs

### [BUG-1] TCP and UDP bound to the same port — server crashes on start
**File:** [`chat_server.py:55-57`](file:///C:/Users/Abdul%20Hadi/Cipher/chat_server.py)

```python
# BROKEN: both bind to PORT 5000 — second bind raises OSError
self.server_socket.bind((HOST, PORT))   # TCP
self.udp_socket.bind((HOST, PORT))      # UDP — crashes here
```

TCP and UDP are separate protocols, so the OS allows both to bind the same port number *in theory*, but on Windows this often fails or behaves unexpectedly without `SO_REUSEADDR` set on the UDP socket **before** binding.

**Fix:**
```python
# Set SO_REUSEADDR on UDP socket before bind, OR use a separate port (e.g. 5001)
self.udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
self.udp_socket.bind((HOST, PORT))   # now safe, or use PORT+1
```

---

### [BUG-2] `_setup_data_directory` can return `None` — unhandled crash
**File:** [`chat_server.py:51`](file:///C:/Users/Abdul%20Hadi/Cipher/chat_server.py)

```python
return None  # <-- self.data_dir = None silently, crashes if used later
```

`self.data_dir` is never actually used anywhere after assignment, but the bare `except: continue` swallows all errors silently too.

**Fix:**
```python
# Either raise, or pick tempdir as final fallback — never return None
raise RuntimeError("Cannot create data directory in any location")
```

---

### [BUG-3] `_onDetect` in QR scanner does nothing — friend-add is dead
**File:** [`qr_scanner_screen.dart:32-39`](file:///C:/Users/Abdul%20Hadi/Cipher/cipher_app/lib/screens/qr_scanner_screen.dart)

```dart
void _onDetect(BarcodeCapture capture) async {
  for (final barcode in barcodes) {
    if (barcode.rawValue != null && barcode.rawValue!.startsWith('cipher-qr-')) {
      // Send add friend request
      // Pause scanner conceptually or handle single trigger
      // ← NOTHING HAPPENS. Empty body.
    }
  }
}
```

The QR scan detects the code but never calls the API or navigates anywhere.

**Fix:**
```dart
void _onDetect(BarcodeCapture capture) async {
  for (final barcode in capture.barcodes) {
    final val = barcode.rawValue;
    if (val != null && val.startsWith('cipher-qr-') && myUserId != null) {
      // ponytail: minimal — just call the endpoint and pop
      await ApiService.addFriendByQr(myUserId!, val);
      if (mounted) Navigator.pop(context);
      return; // stop processing after first valid code
    }
  }
}
```

---

### [BUG-4] `_handle_call_media` relays call media over TCP, not UDP
**File:** [`chat_server.py:379-394`](file:///C:/Users/Abdul%20Hadi/Cipher/chat_server.py)

The `process()` dispatch table routes `call_media` TCP messages to `_handle_call_media`, which re-sends media over TCP. Meanwhile the `udp_receive_loop` also handles `call_media` over UDP. This means media sent via TCP gets relayed again over TCP — wrong path, high latency, wrong framing.

**Fix:**
Remove `'call_media': self._handle_call_media` from the TCP dispatch table in `process()`. Media relay should only happen in `udp_receive_loop`.

```python
handlers = {
    'private_message': self._handle_private_message,
    # ... rest of handlers ...
    'forward_message': self._handle_forward_message,
    # 'call_media' removed — handled by UDP loop only
}
```

---

## 🔴 Security Issues

### [SEC-1] No authentication on `/api/add_friend` — any user can add friends as anyone
**File:** [`api/main.py:105-131`](file:///C:/Users/Abdul%20Hadi/Cipher/api/main.py)

```python
@app.post("/api/add_friend")
def add_friend(user_id: int, target_identifier: str, ...):
    # user_id comes from the query string — anyone can spoof it
```

`user_id` is a plain query parameter. Anyone can call `POST /api/add_friend?user_id=1&target_identifier=admin` and act as user 1.

**Fix:** Use a JWT or session token. At minimum, verify the user_id against a session:
```python
# Add a dependency that validates a session token header
# and returns the authenticated user_id from the DB, not from the request.
```

---

### [SEC-2] `bcrypt` imported twice — `passlib` imported but unused
**File:** [`api/main.py:4,15`](file:///C:/Users/Abdul%20Hadi/Cipher/api/main.py)

```python
from passlib.context import CryptContext   # line 4 — never used
# ...
import bcrypt                               # line 15 — this is what's actually used
```

`passlib` is imported (and in `requirements.txt`) but never used. Only `bcrypt` is used directly. This is confusion waiting to cause a real bug if someone deletes one thinking it's a duplicate.

**Fix:**
```python
# Remove passlib import entirely from main.py
# Remove passlib[bcrypt] from requirements.txt — bcrypt alone is sufficient
import bcrypt
```

---

### [SEC-3] In-memory rate limiter resets on every server restart — no real protection
**File:** [`api/main.py:38-58`](file:///C:/Users/Abdul Hadi/Cipher/api/main.py)

```python
ip_registration_tracker = {}  # dies on restart
```

A simple restart bypasses the anti-alt protection entirely.

**Fix (minimum viable):** Persist to the SQLite DB or use Redis. At the very minimum, use the existing `registered_ip` column in the `User` table to do a DB-level check:
```python
# Already stored: registered_ip on User model
# Just query: does any user share this IP and was created in last hour?
recent = db.query(models.User).filter(
    models.User.registered_ip == client_ip,
    models.User.created_at > datetime.utcnow() - timedelta(hours=1)
).first()
if recent:
    raise HTTPException(status_code=429, ...)
```

---

### [SEC-4] `device_fingerprint` is hardcoded to `'flutter_client'` — anti-alt is bypassed
**File:** [`api_service.dart:19`](file:///C:/Users/Abdul%20Hadi/Cipher/cipher_app/lib/services/api_service.dart)

```dart
'device_fingerprint': 'flutter_client',  // every device sends the same string
```

The API blocks accounts if they share a `device_fingerprint`. Since every Flutter client sends `'flutter_client'`, the second registration on any device will be blocked — or the check is useless, depending on timing.

**Fix:** Use a real device identifier. The `device_info_plus` package gives a stable hardware ID:
```dart
// ponytail: one dep added, but it's the whole point of the feature
final deviceInfo = DeviceInfoPlugin();
final id = Platform.isAndroid
    ? (await deviceInfo.androidInfo).id
    : (await deviceInfo.iosInfo).identifierForVendor ?? 'unknown';
```

---

### [SEC-5] Login returns the full user object including `hashed_password` field path
**File:** [`api/main.py:98-103`](file:///C:/Users/Abdul%20Hadi/Cipher/api/main.py)

`login` returns `user` which is a SQLAlchemy model serialized via `UserResponse`. `UserResponse` does not include `hashed_password`, so it's fine — **but** `UserResponse` also doesn't include `is_active` check. A deactivated user can still log in.

**Fix:**
```python
def login(creds: LoginRequest, db: Session = Depends(database.get_db)):
    user = db.query(models.User).filter(models.User.email == creds.email).first()
    if not user or not verify_password(creds.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    if not user.is_active:                          # ← add this
        raise HTTPException(status_code=403, detail="Account is deactivated")
    return user
```

---

## 🟡 Logic Bugs

### [BUG-5] `_filteredChats` filters by `_myUsername` but username loads async
**File:** [`home_screen.dart:66-68`](file:///C:/Users/Abdul%20Hadi/Cipher/cipher_app/lib/screens/home_screen.dart)

```dart
List<Map<String, dynamic>> get _filteredChats {
  return allDummyChats.where((chat) => chat['name'] != _myUsername).toList();
}
```

`_myUsername` starts as `''`. Before `_loadUsername()` resolves, the filter compares `'' != 'Alice'` → true for all, so no chats are filtered. This is harmless with dummy data but will break with real data.

**Fix:** Guard with `_isReady` (already exists) or just filter only when `_myUsername.isNotEmpty`.

---

### [BUG-6] `Navigator.pushReplacementNamed` then `ScaffoldMessenger` — context may be detached
**File:** [`login_screen.dart:26-27`](file:///C:/Users/Abdul%20Hadi/Cipher/cipher_app/lib/screens/login_screen.dart), [`register_screen.dart:28-29`](file:///C:/Users/Abdul%20Hadi/Cipher/cipher_app/lib/screens/register_screen.dart)

```dart
Navigator.pushReplacementNamed(context, '/home');  // screen is replaced
ScaffoldMessenger.of(context).showSnackBar(...);   // context may no longer be valid
```

After `pushReplacement`, the current widget is removed from the tree. `ScaffoldMessenger.of(context)` on a detached context throws in debug or silently fails in release.

**Fix:** Swap the order — show snackbar first, then navigate. Or show the snackbar on the *destination* screen.
```dart
ScaffoldMessenger.of(context).showSnackBar(...);
Navigator.pushReplacementNamed(context, '/home');
```

---

### [BUG-7] `SocketService.disconnect()` doesn't close the `StreamController`
**File:** [`socket_service.dart:97-100`](file:///C:/Users/Abdul%20Hadi/Cipher/cipher_app/lib/services/socket_service.dart)

```dart
void disconnect() {
  _socket?.destroy();
  _socket = null;
  // _messageController is never closed → memory leak
}
```

**Fix:**
```dart
void disconnect() {
  _socket?.destroy();
  _socket = null;
  _messageController.close(); // ponytail: one line, fixes the leak
}
```

---

### [BUG-8] `EncryptionService` uses a static IV — breaks AES-CBC security
**File:** [`encryption_service.dart:14`](file:///C:/Users/Abdul%20Hadi/Cipher/cipher_app/lib/services/encryption_service.dart)

```dart
final _iv = enc.IV.fromLength(16);  // IV is always 16 zero bytes
```

Reusing the same IV with the same key for every message completely defeats AES-CBC. Two identical plaintexts will produce identical ciphertexts, and known-plaintext attacks become trivial.

**Fix:** Generate a random IV per message and prepend it to the ciphertext:
```dart
String encryptMessage(String plainText) {
  final iv = enc.IV.fromSecureRandom(16); // ponytail: random per message
  final encrypter = enc.Encrypter(enc.AES(_sessionAesKey!));
  final encrypted = encrypter.encrypt(plainText, iv: iv);
  return '${iv.base64}:${encrypted.base64}'; // prepend IV for decryption
}
```

---

### [BUG-9] `models.py` uses `datetime.utcnow` — deprecated in Python 3.12+
**File:** [`models.py:19,33`](file:///C:/Users/Abdul%20Hadi/Cipher/api/models.py)

```python
created_at = Column(DateTime, default=datetime.utcnow)
```

`datetime.utcnow` is deprecated since Python 3.12 and will be removed. It also returns a naive datetime (no timezone info).

**Fix:**
```python
from datetime import datetime, timezone
created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
```

---

## 🟠 Dead / Unnecessary Code

### [DEAD-1] `rigorous_tests.py` imports `chat_client.py` which is 74KB — what is it?
**File:** [`chat_client.py`](file:///C:/Users/Abdul%20Hadi/Cipher/chat_client.py) (73,953 bytes)

There is a 74KB `chat_client.py` at the root that is not imported by any server or Flutter glue code. The project uses Flutter as the client. This file appears to be a legacy tkinter/terminal client that is entirely redundant.

**Fix:** Delete it, or move to a `legacy/` folder if you want to keep it for reference.

---

### [DEAD-2] `pointycastle` imported but RSA is not implemented
**File:** [`encryption_service.dart:2`](file:///C:/Users/Abdul%20Hadi/Cipher/cipher_app/lib/services/encryption_service.dart)

```dart
import 'package:pointycastle/asymmetric/api.dart'; // nothing from this is used
```

The comment says "Phase 4 E2EE" — RSA key exchange is not implemented yet.

**Fix:** Remove the import until RSA is actually implemented. Unused imports slow compile times and inflate the binary.

---

### [DEAD-3] `background` color in `ColorScheme` is deprecated in Flutter Material 3
**File:** [`main.dart:27`](file:///C:/Users/Abdul%20Hadi/Cipher/cipher_app/lib/main.dart)

```dart
colorScheme: const ColorScheme.dark(
  background: Color(0xFF202225),  // deprecated in Flutter 3.18+
),
```

**Fix:**
```dart
colorScheme: const ColorScheme.dark(
  surface: Color(0xFF202225),  // 'surface' replaces 'background'
),
```

---

### [DEAD-4] `bcrypt` not in `requirements.txt`
**File:** [`requirements.txt`](file:///C:/Users/Abdul%20Hadi/Cipher/requirements.txt)

`api/main.py` directly imports `bcrypt`, but `requirements.txt` only lists `passlib[bcrypt]`. If `passlib` is removed (per SEC-2 fix above), `bcrypt` becomes an undeclared dependency.

**Fix:** Add `bcrypt>=4.0.0` to `requirements.txt`.

---

## Fix Priority Order

| # | ID | Impact | Effort |
|---|---|---|---|
| 1 | BUG-1 | Server won't start | 1 line |
| 2 | SEC-1 | Anyone can impersonate any user | Medium |
| 3 | BUG-3 | QR add-friend does nothing | Small |
| 4 | BUG-8 | AES encryption is broken | Small |
| 5 | BUG-4 | Media relay double-sends | 1 line |
| 6 | BUG-6 | Snackbar context crash | 1 line |
| 7 | SEC-2 | Dead import + confusion | 1 line |
| 8 | SEC-4 | Anti-alt bypassed | Small |
| 9 | BUG-7 | Stream leak | 1 line |
| 10 | BUG-5 | Filter logic off | 1 line |
| 11 | SEC-3 | Rate limiter reset on restart | Medium |
| 12 | SEC-5 | Inactive users can log in | 1 line |
| 13 | BUG-9 | Deprecated datetime | 1 line |
| 14 | DEAD-1 | 74KB dead file | Delete |
| 15 | DEAD-2 | Unused import | 1 line |
| 16 | DEAD-3 | Deprecated Flutter API | 1 line |
| 17 | DEAD-4 | Missing dep declaration | 1 line |
