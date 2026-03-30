"""
share_service.py — Document sharing via public links or email (Part 6)

Logic:
  - Public link: generate UUID token → store in shared_links table with expiry
  - Email: if user exists → grant access_control row; else → create pending invite
"""
import uuid
from datetime import datetime, timedelta
from app.core.database import get_supabase_sync
from app.utils.logger import logger


class ShareService:

    def create_public_link(
        self,
        document_id: str,
        created_by: str,
        expires_in_hours: int = 24,
        password: str | None = None,
    ) -> dict:
        supabase = get_supabase_sync()
        token = str(uuid.uuid4()).replace("-", "")
        expires_at = (datetime.utcnow() + timedelta(hours=expires_in_hours)).isoformat()

        row = supabase.table("shared_links").insert({
            "token":        token,
            "document_id":  document_id,
            "created_by":   created_by,
            "expires_at":   expires_at,
            "password":     password,
            "is_active":    True,
        }).execute()

        return {
            "share_id":   row.data[0]["id"] if row.data else None,
            "token":      token,
            "expires_at": expires_at,
        }

    def share_via_email(
        self,
        document_id: str,
        shared_by: str,
        department_id: str,
        email: str,
    ) -> dict:
        supabase = get_supabase_sync()

        # Check if user with this email exists
        user_row = supabase.table("users").select("id").eq("email", email).execute()

        if user_row.data:
            # Grant direct access
            recipient_id = user_row.data[0]["id"]
            supabase.table("access_control").insert({
                "document_id":    document_id,
                "user_id":        recipient_id,
                "granted_by":     shared_by,
                "permission":     "view",
            }).execute()
            logger.info(f"[share] Granted access to existing user {email}")
            return {"status": "access_granted", "email": email, "user_exists": True}
        else:
            # Create pending invite
            supabase.table("pending_invites").insert({
                "document_id":   document_id,
                "invited_email": email,
                "invited_by":    shared_by,
                "department_id": department_id,
                "expires_at":    (datetime.utcnow() + timedelta(days=7)).isoformat(),
            }).execute()
            logger.info(f"[share] Created pending invite for {email}")
            return {"status": "invite_sent", "email": email, "user_exists": False}

    def validate_public_link(self, token: str) -> dict | None:
        supabase = get_supabase_sync()
        result = (
            supabase.table("shared_links")
            .select("*, documents(id, filename, doc_type)")
            .eq("token", token)
            .eq("is_active", True)
            .execute()
        )
        if not result.data:
            return None
        link = result.data[0]
        if link["expires_at"] < datetime.utcnow().isoformat():
            return None
        return link

share_service = ShareService()
