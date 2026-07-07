from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from .database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True, nullable=False)
    email = Column(String(100), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    qr_code_string = Column(String(100), unique=True, index=True, nullable=False)
    
    # Anti-alt metadata
    registered_ip = Column(String(50))
    device_fingerprint = Column(String(255))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))  # ponytail: fix BUG-9

    # Relationships
    friends_added = relationship("Friendship", foreign_keys="[Friendship.user_id]", back_populates="user")
    friends_of = relationship("Friendship", foreign_keys="[Friendship.friend_id]", back_populates="friend")


class Friendship(Base):
    __tablename__ = "friendships"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    friend_id = Column(Integer, ForeignKey("users.id"))
    status = Column(String(20), default="pending") # pending, accepted, blocked
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))  # ponytail: fix BUG-9

    user = relationship("User", foreign_keys=[user_id], back_populates="friends_added")
    friend = relationship("User", foreign_keys=[friend_id], back_populates="friends_of")
