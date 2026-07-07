#!/usr/bin/env python3
"""
Cipher - Server
Real-time chat server with voice/video call media relay
"""

import socket
import threading
import json
import os
import time
import tempfile
import requests  # for offline message queue API calls
from datetime import datetime
from typing import Dict, List, Optional
import struct

HOST = '0.0.0.0'
PORT = 5000
BUFFER_SIZE = 65536
API_BASE = 'http://127.0.0.1:8000/api'  # internal API base


class ChatServer:
    def __init__(self):
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.udp_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # Increase UDP buffers for video datagrams
        self.udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024 * 1024)
        self.udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1024 * 1024)
        self.udp_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)  # ponytail: fix BUG-1, must set before bind
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        self.clients: Dict[str, dict] = {}
        self.groups: Dict[str, dict] = {}
        self.active_calls: Dict[str, dict] = {}
        self.lock = threading.Lock()
        self.running = False
        self.data_dir = self._setup_data_directory()
        
    def _setup_data_directory(self) -> str:
        locations = [
            os.path.join(os.path.dirname(os.path.abspath(__file__)), 'server_data'),
            os.path.join(os.path.expanduser('~'), 'whatsapp_clone_data'),
            os.path.join(tempfile.gettempdir(), 'whatsapp_clone_data'),
        ]
        for path in locations:
            try:
                os.makedirs(os.path.join(path, 'files'), exist_ok=True)
                print(f"[SERVER] Data directory: {path}")
                return path
            except:
                continue
        raise RuntimeError("Cannot create data directory in any location")  # ponytail: fix BUG-2, never return None
        
    def start(self):
        try:
            self.server_socket.bind((HOST, PORT))
            self.server_socket.listen(50)
            self.udp_socket.bind((HOST, PORT))
            self.running = True
            threading.Thread(target=self.udp_receive_loop, daemon=True).start()
            
            hostname = socket.gethostname()
            try:
                local_ip = socket.gethostbyname(hostname)
            except:
                local_ip = "127.0.0.1"
            
            print("=" * 55)
            print("            CIPHER SERVER")
            print("=" * 55)
            print(f"  Local IP Address : {local_ip}")
            print(f"  Port             : {PORT}")
            print("=" * 55)
            print("  Connect using:")
            print(f"    Same PC    : 127.0.0.1")
            print(f"    LAN/WiFi   : {local_ip}")
            print("=" * 55)
            print("\n[SERVER] Waiting for connections...\n")
            
            while self.running:
                try:
                    client_socket, address = self.server_socket.accept()
                    threading.Thread(target=self.handle_client, args=(client_socket, address), daemon=True).start()
                except:
                    if self.running:
                        pass
        finally:
            self.running = False
            
    def send_msg(self, sock: socket.socket, data: dict) -> bool:
        # Message framing pattern:
        # - Encode JSON payload to bytes.
        # - Prefix with a 4-byte big-endian payload length.
        # This allows the receiver to know exactly where each message ends.
        try:
            msg = json.dumps(data).encode('utf-8')
            sock.sendall(struct.pack('>I', len(msg)) + msg)
            return True
        except:
            return False
            
    def recv_msg(self, sock: socket.socket) -> Optional[dict]:
        # Read one framed message:
        # 1) Read fixed 4-byte length prefix.
        # 2) Read exactly "length" bytes of payload.
        # 3) Decode JSON into a Python dict.
        try:
            raw_len = b''
            while len(raw_len) < 4:
                chunk = sock.recv(4 - len(raw_len))
                if not chunk:
                    return None
                raw_len += chunk
            length = struct.unpack('>I', raw_len)[0]
            if length > 100 * 1024 * 1024:
                return None
            data = b''
            while len(data) < length:
                chunk = sock.recv(min(BUFFER_SIZE, length - len(data)))
                if not chunk:
                    return None
                data += chunk
            return json.loads(data.decode('utf-8'))
        except:
            return None
            
    def handle_client(self, sock: socket.socket, addr: tuple):
        username = None
        try:
            data = self.recv_msg(sock)
            if not data or data.get('type') != 'register':
                sock.close()
                return
                
            username = data.get('username', '').strip()
            if not username or username in self.clients:
                self.send_msg(sock, {'type': 'error', 'message': 'Username taken or invalid'})
                sock.close()
                return
                
            with self.lock:
                self.clients[username] = {'socket': sock, 'address': addr, 'status': 'online'}
                
            print(f"[+] {username} connected from {addr}")
            self.send_msg(sock, {'type': 'registered', 'username': username})
            self.broadcast_users()
            self.send_groups(sock)
            self._deliver_offline_messages(username, sock)
            
            while self.running:
                msg = self.recv_msg(sock)
                if not msg:
                    break
                self.process(username, msg)
        except:
            pass
        finally:
            if username:
                with self.lock:
                    self.clients.pop(username, None)
                print(f"[-] {username} disconnected")
                self.broadcast_users()
            try:
                sock.close()
            except:
                pass

    def _deliver_offline_messages(self, username: str, sock):
        """Fetch queued messages from API and push to newly connected client."""
        try:
            resp = requests.get(f'{API_BASE}/messages/pending?username={username}', timeout=3)
            if resp.status_code == 200:
                for m in resp.json():
                    self.send_msg(sock, {
                        'type': 'private_message',
                        'sender': m['sender'],
                        'content': m['content'],
                        'content_type': m.get('content_type', 'text'),
                        'filename': m.get('filename'),
                        'timestamp': m.get('timestamp', ''),
                        'offline_queued': True,
                    })
        except Exception:
            pass  # non-fatal

    def udp_receive_loop(self):
        while self.running:
            try:
                data, addr = self.udp_socket.recvfrom(BUFFER_SIZE)
                if not data:
                    continue
                msg = json.loads(data.decode('utf-8'))
                msg_type = msg.get('type')
                
                if msg_type == 'register_udp':
                    username = msg.get('username')
                    if username and username in self.clients:
                        self.clients[username]['udp_address'] = addr
                
                elif msg_type == 'call_media':
                    call_id = msg.get('call_id')
                    sender = msg.get('sender')
                    call = self.active_calls.get(call_id)
                    
                    if sender and sender in self.clients:
                        self.clients[sender]['udp_address'] = addr
                        
                    if not call or call.get('status') != 'connected':
                        continue
                        
                    other = call['receiver'] if call['caller'] == sender else call['caller']
                    
                    if other == sender:
                        continue  # Absolute reflection block: Do not process if pointing to self.
                        
                    if other in self.clients and 'udp_address' in self.clients[other]:
                        # Hardware block: If the destination IP/Port matches the incoming packet
                        if self.clients[other]['udp_address'] == addr:
                            continue
                            
                        self.udp_socket.sendto(data, self.clients[other]['udp_address'])
            except OSError as e:
                # Catch ICMP Port Unreachable which raises 10054 on Windows
                if getattr(e, 'winerror', None) == 10054:
                    pass
                else:
                    time.sleep(0.01)
            except Exception as e:
                print(f"UDP Server Error: {e}")
                time.sleep(0.01)

    def process(self, sender: str, msg: dict):
        t = msg.get('type', '')
        handlers = {
            'private_message': self._handle_private_message,
            'group_message': self._handle_group_message,
            'create_group': self._handle_create_group,
            'join_group': self._handle_join_group,
            'leave_group': self._handle_leave_group,
            'delete_group': self._handle_delete_group,
            'typing': self._handle_typing,
            'voice_call': self._handle_start_call,
            'video_call': self._handle_start_call,
            'call_response': self._handle_call_response,
            'end_call': self._handle_end_call,
            # 'call_media' removed — handled by UDP loop only (fix BUG-4)
            'forward_message': self._handle_forward_message,
            'read_receipt': self._handle_read_receipt,
            'delete_message': self._handle_delete_message,
            'reaction': self._handle_reaction,
        }
        
        handler = handlers.get(t)
        if handler:
            handler(sender, msg)

    def _message_payload(self, sender: str, msg: dict) -> dict:
        """Build a standard message payload shared by private/group/forwarded flows."""
        return {
            'sender': sender,
            'content': msg.get('content', ''),
            'content_type': msg.get('content_type', 'text'),
            'timestamp': datetime.now().strftime('%H:%M'),
            'filename': msg.get('filename'),
            'file_data': msg.get('file_data'),
        }

    def _handle_private_message(self, sender: str, msg: dict):
        recv = msg.get('receiver')
        if recv not in self.clients:
            # Recipient offline — queue via API
            try:
                requests.post(f'{API_BASE}/messages/store', json={
                    'sender_username': sender,
                    'receiver_username': recv,
                    'content': msg.get('content', ''),
                    'content_type': msg.get('content_type', 'text'),
                    'filename': msg.get('filename'),
                }, timeout=2)
            except Exception:
                pass  # non-fatal — best effort queue
            return
        out = self._message_payload(sender, msg)
        out.update({'type': 'private_message', 'receiver': recv})
        self.send_msg(self.clients[recv]['socket'], out)
        out['type'] = 'message_sent'
        self.send_msg(self.clients[sender]['socket'], out)

    def _handle_group_message(self, sender: str, msg: dict):
        grp = msg.get('group')
        if grp not in self.groups or sender not in self.groups[grp]['members']:
            return
        out = self._message_payload(sender, msg)
        out.update({'type': 'group_message', 'group': grp})
        for member in self.groups[grp]['members']:
            if member in self.clients:
                self.send_msg(self.clients[member]['socket'], out)

    def _handle_create_group(self, sender: str, msg: dict):
        name = msg.get('name', '').strip()
        if not name:
            return
        created = False
        with self.lock:
            if name not in self.groups:
                self.groups[name] = {'owner': sender, 'members': [sender]}
                created = True
        if created:
            self.send_msg(self.clients[sender]['socket'], {'type': 'group_created', 'group': name})
            self.broadcast_groups()

    def _handle_join_group(self, sender: str, msg: dict):
        grp = msg.get('group')
        joined = False
        with self.lock:
            if grp in self.groups and sender not in self.groups[grp]['members']:
                self.groups[grp]['members'].append(sender)
                joined = True
        if joined:
            self.send_msg(self.clients[sender]['socket'], {'type': 'group_joined', 'group': grp})
            self.broadcast_groups()

    def _handle_leave_group(self, sender: str, msg: dict):
        grp = msg.get('group')
        left = False
        with self.lock:
            if grp in self.groups and sender in self.groups[grp]['members']:
                self.groups[grp]['members'].remove(sender)
                if not self.groups[grp]['members']:
                    del self.groups[grp]
                left = True
        if left:
            self.send_msg(self.clients[sender]['socket'], {'type': 'group_left', 'group': grp})
            self.broadcast_groups()

    def _handle_delete_group(self, sender: str, msg: dict):
        grp = msg.get('group')
        members_to_notify = []
        with self.lock:
            if grp in self.groups and self.groups[grp]['owner'] == sender:
                members_to_notify = self.groups[grp]['members'][:]
                del self.groups[grp]
        if members_to_notify:
            for member in members_to_notify:
                if member in self.clients:
                    self.send_msg(self.clients[member]['socket'], {'type': 'group_deleted', 'group': grp})
            self.broadcast_groups()

    def _handle_typing(self, sender: str, msg: dict):
        recv = msg.get('receiver')
        grp = msg.get('group')
        out = {'type': 'typing', 'sender': sender, 'is_typing': msg.get('is_typing', False)}
        if grp and grp in self.groups:
            out['group'] = grp
            for member in self.groups[grp]['members']:
                if member in self.clients and member != sender:
                    self.send_msg(self.clients[member]['socket'], out)
        elif recv and recv in self.clients:
            self.send_msg(self.clients[recv]['socket'], out)

    def _handle_start_call(self, sender: str, msg: dict):
        recv = msg.get('receiver')
        if recv not in self.clients:
            return
        call_type = 'voice' if msg.get('type') == 'voice_call' else 'video'
        call_id = f"call_{sender}_{recv}_{int(time.time())}"
        with self.lock:
            self.active_calls[call_id] = {'caller': sender, 'receiver': recv, 'type': call_type, 'status': 'ringing'}
        self.send_msg(self.clients[recv]['socket'], {
            'type': 'incoming_call', 'call_id': call_id, 'caller': sender, 'call_type': call_type
        })
        self.send_msg(self.clients[sender]['socket'], {
            'type': 'call_initiated', 'call_id': call_id, 'receiver': recv, 'call_type': call_type
        })

    def _handle_call_response(self, sender: str, msg: dict):
        call_id = msg.get('call_id')
        resp = msg.get('response')
        caller = None
        
        with self.lock:
            if call_id in self.active_calls:
                call = self.active_calls[call_id]
                caller = call.get('caller')

                if resp == 'accept':
                    call['status'] = 'connected'
                else:
                    del self.active_calls[call_id]
                    
        if not caller:
            return

        if resp == 'accept':
            if caller in self.clients:
                self.send_msg(self.clients[caller]['socket'], {'type': 'call_accepted', 'call_id': call_id})
            self.send_msg(self.clients[sender]['socket'], {'type': 'call_connected', 'call_id': call_id})
        elif caller in self.clients:
            self.send_msg(self.clients[caller]['socket'], {'type': 'call_rejected', 'call_id': call_id})

    def _handle_end_call(self, sender: str, msg: dict):
        call_id = msg.get('call_id')
        other = None
        with self.lock:
            if call_id in self.active_calls:
                call = self.active_calls[call_id]
                other = call['receiver'] if call['caller'] == sender else call['caller']
                del self.active_calls[call_id]
                
        if other and other in self.clients:
            self.send_msg(self.clients[other]['socket'], {'type': 'call_ended', 'call_id': call_id})

    def _handle_call_media(self, sender: str, msg: dict):
        call_id = msg.get('call_id')
        call = self.active_calls.get(call_id)
        
        if not call or call.get('status') != 'connected':
            return
            
        other = call['receiver'] if call['caller'] == sender else call['caller']
        if other in self.clients:
            self.send_msg(self.clients[other]['socket'], {
                'type': 'call_media',
                'call_id': call_id,
                'sender': sender,
                'media_type': msg.get('media_type'),
                'data': msg.get('data')
            })

    def _handle_read_receipt(self, sender: str, msg: dict):
        recv = msg.get('receiver')
        if recv and recv in self.clients:
            self.send_msg(self.clients[recv]['socket'], {
                'type': 'read_receipt',
                'from': sender,
                'message_id': msg.get('message_id'),
            })

    def _handle_delete_message(self, sender: str, msg: dict):
        recv = msg.get('receiver')
        if recv and recv in self.clients:
            self.send_msg(self.clients[recv]['socket'], {
                'type': 'delete_message',
                'from': sender,
                'message_id': msg.get('message_id'),
            })

    def _handle_reaction(self, sender: str, msg: dict):
        recv = msg.get('receiver')
        if recv and recv in self.clients:
            self.send_msg(self.clients[recv]['socket'], {
                'type': 'reaction',
                'from': sender,
                'message_id': msg.get('message_id'),
                'emoji': msg.get('emoji'),
            })

    def _handle_forward_message(self, sender: str, msg: dict):
        target = msg.get('target')
        target_type = msg.get('target_type')
        out = self._message_payload(sender, msg)
        out['forwarded'] = True
        
        if target_type == 'private' and target in self.clients:
            # 1. Send the message to the target recipient
            out['type'] = 'private_message'
            out['receiver'] = target
            self.send_msg(self.clients[target]['socket'], out)
            
            # 2. FIX: Send the confirmation back to the sender so their UI updates
            out['type'] = 'message_sent'
            self.send_msg(self.clients[sender]['socket'], out)
            
        elif target_type == 'group' and target in self.groups:
            # For groups, broadcast to everyone (including the sender if they are in the group)
            out['type'] = 'group_message'
            out['group'] = target
            for member in self.groups[target]['members']:
                if member in self.clients:
                    self.send_msg(self.clients[member]['socket'], out)
                        
    def broadcast_users(self):
        with self.lock:
            # Safely create the list while locked
            users = [{'username': u, 'status': d['status']} for u, d in self.clients.items()]
            # Safely copy the active sockets while locked
            client_sockets = [c['socket'] for c in self.clients.values()]
            
        msg = {'type': 'user_list', 'users': users}
        
        # Send outside the lock to prevent bottlenecking the server
        for sock in client_sockets:
            self.send_msg(sock, msg)
            
    def send_groups(self, sock):
        groups = [{'name': n, 'owner': g['owner'], 'members': g['members']} for n, g in self.groups.items()]
        self.send_msg(sock, {'type': 'group_list', 'groups': groups})
        
    def broadcast_groups(self):
        with self.lock:
            # Safely create the list of groups while locked
            groups = [{'name': n, 'owner': g['owner'], 'members': g['members']} for n, g in self.groups.items()]
            # Safely copy the active client sockets while locked
            client_sockets = [c['socket'] for c in self.clients.values()]
            
        msg = {'type': 'group_list', 'groups': groups}
        
        # Send outside the lock to prevent bottlenecking the server
        for sock in client_sockets:
            self.send_msg(sock, msg)


if __name__ == '__main__':
    print("\nStarting Cipher Server...\n")
    server = ChatServer()
    try:
        server.start()
    except KeyboardInterrupt:
        print("\n[SERVER] Shutting down...")
        server.running = False
