from enum import Enum
from fastapi import Depends, HTTPException, status
from app.core.security import get_current_user   # ← FIXED: was "core.security"


class Role(str, Enum):
    USER    = "user"
    OFFICER = "officer"
    ADMIN   = "admin"


class UserStatus(str, Enum):
    PENDING  = "pending"
    VERIFIED = "verified"
    BANNED   = "banned"


def require_role(required_roles: list[Role]):
    async def role_checker(user: dict = Depends(get_current_user)):
        user_role = user.get("role")
        if user_role not in [r.value for r in required_roles] and user_role != Role.ADMIN.value:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Access denied: one of {[r.value for r in required_roles]} role required.",
            )
        return user
    return role_checker