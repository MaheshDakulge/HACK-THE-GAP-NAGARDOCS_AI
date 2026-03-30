"""
activity_service.py — Centralized activity logging for NagarDocs (Part 9)
Tracks: upload, view, share, login, delete, move, export, admin actions
Cannot delete logs (append-only by RLS policy in schema.sql)
"""
from datetime import datetime
from app.core.database import get_supabase_sync
from app.utils.logger import logger


class ActivityService:

    def log(
        self,
        user_id: str,
        department_id: str,
        action: str,
        detail: str = "",
        document_id: str | None = None,
        metadata: dict | None = None,
    ):
        """Insert one activity log entry. Silently swallows errors so main flow is never blocked."""
        try:
            supabase = get_supabase_sync()
            supabase.table("activity_log").insert({
                "user_id":       user_id,
                "department_id": department_id,
                "action":        action,
                "detail":        detail,
                "document_id":   document_id,
                "metadata":      metadata or {},
                "created_at":    datetime.utcnow().isoformat(),
            }).execute()
        except Exception as e:
            logger.warning(f"[activity] Failed to log action '{action}': {e}")

    # ── Convenience wrappers ─────────────────────────────────────────────────────

    def log_upload(self, user_id, department_id, doc_id, filename):
        self.log(user_id, department_id, "upload", f"Uploaded: {filename}", doc_id)

    def log_view(self, user_id, department_id, doc_id, filename):
        self.log(user_id, department_id, "view", f"Viewed: {filename}", doc_id)

    def log_share(self, user_id, department_id, doc_id, recipient):
        self.log(user_id, department_id, "share", f"Shared with: {recipient}", doc_id)

    def log_login(self, user_id, department_id):
        self.log(user_id, department_id, "login", "User logged in")

    def log_export(self, user_id, department_id, detail):
        self.log(user_id, department_id, "export", detail)

activity_service = ActivityService()
