# 💬 Cipher - Secure Worldwide Communication Platform

Cipher is a premium, cross-platform real-time communication application featuring a hybrid modern architecture. Designed with a seamless Discord and WhatsApp fusion UI, it is built to handle highly secure, globally accessible messaging and VoIP calls.

---

## 🚀 Key Features

*   **Cross-Platform UI**: Beautiful, responsive Flutter frontend running natively on Windows, macOS, Android, and iOS.
*   **Discord/WhatsApp Fusion**: Features a left-side server/community navigation bar with clean, modern chat bubbles.
*   **End-to-End Encryption (E2EE)**: Complete privacy using AES-256 and RSA cryptography to ensure messages are completely secure worldwide.
*   **Unique QR Friend System**: Every user receives a unique QR code upon registration. Adding friends is as simple as scanning their code with your device camera.
*   **Advanced Anti-Alt Security**: Strict IP rate-limiting, device fingerprinting, and strict email verification prevent network spam and alternate account abuse.
*   **High-Performance Backend**: A hybrid backend powered by FastAPI (for rapid REST authentication) alongside a custom multi-threaded Python TCP/UDP socket server for zero-latency real-time chat and media relaying.

---

## 🏗️ Architecture Design

Cipher utilizes a split-stack architecture to balance standard web scalability with the raw speed of direct socket connections:

```
                  ┌──────────────────────────────┐
                  │    Cipher Cloud Backend      │
                  │  (FastAPI: 8000, TCP: 5000)  │
                  └──────────────┬───────────────┘
                                 │
             ┌───────────────────┴───────────────────┐
       REST (Auth/QR)                          TCP/UDP (Real-Time)
             │                                       │
  ┌──────────▼──────────┐                 ┌──────────▼──────────┐
  │  • PostgreSQL DB    │                 │  • End-to-End Enc.  │
  │  • User/QR Auth     │                 │  • 4-byte Framing   │
  │  • Anti-Alt System  │                 │  • VoIP/Video Relay │
  └─────────────────────┘                 └─────────────────────┘
```

### 1. The FastAPI Authentication Layer
User registration, login, and friend-adding operations are routed through a modern FastAPI server hooked into a **PostgreSQL** database. This ensures strict relational data integrity and allows for secure `bcrypt` password hashing.

### 2. Custom TCP Message Framing
For real-time chat, the Flutter client opens a raw `dart:io` socket directly to the Python backend. To prevent TCP stream fragmentation across the global internet, Cipher uses a custom message framing mechanism:
*   **Header**: A 4-byte big-endian unsigned integer indicating the length of the payload.
*   **Payload**: An AES-encrypted JSON string containing the message.

---

## 📂 Project Structure

*   📁 **[api/](api/)**: The FastAPI backend containing database configurations, SQLAlchemy models, and REST endpoints.
*   📁 **[cipher_app/](cipher_app/)**: The complete Flutter frontend project, containing the Dart UI, themes, API services, and socket implementations.
*   📁 **[chat_server.py](chat_server.py)**: The legacy multi-threaded TCP & UDP real-time server.
*   📁 **[Dockerfile](Dockerfile)**: Cloud-ready deployment configuration to launch both the API and Socket servers simultaneously.

---

## 🛠️ Getting Started

### 📋 Prerequisites
*   **Backend**: Python 3.11+, PostgreSQL (or SQLite for local testing).
*   **Frontend**: Flutter SDK (3.2.0+).

### 1. Running the Backend
Install the backend dependencies:
```bash
pip install -r requirements.txt
```
Launch the REST API:
```bash
uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
```
Launch the Socket Server (in a new terminal):
```bash
python chat_server.py
```

### 2. Running the Frontend
Navigate into the Flutter project and fetch the dependencies:
```bash
cd cipher_app
flutter pub get
```
Run on Desktop or Mobile:
```bash
flutter run -d windows
# or
flutter run
```
