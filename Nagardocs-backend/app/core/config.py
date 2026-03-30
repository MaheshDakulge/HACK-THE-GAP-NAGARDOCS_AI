import os
from pydantic_settings import BaseSettings, SettingsConfigDict

_here     = os.path.dirname(os.path.abspath(__file__))
_app_dir  = os.path.dirname(_here)
_root     = os.path.dirname(_app_dir)
_env_file = os.path.join(_root, ".env")


class Settings(BaseSettings):
    # ── Supabase ───────────────────────────────────────────────────────────────
    supabase_url:         str = ""
    supabase_service_key: str = ""

    # ── JWT ───────────────────────────────────────────────────────────────────
    jwt_secret:                  str = "change-me-in-production"
    jwt_algorithm:               str = "HS256"
    access_token_expire_minutes: int = 1440       # 24 hours

    # ── OpenAI ────────────────────────────────────────────────────────────────
    openai_api_key: str = ""

    # ── Google Vision (optional fallback) ─────────────────────────────────────
    google_vision_api_key: str = ""

    # ── NagarDocs ─────────────────────────────────────────────────────────────
    max_upload_bytes: int   = 20 * 1024 * 1024    # 20 MB
    hash_algorithm:   str   = "sha256"
    autosort_confidence_threshold: float = 0.75
    ocr_languages:    str   = "mar+hin+eng"

    # FIXED: default to "tesseract" (Linux PATH binary).
    # Override in .env on Windows: TESSERACT_CMD=C:\Program Files\Tesseract-OCR\tesseract.exe
    tesseract_cmd: str = "tesseract"

    model_config = SettingsConfigDict(env_file=_env_file, extra="ignore")


settings = Settings()
print("ENV FILE PATH:", _env_file)
print("SUPABASE_URL:", settings.supabase_url)
print("SUPABASE_KEY:", settings.supabase_service_key[:10])
