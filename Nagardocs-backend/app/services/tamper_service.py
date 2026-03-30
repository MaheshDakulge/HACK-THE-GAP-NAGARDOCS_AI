
import hashlib
from app.core.database import get_supabase_sync


class TamperService:

    def compute_hash(self, file_bytes: bytes) -> str:
        """Return hex SHA-256 digest of raw file bytes."""
        return hashlib.sha256(file_bytes).hexdigest()

    def check_duplicate(self, file_hash: str) -> dict:
        """
        Returns dict:
          { "is_duplicate": bool, "duplicate_of": str|None, "filename": str|None }
        """
        supabase = get_supabase_sync()
        result = (
            supabase.table("documents")
            .select("id, filename, created_at")
            .eq("file_hash", file_hash)
            .limit(1)
            .execute()
        )
        if result.data:
            existing = result.data[0]
            return {
                "is_duplicate": True,
                "duplicate_of": existing["id"],
                "filename": existing["filename"],
            }
        return {"is_duplicate": False, "duplicate_of": None, "filename": None}

    def verify_integrity(self, doc_id: str, file_bytes: bytes) -> dict:
        """
        Re-hash file and compare against stored baseline.
        Returns { "is_tampered": bool, "stored_hash": str, "current_hash": str }
        """
        supabase = get_supabase_sync()
        doc = supabase.table("documents").select("file_hash").eq("id", doc_id).execute()
        if not doc.data:
            return {"is_tampered": False, "error": "Document not found"}

        stored_hash = doc.data[0]["file_hash"]
        current_hash = self.compute_hash(file_bytes)
        return {
            "is_tampered": stored_hash != current_hash,
            "stored_hash": stored_hash,
            "current_hash": current_hash,
        }
