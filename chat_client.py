#!/usr/bin/env python3
"""
BitChat - Client
Real-time chat with voice/video calls using pyaudio and opencv
"""

import tkinter as tk
from tkinter import ttk, messagebox, filedialog, simpledialog
import socket
import threading
import json
import base64
import os
import io
import struct
import time
from datetime import datetime
from typing import Optional, Dict, List
from PIL import Image, ImageTk
import pyaudio
import cv2
import platform
import queue

try:
    import winsound
except ImportError:
    winsound = None

try:
    import win11toast
except ImportError:
    win11toast = None

import tempfile

# Optional imports for voice/video
PYAUDIO_AVAILABLE = True
OPENCV_AVAILABLE = True
PIL_AVAILABLE = True

DEFAULT_PORT = 5000
BUFFER_SIZE = 65536

# Audio settings
AUDIO_FORMAT = 8  # pyaudio.paInt16 = 8
AUDIO_CHANNELS = 1
AUDIO_RATE = 16000
AUDIO_CHUNK = 256  # 256 frames -> strictly bypasses all restrictive ISP router MTUs natively


class Theme:
    DARK = {
        'bg': '#0f172a', 'bg2': '#1e293b', 'bg3': '#334155',
        'sent': '#3b82f6', 'recv': '#1e293b', 'input': '#1e293b',
        'text': '#f8fafc', 'text2': '#cbd5e1', 'text3': '#94a3b8',
        'accent': '#6366f1', 'hover': '#334155', 'border': '#334155',
        'online': '#10b981', 'offline': '#64748b',
        'accept': '#10b981', 'reject': '#ef4444'
    }
    LIGHT = {
        'bg': '#f8fafc', 'bg2': '#ffffff', 'bg3': '#f1f5f9',
        'sent': '#dbeafe', 'recv': '#ffffff', 'input': '#ffffff',
        'text': '#0f172a', 'text2': '#334155', 'text3': '#64748b',
        'accent': '#4f46e5', 'hover': '#f1f5f9', 'border': '#e2e8f0',
        'online': '#10b981', 'offline': '#94a3b8',
        'accept': '#10b981', 'reject': '#ef4444'
    }


class ChatClient:
    def __init__(self):
        self.socket: Optional[socket.socket] = None
        self.udp_socket: Optional[socket.socket] = None
        self.username: Optional[str] = None
        self.server_host: Optional[str] = None
        self.server_port: int = DEFAULT_PORT
        self.connected = False
        self.current_chat = None
        self.current_chat_type = None
        self.dark_mode = False
        self.theme = Theme.LIGHT
        
        self.users: List[dict] = []
        self.groups: List[dict] = []
        self.messages: Dict[str, List[dict]] = {}
        self.unread_counts: Dict[str, int] = {}
        self.typing_timers: Dict[str, str] = {}
        self.current_tab = 'chats'
        
        # Call state
        self.active_call = None
        self.call_type = None
        self.call_dialog = None
        self.call_running = False
        self.audio_stream_in = None
        self.audio_stream_out = None
        self.pyaudio_instance = None
        self.video_capture = None
        self.video_label = None
        self.remote_video_label = None
        self.accept_btn = None
        self.end_reject_btn = None
        self.call_btn_frame = None
        self.local_video_size = (320, 180)
        self.remote_video_size = (854, 480)
        self.call_window_video_size = "1200x860"
        self.call_window_voice_size = "350x400"
        self.call_window_video_min = (1000, 760)
        self.audio_queue = queue.Queue()
        
        self.send_lock = threading.Lock() # Add a lock for thread-safe sending
        self.setup_gui()
        
    def setup_gui(self):
        self.root = tk.Tk()
        self.root.title("BitChat")
        self.root.geometry("1000x700")
        self.root.minsize(800, 600)
        self.root.configure(bg=self.theme['bg'])
        
        self.root.grid_columnconfigure(0, weight=0, minsize=320)
        self.root.grid_columnconfigure(1, weight=1)
        self.root.grid_rowconfigure(0, weight=1)
        
        self.show_login()
        
    def show_login(self):
        self.login_frame = tk.Frame(self.root, bg=self.theme['bg'])
        self.login_frame.place(relx=0.5, rely=0.5, anchor='center')
        
        # Simple wordmark logo for app branding.
        tk.Label(self.login_frame, text="BitChat", font=('Segoe UI', 30, 'bold'),
                 bg=self.theme['bg'], fg=self.theme['accent']).pack(pady=(0, 30))
        tk.Label(self.login_frame, text="Fast local messaging and calls", font=('Segoe UI', 10),
                 bg=self.theme['bg'], fg=self.theme['text2']).pack(pady=(0, 16))
        
        tk.Label(self.login_frame, text="Server IP:", font=('Segoe UI', 11),
                 bg=self.theme['bg'], fg=self.theme['text2']).pack(anchor='w')
        self.host_entry = tk.Entry(self.login_frame, font=('Segoe UI', 12), width=30,
                                   bg=self.theme['input'], fg=self.theme['text'],
                                   insertbackground=self.theme['text'], relief='flat')
        self.host_entry.insert(0, '127.0.0.1')
        self.host_entry.pack(pady=(5, 15), ipady=8, ipadx=10)
        
        tk.Label(self.login_frame, text="Username:", font=('Segoe UI', 11),
                 bg=self.theme['bg'], fg=self.theme['text2']).pack(anchor='w')
        self.user_entry = tk.Entry(self.login_frame, font=('Segoe UI', 12), width=30,
                                   bg=self.theme['input'], fg=self.theme['text'],
                                   insertbackground=self.theme['text'], relief='flat')
        self.user_entry.pack(pady=(5, 20), ipady=8, ipadx=10)
        self.user_entry.bind('<Return>', lambda e: self.connect())
        
        self.connect_btn = tk.Button(self.login_frame, text="Connect", font=('Segoe UI', 12, 'bold'),
                                     bg=self.theme['accent'], fg='white', relief='flat',
                                     cursor='hand2', command=self.connect, width=20)
        self.connect_btn.pack(pady=10, ipady=8)
        
        self.status_label = tk.Label(self.login_frame, text="", font=('Segoe UI', 10),
                                     bg=self.theme['bg'], fg=self.theme['text2'])
        self.status_label.pack(pady=10)
        
        # Feature availability
        features = []
        if PYAUDIO_AVAILABLE:
            features.append("Voice calls: Ready")
        else:
            features.append("Voice calls: Install pyaudio")
        if OPENCV_AVAILABLE:
            features.append("Video calls: Ready")
        else:
            features.append("Video calls: Install opencv-python")
            
        tk.Label(self.login_frame, text="\n".join(features), font=('Segoe UI', 9),
                 bg=self.theme['bg'], fg=self.theme['text3'], justify='center').pack(pady=20)
        
    def connect(self):
        host = self.host_entry.get().strip() or '127.0.0.1'
        username = self.user_entry.get().strip()
        
        if not username:
            self.status_label.config(text="Please enter a username", fg=self.theme['reject'])
            return
            
        self.connect_btn.config(state='disabled')
        self.status_label.config(text="Connecting...", fg=self.theme['text2'])
        
        threading.Thread(target=self._connect_thread, args=(host, username), daemon=True).start()
        
    def _connect_thread(self, host: str, username: str):
        try:
            self.server_host = host
            self.server_port = DEFAULT_PORT
            
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(10)
            self.socket.connect((host, DEFAULT_PORT))
            self.socket.settimeout(None)
            
            self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024 * 1024)
            self.udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1024 * 1024)
            
            self.send_msg({'type': 'register', 'username': username})
            
            response = self.recv_msg()
            if response and response.get('type') == 'registered':
                self.username = username
                self.connected = True
                
                # Send the initial UDP packet so the server registers our address
                self.udp_send_msg({'type': 'register_udp', 'username': self.username})
                
                self.root.after(0, self.on_connected)
                
                # Start receive threads
                threading.Thread(target=self.receive_loop, daemon=True).start()
                threading.Thread(target=self.udp_receive_loop, daemon=True).start()
            else:
                error = response.get('message', 'Connection failed') if response else 'No response'
                self.root.after(0, lambda: self.on_error(error))
        except Exception as e:
            self.root.after(0, lambda: self.on_error(str(e)))
            
    def on_connected(self):
        self.login_frame.destroy()
        self.create_main_ui()

    def _rebuild_main_ui(self):
        """
        Recreate sidebar + chat area so every widget picks up the new theme colors.
        """
        for attr in ('sidebar', 'chat_panel'):
            widget = getattr(self, attr, None)
            if widget and widget.winfo_exists():
                widget.destroy()
        self.create_main_ui()
        if self.current_chat and self.current_chat_type:
            self.open_chat(self.current_chat, self.current_chat_type)
        else:
            self.show_welcome()
        
    def on_error(self, error: str):
        self.status_label.config(text=error, fg=self.theme['reject'])
        self.connect_btn.config(state='normal')
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
            self.socket = None
            
    def send_msg(self, data: dict) -> bool:
        # Networking basics:
        # 1) Serialize Python dict to bytes (JSON).
        # 2) Prefix with 4-byte big-endian message length.
        # 3) Send atomically under a lock so threads do not interleave packets.
        try:
            msg = json.dumps(data).encode('utf-8')
            with self.send_lock: # Lock the socket during the write operation
                self.socket.sendall(struct.pack('>I', len(msg)) + msg)
            return True
        except:
            return False
            
    def udp_send_msg(self, data: dict) -> bool:
        if not self.udp_socket or not self.server_host:
            return False
        try:
            msg = json.dumps(data).encode('utf-8')
            if len(msg) > 65000:
                print("Warning: UDP packet exceeds safe MTU boundary.")
                return False
            self.udp_socket.sendto(msg, (self.server_host, self.server_port))
            return True
        except Exception as e:
            print(f"UDP send err: {e}")
            return False
            
    def recv_msg(self) -> Optional[dict]:
        # Reverse of send_msg():
        # 1) Read 4-byte length prefix.
        # 2) Read exactly that many bytes.
        # 3) Decode JSON payload.
        try:
            raw_len = b''
            while len(raw_len) < 4:
                chunk = self.socket.recv(4 - len(raw_len))
                if not chunk:
                    return None
                raw_len += chunk
            length = struct.unpack('>I', raw_len)[0]
            data = b''
            while len(data) < length:
                chunk = self.socket.recv(min(BUFFER_SIZE, length - len(data)))
                if not chunk:
                    return None
                data += chunk
            return json.loads(data.decode('utf-8'))
        except:
            return None

    def _chat_key(self, user_a: str, user_b: str) -> str:
        """Create a stable private-chat key regardless of sender order."""
        return '_'.join(sorted([user_a, user_b]))

    def _store_message(self, chat_id: str, msg: dict):
        """Append a message to in-memory history, creating the list when needed."""
        if chat_id not in self.messages:
            self.messages[chat_id] = []
        self.messages[chat_id].append(msg)
            
    def receive_loop(self):
        while self.connected:
            msg = self.recv_msg()
            if not msg:
                self.connected = False
                self.root.after(0, lambda: messagebox.showerror("Disconnected", "Lost connection to server"))
                break
            self.root.after(0, lambda m=msg: self.handle_message(m))
            
    def udp_receive_loop(self):
        while self.connected:
            try:
                data, addr = self.udp_socket.recvfrom(BUFFER_SIZE)
                if not data:
                    continue
                msg = json.loads(data.decode('utf-8'))
                if msg.get('type') == 'call_media':
                    if msg.get('media_type') == 'audio':
                        self.handle_call_media(msg)  # Thread-safe queue bypasses Tkinter bottlenecks!
                    else:
                        self.root.after(0, lambda m=msg: self.handle_call_media(m))
            except OSError as e:
                # Handle WSAECONNRESET (10054) on recvfrom which results from ICMP Port Unreachable.
                if getattr(e, 'winerror', None) == 10054:
                    pass
                else:
                    time.sleep(0.01)
            except Exception as e:
                time.sleep(0.01)
            
    def handle_message(self, msg: dict):
        t = msg.get('type', '')
        # Dispatch table keeps protocol handling concise and easy to extend.
        handlers = {
            'user_list': self._handle_user_list,
            'group_list': self._handle_group_list,
            'private_message': self.handle_private_msg,
            'group_message': self.handle_group_msg,
            'message_sent': self.handle_msg_sent,
            'typing': self.handle_typing,
            'incoming_call': self.handle_incoming_call,
            'call_initiated': self.handle_call_initiated,
            'call_accepted': self.handle_call_accepted,
            'call_connected': self.handle_call_connected,
            'call_rejected': self.handle_call_rejected,
            'call_ended': self.handle_call_ended,
            'call_media': self.handle_call_media,
        }
        handler = handlers.get(t)
        if handler:
            handler(msg)

    def _handle_user_list(self, msg: dict):
        self.users = msg.get('users', [])
        if self.current_tab == 'chats':
            self.refresh_list()

    def _handle_group_list(self, msg: dict):
        self.groups = msg.get('groups', [])
        if self.current_tab == 'groups':
            self.refresh_list()
            
    def handle_private_msg(self, msg: dict):
        sender = msg.get('sender')
        chat_id = self._chat_key(self.username, sender)
        self._store_message(chat_id, msg)
        
        self.play_sound('receive')
        
        if self.current_chat == sender and self.current_chat_type == 'private':
            self.display_message(msg)
            self.scroll_to_bottom()
        else:
            self.unread_counts[sender] = self.unread_counts.get(sender, 0) + 1
            if self.current_tab == 'chats':
                self.refresh_list()
            self.show_notification(f"Message from {sender}", msg.get('content', '')[:50])
            
    def handle_group_msg(self, msg: dict):
        group = msg.get('group')
        self._store_message(group, msg)
        
        if msg.get('sender') != self.username:
            self.play_sound('receive')
        
        if self.current_chat == group and self.current_chat_type == 'group':
            self.display_message(msg)
            self.scroll_to_bottom()
        else:
            self.unread_counts[group] = self.unread_counts.get(group, 0) + 1
            if self.current_tab == 'groups':
                self.refresh_list()
            if msg.get('sender') != self.username:
                self.show_notification(f"{msg.get('sender')} in {group}", msg.get('content', '')[:50])
            
    def handle_msg_sent(self, msg: dict):
        recv = msg.get('receiver')
        group = msg.get('group')
        
        self.play_sound('send')
        
        if recv:
            chat_id = self._chat_key(self.username, recv)
            msg['sender'] = self.username
            self._store_message(chat_id, msg)
            if self.current_chat == recv:
                self.display_message(msg)
                self.scroll_to_bottom()
        elif group:
            msg['sender'] = self.username
            self._store_message(group, msg)
            
    def handle_typing(self, msg: dict):
        sender = msg.get('sender')
        is_typing = msg.get('is_typing', False)
        group = msg.get('group')
        
        if (group and self.current_chat == group) or (not group and self.current_chat == sender):
            try:
                if hasattr(self, 'typing_label') and self.typing_label.winfo_exists():
                    if is_typing:
                        self.typing_label.config(text=f"{sender} is typing...")
                        if sender in self.typing_timers:
                            self.root.after_cancel(self.typing_timers[sender])
                        self.typing_timers[sender] = self.root.after(3000, self.clear_typing)
                    else:
                        self.typing_label.config(text="")
            except:
                pass
                
    def clear_typing(self):
        try:
            if hasattr(self, 'typing_label') and self.typing_label.winfo_exists():
                self.typing_label.config(text="")
        except:
            pass
            
    def play_sound(self, sound_type: str):
        if winsound:
            try:
                # SystemAsterisk for receive, SystemDefault for send (subtle pop)
                sound = "SystemAsterisk" if sound_type == 'receive' else "SystemDefault"
                winsound.PlaySound(sound, winsound.SND_ALIAS | winsound.SND_ASYNC)
            except:
                pass

    def show_notification(self, title: str, message: str):
        if win11toast:
            try:
                threading.Thread(target=win11toast.toast, args=(title, message), kwargs={'app_id': 'BitChat'}, daemon=True).start()
            except:
                self.root.after(0, lambda: self._show_toast(title, message))
        else:
            self.root.after(0, lambda: self._show_toast(title, message))
        
    def _show_toast(self, title: str, message: str):
        toast = tk.Toplevel(self.root)
        toast.overrideredirect(True)
        toast.attributes("-topmost", True)
        toast.configure(bg=self.theme['accent'])
        
        container = tk.Frame(toast, bg=self.theme['accent'], padx=15, pady=10)
        container.pack(fill='both', expand=True)

        tk.Label(container, text=title, font=('Segoe UI', 10, 'bold'), bg=self.theme['accent'], fg='white').pack(anchor='w')
        tk.Label(container, text=message, font=('Segoe UI', 9), bg=self.theme['accent'], fg='white', wraplength=250, justify='left').pack(anchor='w', pady=(2, 0))
        
        toast.update_idletasks()
        w = toast.winfo_width()
        h = toast.winfo_height()
        sw = toast.winfo_screenwidth()
        sh = toast.winfo_screenheight()
        
        x = sw - w - 20
        y = sh - h - 60
        toast.geometry(f"+{x}+{y}")
        
        self.root.after(4000, toast.destroy)
        
    def create_main_ui(self):
        # Left sidebar
        self.sidebar = tk.Frame(self.root, bg=self.theme['bg2'], width=320)
        self.sidebar.grid(row=0, column=0, sticky='nsew')
        self.sidebar.grid_propagate(False)
        
        # Sidebar header
        header = tk.Frame(self.sidebar, bg=self.theme['bg3'], height=60)
        header.pack(fill='x')
        header.pack_propagate(False)
        
        tk.Label(header, text=f"  {self.username}", font=('Segoe UI', 14, 'bold'),
                 bg=self.theme['bg3'], fg=self.theme['text']).pack(side='left', padx=10, pady=15)
        
        # Header buttons
        btn_frame = tk.Frame(header, bg=self.theme['bg3'])
        btn_frame.pack(side='right', padx=5)
        
        tk.Button(btn_frame, text="+" , font=('Segoe UI', 14), bg=self.theme['bg3'],
                  fg=self.theme['text2'], relief='flat', cursor='hand2',
                  command=self.create_group).pack(side='left', padx=2)
        
        self.theme_btn = tk.Button(btn_frame, text="D" if self.dark_mode else "L", font=('Segoe UI', 10, 'bold'),
                                   bg=self.theme['bg3'], fg=self.theme['text2'], relief='flat',
                                   cursor='hand2', command=self.toggle_theme, width=2)
        self.theme_btn.pack(side='left', padx=2)
        
        # Search
        search_frame = tk.Frame(self.sidebar, bg=self.theme['bg2'])
        search_frame.pack(fill='x', padx=10, pady=10)
        
        self.search_var = tk.StringVar()
        self.search_entry = tk.Entry(search_frame, textvariable=self.search_var, font=('Segoe UI', 11),
                                     bg=self.theme['input'], fg=self.theme['text'],
                                     insertbackground=self.theme['text'], relief='flat')
        self.search_entry.pack(fill='x', ipady=8, ipadx=10)
        self.search_entry.insert(0, "Search...")
        self.search_entry.config(fg=self.theme['text3'])
        self.search_entry.bind('<FocusIn>', lambda e: self.on_search_focus(True))
        self.search_entry.bind('<FocusOut>', lambda e: self.on_search_focus(False))
        self.search_var.trace('w', lambda *args: self.refresh_list())
        
        # Tabs
        tabs = tk.Frame(self.sidebar, bg=self.theme['bg2'])
        tabs.pack(fill='x', padx=10, pady=5)
        
        self.chat_tab = tk.Button(tabs, text="Chats", font=('Segoe UI', 11, 'bold'),
                                  bg=self.theme['accent'], fg='white', relief='flat',
                                  cursor='hand2', command=lambda: self.switch_tab('chats'))
        self.chat_tab.pack(side='left', expand=True, fill='x', padx=(0, 5), ipady=8)
        
        self.group_tab = tk.Button(tabs, text="Groups", font=('Segoe UI', 11),
                                   bg=self.theme['bg3'], fg=self.theme['text2'], relief='flat',
                                   cursor='hand2', command=lambda: self.switch_tab('groups'))
        self.group_tab.pack(side='left', expand=True, fill='x', padx=(5, 0), ipady=8)
        
        # List container with scrollbar
        list_container = tk.Frame(self.sidebar, bg=self.theme['bg2'])
        list_container.pack(fill='both', expand=True)
        
        self.list_canvas = tk.Canvas(list_container, bg=self.theme['bg2'], highlightthickness=0)
        scrollbar = ttk.Scrollbar(list_container, orient='vertical', command=self.list_canvas.yview)
        
        self.list_frame = tk.Frame(self.list_canvas, bg=self.theme['bg2'])
        self.list_canvas.create_window((0, 0), window=self.list_frame, anchor='nw', tags='frame')
        self.list_canvas.configure(yscrollcommand=scrollbar.set)
        
        self.list_canvas.pack(side='left', fill='both', expand=True)
        scrollbar.pack(side='right', fill='y')
        
        self.list_frame.bind('<Configure>', lambda e: self.list_canvas.configure(scrollregion=self.list_canvas.bbox('all')))
        self.list_canvas.bind('<Configure>', lambda e: self.list_canvas.itemconfig('frame', width=e.width))
        
        # Mouse wheel scrolling
        self.list_canvas.bind('<Enter>', lambda e: self.list_canvas.bind_all('<MouseWheel>', self.on_mousewheel))
        self.list_canvas.bind('<Leave>', lambda e: self.list_canvas.unbind_all('<MouseWheel>'))
        
        # Right panel (chat area)
        self.chat_panel = tk.Frame(self.root, bg=self.theme['bg'])
        self.chat_panel.grid(row=0, column=1, sticky='nsew')
        
        self.show_welcome()
        self.refresh_list()
        
    def on_mousewheel(self, event):
        self.list_canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")
        
    def on_search_focus(self, focused: bool):
        if focused:
            if self.search_entry.get() == "Search...":
                self.search_entry.delete(0, tk.END)
                self.search_entry.config(fg=self.theme['text'])
        else:
            if not self.search_entry.get():
                self.search_entry.insert(0, "Search...")
                self.search_entry.config(fg=self.theme['text3'])
                
    def switch_tab(self, tab: str):
        self.current_tab = tab
        if tab == 'chats':
            self.chat_tab.config(bg=self.theme['accent'], fg='white', font=('Segoe UI', 11, 'bold'))
            self.group_tab.config(bg=self.theme['bg3'], fg=self.theme['text2'], font=('Segoe UI', 11))
        else:
            self.group_tab.config(bg=self.theme['accent'], fg='white', font=('Segoe UI', 11, 'bold'))
            self.chat_tab.config(bg=self.theme['bg3'], fg=self.theme['text2'], font=('Segoe UI', 11))
        self.refresh_list()
        
    def refresh_list(self):
        for w in self.list_frame.winfo_children():
            w.destroy()
            
        search = self.search_var.get().lower()
        if search == "search...":
            search = ""
            
        if self.current_tab == 'chats':
            shown = 0
            for user in self.users:
                if user['username'] == self.username:
                    continue
                if search and search not in user['username'].lower():
                    continue
                self.create_list_item(user['username'], user.get('status', 'online'), 'private')
                shown += 1
            if shown == 0:
                tk.Label(self.list_frame, text="No users online", font=('Segoe UI', 11),
                         bg=self.theme['bg2'], fg=self.theme['text3']).pack(pady=30)
        else:
            for group in self.groups:
                if search and search not in group['name'].lower():
                    continue
                members = len(group.get('members', []))
                self.create_list_item(group['name'], f"{members} members", 'group')
                
            tk.Button(self.list_frame, text="+ Join Group", font=('Segoe UI', 11),
                      bg=self.theme['bg3'], fg=self.theme['accent'], relief='flat',
                      cursor='hand2', command=self.join_group).pack(fill='x', padx=10, pady=15, ipady=10)
                      
    def create_list_item(self, name: str, status: str, item_type: str):
        item = tk.Frame(self.list_frame, bg=self.theme['bg2'], cursor='hand2')
        item.pack(fill='x', pady=1)
        
        inner = tk.Frame(item, bg=self.theme['bg2'])
        inner.pack(fill='x', padx=10, pady=8)
        
        # Avatar circle
        avatar = tk.Label(inner, text=name[0].upper(), font=('Segoe UI', 14, 'bold'),
                          bg=self.theme['accent'], fg='white', width=3, height=1)
        avatar.pack(side='left', padx=(5, 15))
        
        # Text
        text_frame = tk.Frame(inner, bg=self.theme['bg2'])
        text_frame.pack(side='left', fill='x', expand=True)
        
        unread = self.unread_counts.get(name, 0)
        display_name = f"({unread}) {name}" if unread > 0 else name
        
        tk.Label(text_frame, text=display_name, font=('Segoe UI', 12), bg=self.theme['bg2'],
                 fg=self.theme['text'], anchor='w').pack(fill='x')
        
        status_color = self.theme['online'] if status == 'online' else self.theme['text3']
        tk.Label(text_frame, text=status, font=('Segoe UI', 10), bg=self.theme['bg2'],
                 fg=status_color, anchor='w').pack(fill='x')
        
        # Bind click
        for widget in [item, inner, avatar, text_frame] + text_frame.winfo_children():
            widget.bind('<Button-1>', lambda e, n=name, t=item_type: self.open_chat(n, t))
            widget.bind('<Enter>', lambda e, i=item, inn=inner: self.on_item_hover(i, inn, True))
            widget.bind('<Leave>', lambda e, i=item, inn=inner: self.on_item_hover(i, inn, False))
            
    def on_item_hover(self, item: tk.Frame, inner: tk.Frame, enter: bool):
        color = self.theme['hover'] if enter else self.theme['bg2']
        item.config(bg=color)
        inner.config(bg=color)
        for w in inner.winfo_children():
            try:
                if isinstance(w, tk.Frame):
                    w.config(bg=color)
                    for c in w.winfo_children():
                        if not isinstance(c, tk.Button):
                            c.config(bg=color)
                elif not isinstance(w, tk.Button) and w.cget('bg') != self.theme['accent']:
                    w.config(bg=color)
            except:
                pass
                
    def show_welcome(self):
        for w in self.chat_panel.winfo_children():
            w.destroy()
            
        welcome = tk.Frame(self.chat_panel, bg=self.theme['bg'])
        welcome.place(relx=0.5, rely=0.5, anchor='center')
        
        tk.Label(welcome, text="BitChat", font=('Segoe UI', 34, 'bold'),
                 bg=self.theme['bg'], fg=self.theme['accent']).pack()
        tk.Label(welcome, text="Select a chat to start messaging", font=('Segoe UI', 12),
                 bg=self.theme['bg'], fg=self.theme['text2']).pack(pady=10)
                 
    def open_chat(self, name: str, chat_type: str):
        self.current_chat = name
        self.current_chat_type = chat_type
        
        if name in self.unread_counts and self.unread_counts[name] > 0:
            self.unread_counts[name] = 0
            self.refresh_list()
            
        for w in self.chat_panel.winfo_children():
            w.destroy()
            
        # Chat header
        header = tk.Frame(self.chat_panel, bg=self.theme['bg3'], height=60)
        header.pack(fill='x')
        header.pack_propagate(False)
        
        tk.Label(header, text=f"  {name}", font=('Segoe UI', 14, 'bold'),
                 bg=self.theme['bg3'], fg=self.theme['text']).pack(side='left', padx=10, pady=15)
        
        # Call buttons
        if chat_type == 'private':
            btn_frame = tk.Frame(header, bg=self.theme['bg3'])
            btn_frame.pack(side='right', padx=15)
            
            tk.Button(btn_frame, text="Call", font=('Segoe UI', 10), bg=self.theme['accent'],
                      fg='white', relief='flat', cursor='hand2',
                      command=lambda: self.start_call('voice')).pack(side='left', padx=5, ipadx=10, ipady=3)
            
            tk.Button(btn_frame, text="Video", font=('Segoe UI', 10), bg=self.theme['accent'],
                      fg='white', relief='flat', cursor='hand2',
                      command=lambda: self.start_call('video')).pack(side='left', padx=5, ipadx=10, ipady=3)
        else:
            # Group actions
            btn_frame = tk.Frame(header, bg=self.theme['bg3'])
            btn_frame.pack(side='right', padx=15)
            
            tk.Button(btn_frame, text="Leave", font=('Segoe UI', 10), bg=self.theme['reject'],
                      fg='white', relief='flat', cursor='hand2',
                      command=self.leave_current_group).pack(side='left', padx=5, ipadx=10, ipady=3)
            

        # Typing indicator
        self.typing_label = tk.Label(self.chat_panel, text="", font=('Segoe UI', 10, 'italic'),
                                     bg=self.theme['bg'], fg=self.theme['text3'])
        self.typing_label.pack(fill='x', padx=20)
        
        # Messages area
        msg_container = tk.Frame(self.chat_panel, bg=self.theme['bg'])
        msg_container.pack(fill='both', expand=True)
        
        self.msg_canvas = tk.Canvas(msg_container, bg=self.theme['bg'], highlightthickness=0)
        scrollbar = ttk.Scrollbar(msg_container, orient='vertical', command=self.msg_canvas.yview)
        
        self.msg_frame = tk.Frame(self.msg_canvas, bg=self.theme['bg'])
        self.msg_canvas.create_window((0, 0), window=self.msg_frame, anchor='nw', tags='msg_frame')
        self.msg_canvas.configure(yscrollcommand=scrollbar.set)
        
        self.msg_canvas.pack(side='left', fill='both', expand=True)
        scrollbar.pack(side='right', fill='y')
        
        self.msg_frame.bind('<Configure>', lambda e: self.msg_canvas.configure(scrollregion=self.msg_canvas.bbox('all')))
        self.msg_canvas.bind('<Configure>', lambda e: self.msg_canvas.itemconfig('msg_frame', width=e.width))
        
        # Input area
        input_frame = tk.Frame(self.chat_panel, bg=self.theme['bg3'], height=60)
        input_frame.pack(fill='x', side='bottom')
        input_frame.pack_propagate(False)
        
        tk.Button(input_frame, text="@", font=('Segoe UI', 16), bg=self.theme['bg3'],
                  fg=self.theme['text2'], relief='flat', cursor='hand2',
                  command=self.send_file).pack(side='left', padx=10)
        
        self.msg_entry = tk.Entry(input_frame, font=('Segoe UI', 12), bg=self.theme['input'],
                                  fg=self.theme['text'], insertbackground=self.theme['text'], relief='flat')
        self.msg_entry.pack(side='left', fill='x', expand=True, padx=10, ipady=10)
        self.msg_entry.bind('<Return>', lambda e: self.send_text())
        self.msg_entry.bind('<KeyRelease>', self.on_typing)
        
        tk.Button(input_frame, text=">", font=('Segoe UI', 16, 'bold'), bg=self.theme['accent'],
                  fg='white', relief='flat', cursor='hand2', width=3,
                  command=self.send_text).pack(side='right', padx=10, pady=10)
        
        # Load existing messages
        self.load_messages()
        
    def load_messages(self):
        if self.current_chat_type == 'private':
            chat_id = '_'.join(sorted([self.username, self.current_chat]))
        else:
            chat_id = self.current_chat
            
        if chat_id in self.messages:
            for msg in self.messages[chat_id]:
                self.display_message(msg)
        self.scroll_to_bottom()
        
    def display_message(self, msg: dict):
        sender = msg.get('sender', '')
        content = msg.get('content', '')
        timestamp = msg.get('timestamp', '')
        content_type = msg.get('content_type', 'text')
        is_own = sender == self.username
        
        container = tk.Frame(self.msg_frame, bg=self.theme['bg'])
        container.pack(fill='x', padx=20, pady=3)
        
        bubble_bg = self.theme['sent'] if is_own else self.theme['recv']
        anchor = 'e' if is_own else 'w'
        
        bubble = tk.Frame(container, bg=bubble_bg)
        bubble.pack(anchor=anchor, padx=10)
        
        # Sender name for groups
        if self.current_chat_type == 'group' and not is_own:
            tk.Label(bubble, text=sender, font=('Segoe UI', 9, 'bold'), bg=bubble_bg,
                     fg=self.theme['accent']).pack(anchor='w', padx=10, pady=(5, 0))
        
        # Forwarded label
        if msg.get('forwarded'):
            tk.Label(bubble, text="Forwarded", font=('Segoe UI', 8, 'italic'), bg=bubble_bg,
                     fg=self.theme['text3']).pack(anchor='w', padx=10)
        
        # Content
        if content_type == 'text':
            tk.Label(bubble, text=content, font=('Segoe UI', 11), bg=bubble_bg,
                     fg=self.theme['text'], wraplength=350, justify='left').pack(padx=10, pady=5, anchor='w')
        else:
            icon = {'image': '[Image]', 'video': '[Video]', 'file': '[File]'}.get(content_type, '[File]')
            filename = msg.get('filename', 'file')
            
            file_frame = tk.Frame(bubble, bg=bubble_bg)
            file_frame.pack(padx=10, pady=5)
            
            if content_type in ('image', 'video') and msg.get('file_data'):
                try:
                    img = None
                    file_bytes = base64.b64decode(msg['file_data'])
                    if content_type == 'image':
                        img = Image.open(io.BytesIO(file_bytes))
                    elif content_type == 'video' and cv2:
                        fd, temp_path = tempfile.mkstemp(suffix='.mp4')
                        with open(fd, 'wb') as f:
                            f.write(file_bytes)
                        cap = cv2.VideoCapture(temp_path)
                        ret, frame = cap.read()
                        cap.release()
                        os.remove(temp_path)
                        if ret:
                            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                            img = Image.fromarray(frame_rgb)

                    if img:
                        img.thumbnail((250, 250), Image.Resampling.LANCZOS)
                        photo = ImageTk.PhotoImage(img)
                        
                        img_label = tk.Label(file_frame, image=photo, bg=bubble_bg)
                        img_label.image = photo  # Keep reference so it's not garbage collected
                        img_label.pack(pady=(0, 5))
                        
                        if not is_own:
                            img_label.configure(cursor='hand2')
                            img_label.bind('<Button-1>', lambda e, m=msg: self.save_file(m))
                except Exception as e:
                    print(f"Failed to display media inline: {e}")
            
            tk.Label(file_frame, text=f"{icon} {filename}", font=('Segoe UI', 10), bg=bubble_bg,
                     fg=self.theme['text']).pack(side='left')
            
            if not is_own and msg.get('file_data'):
                tk.Button(file_frame, text="Save", font=('Segoe UI', 9), bg=self.theme['accent'],
                          fg='white', relief='flat', cursor='hand2',
                          command=lambda m=msg: self.save_file(m)).pack(side='left', padx=5)
        
        # Timestamp
        tk.Label(bubble, text=timestamp, font=('Segoe UI', 8), bg=bubble_bg,
                 fg=self.theme['text3']).pack(anchor='e', padx=10, pady=(0, 5))
        
        # Context menu
        bubble.bind('<Button-3>', lambda e, m=msg: self.show_context_menu(e, m))
        
    def scroll_to_bottom(self):
        self.msg_canvas.update_idletasks()
        self.msg_canvas.yview_moveto(1.0)
        
    def on_typing(self, event):
        if self.current_chat:
            data = {'type': 'typing', 'is_typing': True}
            if self.current_chat_type == 'group':
                data['group'] = self.current_chat
            else:
                data['receiver'] = self.current_chat
            self.send_msg(data)
            
    def send_text(self):
        content = self.msg_entry.get().strip()
        if not content or not self.current_chat:
            return
            
        if self.current_chat_type == 'group':
            self.send_msg({
                'type': 'group_message', 'group': self.current_chat,
                'content': content, 'content_type': 'text'
            })
        else:
            self.send_msg({
                'type': 'private_message', 'receiver': self.current_chat,
                'content': content, 'content_type': 'text'
            })
            
        self.msg_entry.delete(0, tk.END)
        
    def send_file(self):
        filepath = filedialog.askopenfilename(
            filetypes=[("All Files", "*.*"), ("Images", "*.png *.jpg *.jpeg *.gif"),
                       ("Videos", "*.mp4 *.avi *.mov"), ("Documents", "*.pdf *.doc *.docx")]
        )
        if not filepath:
            return
            
        try:
            with open(filepath, 'rb') as f:
                data = base64.b64encode(f.read()).decode('utf-8')
                
            filename = os.path.basename(filepath)
            ext = filename.lower().split('.')[-1]
            
            if ext in ['png', 'jpg', 'jpeg', 'gif', 'bmp']:
                content_type = 'image'
            elif ext in ['mp4', 'avi', 'mov', 'mkv']:
                content_type = 'video'
            else:
                content_type = 'file'

            if not self._show_file_preview_dialog(filepath, filename, content_type):
                return
                
            msg = {
                'content': f"[{content_type.title()}: {filename}]",
                'content_type': content_type,
                'filename': filename,
                'file_data': data
            }
            
            if self.current_chat_type == 'group':
                msg['type'] = 'group_message'
                msg['group'] = self.current_chat
            else:
                msg['type'] = 'private_message'
                msg['receiver'] = self.current_chat
                
            self.send_msg(msg)
        except Exception as e:
            messagebox.showerror("Error", f"Failed to send file: {e}")

    def _show_file_preview_dialog(self, filepath: str, filename: str, content_type: str) -> bool:
        """
        Show a quick pre-send preview so users can confirm file selection.
        Returns True when user confirms send, otherwise False.
        """
        dialog = tk.Toplevel(self.root)
        dialog.title("Preview File")
        dialog.geometry("420x420")
        dialog.configure(bg=self.theme['bg'])
        dialog.transient(self.root)
        dialog.grab_set()

        state = {'send': False}

        tk.Label(dialog, text="File Preview", font=('Segoe UI', 14, 'bold'),
                 bg=self.theme['bg'], fg=self.theme['text']).pack(pady=(14, 6))
        tk.Label(dialog, text=filename, font=('Segoe UI', 10),
                 bg=self.theme['bg'], fg=self.theme['text2'], wraplength=360).pack(pady=(0, 10))

        preview_frame = tk.Frame(dialog, bg=self.theme['bg2'])
        preview_frame.pack(fill='both', expand=True, padx=20, pady=10)

        rendered_preview = False
        if content_type in ('image', 'video') and PIL_AVAILABLE:
            try:
                if content_type == 'image':
                    img = Image.open(filepath)
                else:
                    cap = cv2.VideoCapture(filepath)
                    ok, frame = cap.read()
                    cap.release()
                    if not ok:
                        frame = None
                    if frame is not None:
                        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                        img = Image.fromarray(frame)
                    else:
                        img = None

                if img is not None:
                    img.thumbnail((340, 240))
                    preview_img = ImageTk.PhotoImage(img)
                    label = tk.Label(preview_frame, image=preview_img, bg=self.theme['bg2'])
                    label.image = preview_img
                    label.pack(pady=12)
                    rendered_preview = True
            except Exception:
                rendered_preview = False

        if not rendered_preview:
            preview_text = {
                'image': 'Image preview unavailable',
                'video': 'Video preview unavailable',
                'file': 'No preview for this file type',
            }.get(content_type, 'No preview available')
            tk.Label(preview_frame, text=preview_text, font=('Segoe UI', 11),
                     bg=self.theme['bg2'], fg=self.theme['text2']).pack(expand=True)

        tk.Label(preview_frame, text=f"Type: {content_type.upper()}",
                 font=('Segoe UI', 10, 'bold'), bg=self.theme['bg2'], fg=self.theme['text']).pack(pady=(0, 12))

        actions = tk.Frame(dialog, bg=self.theme['bg'])
        actions.pack(fill='x', padx=20, pady=(0, 16))

        def confirm_send():
            state['send'] = True
            dialog.destroy()

        tk.Button(actions, text="Cancel", font=('Segoe UI', 10),
                  bg=self.theme['bg3'], fg=self.theme['text'], relief='flat',
                  command=dialog.destroy).pack(side='right', padx=6, ipadx=10, ipady=6)
        tk.Button(actions, text="Send", font=('Segoe UI', 10, 'bold'),
                  bg=self.theme['accent'], fg='white', relief='flat',
                  command=confirm_send).pack(side='right', padx=6, ipadx=12, ipady=6)

        dialog.wait_window()
        return state['send']
            
    def save_file(self, msg: dict):
        filename = msg.get('filename', 'file')
        file_data = msg.get('file_data')
        
        if not file_data:
            return
            
        save_path = filedialog.asksaveasfilename(initialfile=filename)
        if save_path:
            try:
                with open(save_path, 'wb') as f:
                    f.write(base64.b64decode(file_data))
                messagebox.showinfo("Saved", f"File saved to {save_path}")
            except Exception as e:
                messagebox.showerror("Error", f"Failed to save file: {e}")
                
    def show_context_menu(self, event, msg: dict):
        menu = tk.Menu(self.root, tearoff=0)
        menu.add_command(label="Forward", command=lambda: self.forward_message(msg))
        menu.add_command(label="Copy", command=lambda: self.copy_message(msg))
        menu.tk_popup(event.x_root, event.y_root)
        
    def forward_message(self, msg: dict):
        dialog = tk.Toplevel(self.root)
        dialog.title("Forward Message")
        dialog.geometry("300x400")
        dialog.configure(bg=self.theme['bg'])
        dialog.transient(self.root)
        dialog.grab_set()
        
        tk.Label(dialog, text="Forward to:", font=('Segoe UI', 12, 'bold'),
                 bg=self.theme['bg'], fg=self.theme['text']).pack(pady=10)
        
        listbox = tk.Listbox(dialog, font=('Segoe UI', 11), bg=self.theme['bg2'],
                             fg=self.theme['text'], selectbackground=self.theme['accent'])
        listbox.pack(fill='both', expand=True, padx=20, pady=10)
        
        targets = []
        for user in self.users:
            if user['username'] != self.username:
                listbox.insert(tk.END, f"[User] {user['username']}")
                targets.append(('private', user['username']))
        for group in self.groups:
            listbox.insert(tk.END, f"[Group] {group['name']}")
            targets.append(('group', group['name']))
            
        def do_forward():
            sel = listbox.curselection()
            if sel:
                target_type, target = targets[sel[0]]
                self.send_msg({
                    'type': 'forward_message',
                    'target': target,
                    'target_type': target_type,
                    'content': msg.get('content'),
                    'content_type': msg.get('content_type', 'text'),
                    'filename': msg.get('filename'),
                    'file_data': msg.get('file_data')
                })
                dialog.destroy()
                
        tk.Button(dialog, text="Forward", font=('Segoe UI', 11), bg=self.theme['accent'],
                  fg='white', relief='flat', cursor='hand2', command=do_forward).pack(pady=10)
                  
    def copy_message(self, msg: dict):
        self.root.clipboard_clear()
        self.root.clipboard_append(msg.get('content', ''))
        
    def create_group(self):
        name = simpledialog.askstring("Create Group", "Enter group name:", parent=self.root)
        if name:
            self.send_msg({'type': 'create_group', 'name': name.strip()})
            
    def join_group(self):
        name = simpledialog.askstring("Join Group", "Enter group name:", parent=self.root)
        if name:
            self.send_msg({'type': 'join_group', 'group': name.strip()})
            
    def leave_current_group(self):
        if self.current_chat and self.current_chat_type == 'group':
            if messagebox.askyesno("Leave Group", f"Leave {self.current_chat}?"):
                self.send_msg({'type': 'leave_group', 'group': self.current_chat})
                self.show_welcome()
                
    def toggle_theme(self):
        self.dark_mode = not self.dark_mode
        self.theme = Theme.DARK if self.dark_mode else Theme.LIGHT
        self.root.configure(bg=self.theme['bg'])
        self._rebuild_main_ui()
            
    # ==================== CALL FUNCTIONALITY ====================
    
    def start_call(self, call_type: str):
        if not self.current_chat or self.current_chat_type == 'group':
            return
            
        if call_type == 'voice' and not PYAUDIO_AVAILABLE:
            messagebox.showwarning("Voice Call", "Voice calls require pyaudio.\nInstall with: pip install pyaudio")
            return
            
        if call_type == 'video' and not OPENCV_AVAILABLE:
            messagebox.showwarning("Video Call", "Video calls require opencv-python.\nInstall with: pip install opencv-python")
            return
            
        self.call_type = call_type
        self.send_msg({'type': f'{call_type}_call', 'receiver': self.current_chat})
        self.show_call_dialog(self.current_chat, call_type, incoming=False)
        
    def handle_incoming_call(self, msg: dict):
        call_id = msg.get('call_id')
        caller = msg.get('caller')
        call_type = msg.get('call_type')
        group = msg.get('group')
        
        self.active_call = call_id
        self.call_type = call_type
        title = f"{caller} in {group}" if group else caller
        self.show_call_dialog(title, call_type, incoming=True, call_id=call_id)
        
    def show_call_dialog(self, other_user: str, call_type: str, incoming: bool = False, call_id: str = None):
        """Build and display the voice/video call window UI."""
        # Close an older dialog instance first so we never stack multiple call windows.
        if self.call_dialog:
            try:
                self.call_dialog.destroy()
            except:
                pass
        self.accept_btn = None
        self.end_reject_btn = None
        self.call_btn_frame = None

        self.call_dialog = tk.Toplevel(self.root)
        self.call_dialog.title(f"BitChat - {call_type.title()} Call")
        self.call_dialog.geometry(self.call_window_video_size if call_type == 'video' else self.call_window_voice_size)
        if call_type == 'video':
            self.call_dialog.minsize(*self.call_window_video_min)
        self.call_dialog.configure(bg=self.theme['bg'])
        self.call_dialog.transient(self.root)
        self.call_dialog.protocol("WM_DELETE_WINDOW", self.end_call)

        if call_type == 'video':
            self._calculate_video_sizes_for_screen()
            # Footer is fixed-height to guarantee action button visibility.
            footer_frame = self._build_call_footer(other_user, incoming, call_id, fixed_height=170)
            self._build_video_panels()
        else:
            # Voice calls use a compact layout without the video panel section.
            self._build_call_footer(other_user, incoming, call_id, fixed_height=None)

    def _calculate_video_sizes_for_screen(self):
        """Compute balanced local/remote preview sizes based on current display height."""
        # Reserve space for title, status, timer, buttons, and paddings.
        screen_h = self.root.winfo_screenheight()
        max_remote_h = max(320, min(480, screen_h - 360))
        max_local_h = max(140, min(220, int(max_remote_h * 0.4)))
        # Keep a 16:9 aspect ratio so video does not look stretched.
        self.remote_video_size = (int(max_remote_h * 16 / 9), max_remote_h)
        self.local_video_size = (int(max_local_h * 16 / 9), max_local_h)

    def _build_call_footer(self, other_user: str, incoming: bool, call_id: Optional[str], fixed_height: Optional[int] = None):
        """Create the call metadata and control area (name, status, timer, buttons)."""
        # Footer parent: fixed for video calls, natural height for voice calls.
        if fixed_height is not None:
            footer_frame = tk.Frame(self.call_dialog, bg=self.theme['bg'], height=fixed_height)
            footer_frame.pack(side='bottom', fill='x')
            footer_frame.pack_propagate(False)
            info_pad_y = (8, 2)
            timer_pad_y = 4
            btn_pad_y = (8, 10)
        else:
            footer_frame = tk.Frame(self.call_dialog, bg=self.theme['bg'])
            footer_frame.pack(fill='x', pady=(16, 10))
            info_pad_y = (0, 0)
            timer_pad_y = 8
            btn_pad_y = (10, 10)

        info_panel = tk.Frame(footer_frame, bg=self.theme['bg'])
        info_panel.pack(fill='x', pady=info_pad_y)

        tk.Label(
            info_panel,
            text=other_user,
            font=('Segoe UI', 20, 'bold'),
            bg=self.theme['bg'],
            fg=self.theme['text'],
        ).pack()

        status_text = "Incoming call..." if incoming else "Calling..."
        self.call_status = tk.Label(
            info_panel,
            text=status_text,
            font=('Segoe UI', 12),
            bg=self.theme['bg'],
            fg=self.theme['text2'],
        )
        self.call_status.pack()

        self.call_timer_label = tk.Label(
            info_panel,
            text="",
            font=('Segoe UI', 14, 'bold'),
            bg=self.theme['bg'],
            fg=self.theme['accent'],
        )
        self.call_timer_label.pack(pady=timer_pad_y)

        self.call_btn_frame = tk.Frame(footer_frame, bg=self.theme['bg'])
        self.call_btn_frame.pack(fill='x', pady=btn_pad_y)

        if incoming:
            self.accept_btn = self._create_call_action_button(
                parent=self.call_btn_frame,
                text="Accept",
                bg_color=self.theme['accept'],
                command=lambda: self.accept_call(call_id),
            )
            self.accept_btn.pack(side='left', expand=True, padx=24, ipady=12)

        action_text = "Reject" if incoming else "End"
        action_cmd = (lambda: self.reject_call(call_id)) if incoming else self.end_call
        self.end_reject_btn = self._create_call_action_button(
            parent=self.call_btn_frame,
            text=action_text,
            bg_color=self.theme['reject'],
            command=action_cmd,
        )
        self.end_reject_btn.pack(side='left', expand=True, padx=24, ipady=12)
        return footer_frame

    def _create_call_action_button(self, parent, text: str, bg_color: str, command):
        """Return a consistently styled call action button."""
        return tk.Button(
            parent,
            text=text,
            font=('Segoe UI', 13, 'bold'),
            bg=bg_color,
            fg='white',
            relief='flat',
            cursor='hand2',
            width=14,
            bd=0,
            command=command,
        )

    def _build_video_panels(self):
        """Create remote and local preview containers for video calls."""
        # Video area can expand freely because the footer now has fixed reserved space.
        self.video_frame = tk.Frame(self.call_dialog, bg=self.theme['bg'])
        self.video_frame.pack(fill='both', expand=True, padx=20, pady=10)

        self.remote_video_container = tk.Frame(
            self.video_frame,
            bg='#222',
            width=self.remote_video_size[0],
            height=self.remote_video_size[1],
            relief='flat',
        )
        self.remote_video_container.pack(pady=(0, 8))
        self.remote_video_container.pack_propagate(False)

        self.remote_video_label = tk.Label(self.remote_video_container, bg='black')
        self.remote_video_label.pack(fill='both', expand=True)

        self.local_video_container = tk.Frame(
            self.video_frame,
            bg='#111',
            width=self.local_video_size[0],
            height=self.local_video_size[1],
            relief='flat',
        )
        self.local_video_container.pack(anchor='e')
        self.local_video_container.pack_propagate(False)

        self.local_video_label = tk.Label(self.local_video_container, bg='black')
        self.local_video_label.pack(fill='both', expand=True)
                  
    def accept_call(self, call_id: str):
        self.active_call = call_id
        self.send_msg({'type': 'call_response', 'call_id': call_id, 'response': 'accept'})
        self.start_media_streams()
        
    def reject_call(self, call_id: str):
        self.send_msg({'type': 'call_response', 'call_id': call_id, 'response': 'reject'})
        self.close_call_dialog()
        
    def handle_call_initiated(self, msg: dict):
        """Server confirmed the outgoing call — store call_id early for the caller."""
        self.active_call = msg.get('call_id')

    def handle_call_accepted(self, msg: dict):
        self.active_call = msg.get('call_id')
        self.start_media_streams()
        
    def handle_call_connected(self, msg: dict):
        try:
            if self.call_status and self.call_status.winfo_exists():
                self.call_status.config(text="Connected")
        except:
            pass
        self.start_call_timer()
        
    def handle_call_rejected(self, msg: dict):
        messagebox.showinfo("Call Rejected", "The call was rejected")
        self.close_call_dialog()
        
    def handle_call_ended(self, msg: dict):
        self.stop_media_streams()
        self.close_call_dialog()
        
    def handle_call_media(self, msg: dict):
        media_type = msg.get('media_type')
        data = msg.get('data')
        
        if not data:
            return
            
        try:
            if media_type == 'audio' and PYAUDIO_AVAILABLE:
                if msg.get('sender') == self.username:
                    return  # Hard-block any impossible software reflections
                audio_data = base64.b64decode(data)
                self.audio_queue.put(audio_data)
                # Diagnostic counter — prints on first packet then every 50
                self._audio_recv_count = getattr(self, '_audio_recv_count', 0) + 1
                if self._audio_recv_count == 1 or self._audio_recv_count % 50 == 0:
                    print(f"[RECV] Audio packets in queue: {self._audio_recv_count} (qsize={self.audio_queue.qsize()})")

            elif media_type == 'video_chunk' and OPENCV_AVAILABLE and PIL_AVAILABLE:
                if msg.get('sender') == self.username:
                    return  # Hard-block software reflection

                frame_id = msg.get('frame_id')
                chunk_idx = msg.get('chunk_idx')
                total_chunks = msg.get('total_chunks')
                
                if not hasattr(self, 'video_buffers'):
                    self.video_buffers = {}
                    
                if frame_id not in self.video_buffers:
                    self.video_buffers[frame_id] = {}
                    # Garage collect old frames to prevent memory leaks
                    old_keys = [k for k in self.video_buffers if k < frame_id - 5000]
                    for k in old_keys:
                        del self.video_buffers[k]
                        
                self.video_buffers[frame_id][chunk_idx] = data
                
                if len(self.video_buffers[frame_id]) == total_chunks:
                    # Frame complete, assemble and render
                    full_encoded = "".join([self.video_buffers[frame_id][i] for i in range(total_chunks)])
                    del self.video_buffers[frame_id]
                    
                    video_data = base64.b64decode(full_encoded)
                    import numpy as np
                    nparr = np.frombuffer(video_data, np.uint8)
                    frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                    if frame is not None:
                        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                        frame = cv2.resize(frame, self.remote_video_size)
                        img = Image.fromarray(frame)
                        imgtk = ImageTk.PhotoImage(image=img)
    
                        def update_remote_preview(image_tk=imgtk):
                            if self.remote_video_label and self.remote_video_label.winfo_exists():
                                self.remote_video_label.imgtk = image_tk
                                self.remote_video_label.config(image=image_tk)
    
                        self.root.after(0, update_remote_preview)

        except Exception as e:
            print(f"Media error: {e}")
            
    def _open_audio_stream(self, is_input: bool):
        """
        Try to open a PyAudio stream using the default device first.
        If that fails (e.g., Windows exclusive mode lock), enumerate every
        device and return the first one that works.
        Returns the open stream, or None if every device fails.
        """
        pa = self.pyaudio_instance
        mode = 'input' if is_input else 'output'
        channel_key = 'maxInputChannels' if is_input else 'maxOutputChannels'
        open_kwargs = dict(
            format=pyaudio.paInt16,
            channels=AUDIO_CHANNELS,
            rate=AUDIO_RATE,
            frames_per_buffer=AUDIO_CHUNK,
        )
        if is_input:
            open_kwargs['input'] = True
        else:
            open_kwargs['output'] = True

        # 1. Try the system default first
        try:
            stream = pa.open(**open_kwargs)
            print(f"[Audio] Opened default {mode} device OK")
            return stream
        except Exception as e:
            print(f"[Audio] Default {mode} device failed: {e}  — trying all devices...")

        # 2. Fall back to enumerating every device
        for i in range(pa.get_device_count()):
            try:
                info = pa.get_device_info_by_index(i)
                if info.get(channel_key, 0) < 1:
                    continue
                kw = dict(open_kwargs)
                if is_input:
                    kw['input_device_index'] = i
                else:
                    kw['output_device_index'] = i
                stream = pa.open(**kw)
                print(f"[Audio] Opened {mode} device #{i}: {info['name']}")
                return stream
            except Exception:
                continue

        print(f"[Audio] ERROR: no usable {mode} device found on this machine.")
        return None

    def audio_playback_loop(self):
        stream_out = None
        try:
            if PYAUDIO_AVAILABLE and self.pyaudio_instance:
                stream_out = self._open_audio_stream(is_input=False)

            if stream_out is None:
                print("[Audio] Playback stream could not be opened — audio will be silent.")

            _play_count = 0
            while self.call_running:
                try:
                    audio_data = self.audio_queue.get(timeout=0.5)
                    if stream_out:
                        try:
                            stream_out.write(audio_data)
                            _play_count += 1
                            if _play_count == 1 or _play_count % 100 == 0:
                                print(f"[PLAY] Written {_play_count} audio packets to speaker")
                        except OSError as oe:
                            print(f"[PLAY] OSError on write: {oe} — reopening stream")
                            try: stream_out.close()
                            except: pass
                            stream_out = self._open_audio_stream(is_input=False)
                        except Exception as we:
                            print(f"[PLAY] Write error: {we}")
                    else:
                        if _play_count == 0:
                            print("[PLAY] WARNING: got audio data but stream_out is None!")
                except queue.Empty:
                    continue
                except Exception as e:
                    print(f"[PLAY] Unexpected error: {e}")
        finally:
            if stream_out:
                try:
                    stream_out.stop_stream()
                    stream_out.close()
                except: pass

    def start_media_streams(self):
        self.call_running = True
        
        try:
            if self.call_status and self.call_status.winfo_exists():
                self.call_status.config(text="Connected")
        except:
            pass
            
        self.start_call_timer()
        
        # Start audio capture and playback threads
        if PYAUDIO_AVAILABLE and self.call_type in ('voice', 'video'):
            # Clear stale audio chunks from previous calls
            while not self.audio_queue.empty():
                try: self.audio_queue.get_nowait()
                except: break
                
            if not self.pyaudio_instance:
                self.pyaudio_instance = pyaudio.PyAudio()
                
            threading.Thread(target=self.audio_capture_loop, daemon=True).start()
            threading.Thread(target=self.audio_playback_loop, daemon=True).start()
            
        # Start video
        if OPENCV_AVAILABLE and self.call_type == 'video':
            threading.Thread(target=self.video_capture_loop, daemon=True).start()
            
    def audio_capture_loop(self):
        import numpy as np
        stream_in = None
        try:
            stream_in = self._open_audio_stream(is_input=True)
            if stream_in is None:
                print("[Audio] Capture stream could not be opened — mic unavailable.")
                return

            print(f"[Audio] Capture loop started, call_id={self.active_call}")
            _send_count = 0
            while self.call_running and self.active_call:
                try:
                    data = stream_in.read(AUDIO_CHUNK, exception_on_overflow=False)
                    audio_np = np.frombuffer(data, dtype=np.int16)
                    audio_np = np.clip(audio_np * 4.0, -32768, 32767).astype(np.int16)
                    boosted_data = audio_np.tobytes()

                    encoded = base64.b64encode(boosted_data).decode('utf-8')
                    ok = self.udp_send_msg({
                        'type': 'call_media', 'call_id': self.active_call,
                        'sender': self.username,
                        'media_type': 'audio', 'data': encoded
                    })
                    if ok:
                        _send_count += 1
                        if _send_count == 1 or _send_count % 100 == 0:
                            print(f"[SEND] Audio packets sent via UDP: {_send_count}")
                    else:
                        print("[SEND] udp_send_msg returned False!")
                except OSError as e:
                    print(f"[Audio] Capture read error: {e}")
                    # Stream may have been invalidated; attempt to reopen
                    try: stream_in.close()
                    except: pass
                    stream_in = self._open_audio_stream(is_input=True)
                    if stream_in is None:
                        break
                except Exception as e:
                    print(f"[Audio] Capture unexpected error: {e}")
        except Exception as e:
            print(f"[Audio] Capture loop fatal: {e}")
        finally:
            if stream_in:
                try:
                    stream_in.stop_stream()
                    stream_in.close()
                except: pass
            print("[Audio] Capture loop exited.")
            
    def video_capture_loop(self):
        try:
            self.video_capture = cv2.VideoCapture(0)
            
            while self.call_running and self.active_call:
                ret, frame = self.video_capture.read()
                if not ret:
                    break
                    
                # Show local preview
                if PIL_AVAILABLE:
                    try:
                        preview = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                        preview = cv2.resize(preview, self.local_video_size)
                        img = Image.fromarray(preview)
                        imgtk = ImageTk.PhotoImage(image=img)
                        
                        # Define a safe UI update function
                        def update_preview(image_tk=imgtk):
                            if self.local_video_label and self.local_video_label.winfo_exists():
                                self.local_video_label.imgtk = image_tk
                                self.local_video_label.config(image=image_tk)
                                
                        # Send the update to the main Tkinter thread
                        self.root.after(0, update_preview)
                    except:
                        pass
                
                # Encode and chunk video to avoid MTU drop
                frame = cv2.resize(frame, (640, 480))
                _, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 50])
                encoded = base64.b64encode(buffer).decode('utf-8')
                
                chunk_size = 1000  # Safe byte length for JSON overhead inclusion
                frame_id = int(time.time() * 1000)
                total_chunks = (len(encoded) + chunk_size - 1) // chunk_size
                
                for i in range(total_chunks):
                    chunk_data = encoded[i*chunk_size : (i+1)*chunk_size]
                    self.udp_send_msg({
                        'type': 'call_media', 'call_id': self.active_call,
                        'sender': self.username,
                        'media_type': 'video_chunk', 'frame_id': frame_id,
                        'chunk_idx': i, 'total_chunks': total_chunks,
                        'data': chunk_data
                    })
                
                time.sleep(0.033)  # ~30 FPS
                
        except Exception as e:
            print(f"Video error: {e}")
        finally:
            self.cleanup_video()
            
    def cleanup_audio(self):
        try:
            if self.audio_stream_in:
                self.audio_stream_in.stop_stream()
                self.audio_stream_in.close()
        except:
            pass
        try:
            if self.audio_stream_out:
                self.audio_stream_out.stop_stream()
                self.audio_stream_out.close()
        except:
            pass
        self.audio_stream_in = None
        self.audio_stream_out = None
        
    def cleanup_video(self):
        try:
            if self.video_capture:
                self.video_capture.release()
        except:
            pass
        self.video_capture = None
        
    def stop_media_streams(self):
        self.call_running = False
        # Do not manually aggressively destroy audio/video streams here, 
        # let their respective threads detect call_running = False and clean themselves
        # up gracefully via 'finally' blocks to avoid C-library segfaults.
        
    def start_call_timer(self):
        self.call_start_time = time.time()
        self.update_call_timer()
        
    def update_call_timer(self):
        if not self.call_running:
            return
        try:
            if hasattr(self, 'call_timer_label') and self.call_timer_label and self.call_timer_label.winfo_exists():
                elapsed = int(time.time() - self.call_start_time)
                mins = elapsed // 60
                secs = elapsed % 60
                self.call_timer_label.config(text=f"{mins:02d}:{secs:02d}")
                self.root.after(1000, self.update_call_timer)
        except:
            pass
            
    def end_call(self):
        if self.active_call:
            self.send_msg({'type': 'end_call', 'call_id': self.active_call})
        self.stop_media_streams()
        self.close_call_dialog()
        
    def close_call_dialog(self):
        self.call_running = False
        self.active_call = None
        self.call_type = None
        
        if self.call_dialog:
            try:
                self.call_dialog.destroy()
            except:
                pass
            self.call_dialog = None
            
    def run(self):
        self.root.mainloop()


if __name__ == '__main__':
    client = ChatClient()
    client.run()
