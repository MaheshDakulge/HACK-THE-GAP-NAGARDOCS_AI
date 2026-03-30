from pydantic import BaseModel, EmailStr
from typing import Optional

class ShareLinkCreate(BaseModel):
    document_id: str
    expires_in_hours: int = 24
    password: Optional[str] = None

class ShareLinkResponse(BaseModel):
    share_id: str
    url: str
    expires_at: str

class ShareEmailRequest(BaseModel):
    document_id: str
    email: EmailStr
    message: Optional[str] = None
