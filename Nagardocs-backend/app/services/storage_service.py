"""
storage_service.py — File storage abstraction for NagarDocs
Wraps Supabase Storage so upload.py stays clean.
"""
import uuid
from app.core.database import get_supabase_sync


class StorageService:
    BUCKET = "nagardocs"

    def upload_file(self, file_bytes: bytes, department_id: str, filename: str) -> str:
        """Upload file to Supabase Storage and return the storage path."""
        supabase = get_supabase_sync()
        ext = filename.rsplit(".", 1)[-1] if "." in filename else "bin"
        unique_name = f"{uuid.uuid4()}.{ext}"
        storage_path = f"documents/{department_id}/{unique_name}"

        supabase.storage.from_(self.BUCKET).upload(
            storage_path,
            file_bytes,
            {"content-type": self._mime_type(ext)},
        )
        return storage_path

    def get_signed_url(self, storage_path: str, expires_in: int = 3600) -> str:
        """Generate a temporary signed URL for secure access."""
        supabase = get_supabase_sync()
        resp = supabase.storage.from_(self.BUCKET).create_signed_url(storage_path, expires_in)
        return resp.get("signedURL", "")

    def delete_file(self, storage_path: str):
        supabase = get_supabase_sync()
        supabase.storage.from_(self.BUCKET).remove([storage_path])

    def _mime_type(self, ext: str) -> str:
        mapping = {
            "pdf": "application/pdf",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
        }
        return mapping.get(ext.lower(), "application/octet-stream")
