from fastapi import FastAPI, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
import uuid
import bcrypt  # ponytail: fix SEC-2, passlib removed — bcrypt used directly
from datetime import datetime, timezone, timedelta

from . import models, database

models.Base.metadata.create_all(bind=database.engine)

app = FastAPI(title="Cipher API", description="Backend authentication and matching for Cipher App")

# Pydantic Schemas
class UserCreate(BaseModel):
    username: str
    email: EmailStr
    password: str
    device_fingerprint: str = "unknown"

class UserResponse(BaseModel):
    id: int
    username: str
    email: str
    qr_code_string: str
    
    class Config:
        from_attributes = True # Fixed V2 pydantic warning

class LoginRequest(BaseModel):
    email: EmailStr
    password: str

def get_password_hash(password: str) -> str:
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))

def check_rate_limit(ip_address: str, db: Session):
    # ponytail: DB-level check survives restarts; naive UTC for SQLite compat
    one_hour_ago = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(hours=1)
    recent = db.query(models.User).filter(
        models.User.registered_ip == ip_address,
        models.User.created_at > one_hour_ago
    ).first()
    if recent:
        raise HTTPException(status_code=429, detail="Too many registrations from this IP. Anti-alt measure active.")

@app.post("/api/register", response_model=UserResponse)
def register(user: UserCreate, request: Request, db: Session = Depends(database.get_db)):
    client_ip = request.client.host if request.client else "127.0.0.1"
    
    # 1. Check Rate Limit (Anti-Alt)
    check_rate_limit(client_ip, db)
    
    # 2. Check if Email or Username exists
    db_user = db.query(models.User).filter(
        (models.User.email == user.email) | (models.User.username == user.username)
    ).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Email or username already registered")
        
    # 3. Check Device Fingerprint (Basic Anti-Alt)
    db_device = db.query(models.User).filter(models.User.device_fingerprint == user.device_fingerprint).first()
    if db_device and user.device_fingerprint != "unknown":
         # Just a warning or strict block depending on settings. For now, strict block.
         raise HTTPException(status_code=403, detail="Device already associated with an account. Anti-alt measure active.")

    # 4. Generate unique QR string
    qr_string = f"cipher-qr-{uuid.uuid4().hex[:12]}"
    
    hashed_password = get_password_hash(user.password)
    new_user = models.User(
        username=user.username,
        email=user.email,
        hashed_password=hashed_password,
        qr_code_string=qr_string,
        registered_ip=client_ip,
        device_fingerprint=user.device_fingerprint
    )
    
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user

@app.post("/api/login", response_model=UserResponse)
def login(creds: LoginRequest, db: Session = Depends(database.get_db)):
    user = db.query(models.User).filter(models.User.email == creds.email).first()
    if not user or not verify_password(creds.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    if not user.is_active:  # ponytail: fix SEC-5
        raise HTTPException(status_code=403, detail="Account is deactivated")
    return user

@app.post("/api/add_friend")
def add_friend(user_id: int, target_identifier: str, by_qr: bool = False, db: Session = Depends(database.get_db)):
    # target_identifier can be a username or a QR code string
    if by_qr:
        target_user = db.query(models.User).filter(models.User.qr_code_string == target_identifier).first()
    else:
        target_user = db.query(models.User).filter(models.User.username == target_identifier).first()
        
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")
        
    if target_user.id == user_id:
        raise HTTPException(status_code=400, detail="Cannot add yourself")
        
    # Check existing friendship
    existing = db.query(models.Friendship).filter(
        models.Friendship.user_id == user_id, 
        models.Friendship.friend_id == target_user.id
    ).first()
    
    if existing:
        raise HTTPException(status_code=400, detail="Friendship or request already exists")
        
    new_friendship = models.Friendship(user_id=user_id, friend_id=target_user.id, status="pending")
    db.add(new_friendship)
    db.commit()
    return {"message": f"Friend request sent to {target_user.username}"}

@app.get("/api/friends")
def get_friends(user_id: int, db: Session = Depends(database.get_db)):
    friendships = db.query(models.Friendship).filter(
        (models.Friendship.user_id == user_id) | (models.Friendship.friend_id == user_id)
    ).all()

    pending, accepted = [], []
    for f in friendships:
        user = db.query(models.User).filter(models.User.id == f.user_id).first()
        friend = db.query(models.User).filter(models.User.id == f.friend_id).first()
        entry = {
            'id': f.id,
            'user_id': f.user_id,
            'friend_id': f.friend_id,
            'status': f.status,
            'user_username': user.username if user else None,
            'friend_username': friend.username if friend else None,
        }
        if f.status == 'pending':
            pending.append(entry)
        elif f.status == 'accepted':
            accepted.append(entry)
    return {'pending': pending, 'accepted': accepted}

@app.patch("/api/friends/{friendship_id}")
def respond_to_friend(friendship_id: int, action: str, user_id: int, db: Session = Depends(database.get_db)):
    friendship = db.query(models.Friendship).filter(models.Friendship.id == friendship_id).first()
    if not friendship:
        raise HTTPException(status_code=404, detail="Friendship not found")
    if friendship.friend_id != user_id:
        raise HTTPException(status_code=403, detail="Not authorized to respond to this request")
    if action == 'accept':
        friendship.status = 'accepted'
        db.commit()
        return {"message": "Friend request accepted"}
    elif action == 'reject':
        db.delete(friendship)
        db.commit()
        return {"message": "Friend request rejected"}
    raise HTTPException(status_code=400, detail="Invalid action — use 'accept' or 'reject'")

# ── Offline message queue ──────────────────────────────────────────────────────

class OfflineMessageIn(BaseModel):
    sender_username: str
    receiver_username: str
    content: str
    content_type: str = "text"
    filename: str | None = None

@app.post("/api/messages/store")
def store_offline_message(msg: OfflineMessageIn, db: Session = Depends(database.get_db)):
    """Called by the TCP server when the recipient is offline."""
    new_msg = models.OfflineMessage(
        sender_username=msg.sender_username,
        receiver_username=msg.receiver_username,
        content=msg.content,
        content_type=msg.content_type,
        filename=msg.filename,
    )
    db.add(new_msg)
    db.commit()
    return {"message": "Stored"}

@app.get("/api/messages/pending")
def get_pending_messages(username: str, db: Session = Depends(database.get_db)):
    """Called by the client on login to retrieve queued offline messages."""
    msgs = db.query(models.OfflineMessage).filter(
        models.OfflineMessage.receiver_username == username,
        models.OfflineMessage.delivered == False  # noqa: E712
    ).order_by(models.OfflineMessage.created_at).all()
    result = [{'id': m.id, 'sender': m.sender_username, 'content': m.content,
               'content_type': m.content_type, 'filename': m.filename,
               'timestamp': m.created_at.isoformat()} for m in msgs]
    # Mark all as delivered
    for m in msgs:
        m.delivered = True
    db.commit()
    return result

