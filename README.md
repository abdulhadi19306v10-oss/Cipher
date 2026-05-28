# 💬 BitChat - Real-Time Chat & VoIP Calling System

BitChat is a premium, lightweight real-time communication application built from the ground up in Python using raw sockets and Tkinter. It implements custom multi-threaded TCP protocols for state management, messaging, and call handshakes, alongside high-performance UDP media relays for low-latency voice and video calls.

---

## 👥 Contributors

| Name | Roll Number |
| :--- | :--- |
| **Abdul Hadi** | 2025(s)-SE-5 |
| **Muhammad Irfan Shoukat** | 2025(s)-SE-4 |
| **Bilal Ahmad** | 2025(s)-SE-23 |

---

## 🚀 Key Features

*   **Real-time Text Messaging**: Seamless instant messaging for private (one-on-one) and group chats.
*   **Dynamic Group Management**: Create, join, leave, or delete chat groups dynamically.
*   **Voice & Video Calls**: P2P-style voice and video calls powered by PyAudio and OpenCV, using UDP transport with MTU optimizations.
*   **Custom Application Protocol**: Reliable packet framing using a 4-byte big-endian length prefix to prevent message boundaries from splitting over TCP.
*   **Modern Tkinter UI**: Custom dark and light modes with smooth transitions, interactive hover states, typing indicators, and message counters.
*   **Desktop Integrations**: Native Windows toast notifications using `win11toast` and audio alerts using `winsound`.
*   **Thread-Safe Networking**: Guarded send/receive socket operations with mutexes to prevent packet interleaving.

---

## 🏗️ Architecture & Protocol Design

BitChat utilizes a hybrid TCP/UDP architecture to balance reliability and speed:

```
                  ┌──────────────────────────────┐
                  │        BitChat Server        │
                  │  (HOST: 0.0.0.0, PORT: 5000) │
                  └──────────────┬───────────────┘
                                 │
            ┌────────────────────┴────────────────────┐
      TCP (Control & Text)                       UDP (A/V Media)
            │                                         │
 ┌──────────▼──────────┐                   ┌──────────▼──────────┐
 │  • Registration     │                   │  • Audio Packets    │
 │  • Text Messaging   │                   │  • Video Frames     │
 │  • Group Management │                   │  • UDP Registration │
 │  • Call Handshakes  │                   │  • Media Relay      │
 └─────────────────────┘                   └─────────────────────┘
```

### 1. TCP Message Framing Protocol
To prevent TCP stream fragmentation (where multiple messages merge or split over the network buffer), BitChat uses a custom message framing mechanism:
*   **Header**: A 4-byte big-endian unsigned integer indicating the length of the payload.
*   **Payload**: A JSON-encoded dictionary representing the message type and contents.

### 2. Low-Latency UDP Media Stream
Voice and video data is streamed over UDP to eliminate the overhead of TCP handshakes and retransmissions:
*   **Audio Optimization**: PyAudio samples at 16kHz in mono (16-bit format). Audio is sliced into small 256-frame chunks, creating packets small enough to bypass ISP router MTU limits and avoid packet fragmentation.
*   **Video Encoding**: OpenCV captures video frames, compresses them as JPEG, encodes them into Base64, and relays them through the server to the destination client.
*   **Echo & Loopback Control**: The UDP server implements hardware-level source validation and loopback blocks, preventing echo feedback loops.

---

## 📂 Project Directory Structure

Here are the key files inside the project workspace:

*   📁 **[chat_server.py](file:///c:/Users/Abdul%20Hadi/Desktop/Uni%20projects/CN/CN%20project/chat_server.py)**: The main multi-threaded TCP & UDP server responsible for client registration, group routing, and UDP media relaying.
*   📁 **[chat_client.py](file:///c:/Users/Abdul%20Hadi/Desktop/Uni%20projects/CN/CN%20project/chat_client.py)**: The desktop client containing the Tkinter GUI, pyaudio recording/playback loop, and opencv camera capture thread.
*   📁 **[requirements.txt](file:///c:/Users/Abdul%20Hadi/Desktop/Uni%20projects/CN/CN%20project/requirements.txt)**: List of third-party python dependencies for audio, video, image rendering, and notifications.
*   📁 **[.gitignore](file:///c:/Users/Abdul%20Hadi/Desktop/Uni%20projects/CN/CN%20project/.gitignore)**: Standard Git configuration for ignoring temporary local files, cache, and server databases.
*   📁 **[run_server.bat](file:///c:/Users/Abdul%20Hadi/Desktop/Uni%20projects/CN/CN%20project/run_server.bat)**: Shortcut batch script to boot up the BitChat server on Windows.
*   📁 **[run_client.bat](file:///c:/Users/Abdul%20Hadi/Desktop/Uni%20projects/CN/CN%20project/run_client.bat)**: Shortcut batch script to launch a client window on Windows.

---

## 🛠️ Getting Started

### 📋 Prerequisites
Make sure you have **Python 3.8+** installed. You will also need a microphone and webcam to utilize voice/video features.

### 1. Install Dependencies
Open your terminal inside the project directory and run:
```bash
pip install -r requirements.txt
```

> [!NOTE]
> On some Linux platforms, you may need to install `portaudio19-dev` before installing PyAudio. On Windows, PyAudio installs directly via pip.

### 2. Running the Server
To start the central server, double-click **`run_server.bat`** or run in your terminal:
```bash
python chat_server.py
```
Upon startup, the server will output its local IP address (e.g., `192.168.1.100`), which client machines can use to connect over LAN/Wi-Fi.

### 3. Running the Client
To launch a new client instance, double-click **`run_client.bat`** or run:
```bash
python chat_client.py
```

---

## 💬 Usage Guide

1.  **Connection Screen**: Enter the Server IP (use `127.0.0.1` if running client and server on the same machine, or the server's local LAN IP if connecting across multiple computers). Choose a unique username and click **Connect**.
2.  **Private Chat**: Select any online user from the sidebar list to start a private conversation.
3.  **Group Chat**: Click the **`+`** icon on the sidebar header to create a new group. Other users can join the group by clicking **`+ Join Group`** in their Groups tab.
4.  **Voice & Video Calls**: Open a private chat window with another user and click **Call** (voice call) or **Video** (video call). The receiver will receive a ringing popup to Accept or Reject.
5.  **Themes**: Click the **`L` / `D`** button in the sidebar header to toggle between Light and Dark themes.

---

## ⚙️ Technical Environment Settings
*   **TCP Control Port**: `5000`
*   **UDP Media Port**: `5000`
*   **Default Audio Sample Rate**: `16000 Hz`
*   **Local Video Stream Resolution**: `320 x 180` (Downscaled to preserve bandwidth)
*   **Remote Video Stream Resolution**: `854 x 480`

lution**: `320 x 180` (Downscaled to preserve bandwidth)
*   **Remote Video Stream Resolution**: `854 x 480`

---

## 👥 Contributors

| Name | Roll Number |
| :--- | :--- |
| **Abdul Hadi** | 2025(s)-SE-5 |
| **Muhammad Irfan Shoukat** | 2025(s)-SE-4 |
| **Bilal Ahmad** | 2025(s)-SE-23 |

