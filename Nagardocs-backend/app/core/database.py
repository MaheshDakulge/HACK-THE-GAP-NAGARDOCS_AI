import httpx
from typing import Any, Optional
from app.core.config import settings

# FIXED: removed print("KEY:", ...) — service key must never be logged


class _Result:
    def __init__(self, data, count=None):
        self.data  = data if data is not None else []
        self.count = count


class _QueryBuilder:
    def __init__(self, base_url: str, table: str, headers: dict):
        self._url     = f"{base_url}/rest/v1/{table}"
        self._headers = headers
        self._filters: list[str] = []
        self._selects: str = "*"
        self._order:   Optional[str] = None
        self._range_start: Optional[int] = None
        self._range_end:   Optional[int] = None
        self._limit:  Optional[int] = None
        self._action  = "select"
        self._body:    Any = None
        self._count_mode: Optional[str] = None

    def select(self, columns: str = "*", count: Optional[str] = None):
        self._selects = columns
        self._action  = "select"
        if count:
            self._count_mode = count
            self._headers = {**self._headers, "Prefer": f"count={count}"}
        return self

    def insert(self, data: dict):
        self._action = "insert"
        self._body   = data
        self._headers = {**self._headers, "Prefer": "return=representation"}
        return self

    def update(self, data: dict):
        self._action = "update"
        self._body   = data
        self._headers = {**self._headers, "Prefer": "return=representation"}
        return self

    def delete(self):
        self._action = "delete"
        self._headers = {**self._headers, "Prefer": "return=representation"}
        return self

    def upsert(self, data: dict):
        self._action = "upsert"
        self._body   = data
        self._headers = {**self._headers, "Prefer": "resolution=merge-duplicates,return=representation"}
        return self

    def eq(self, col: str, val: Any):
        self._filters.append(f"{col}=eq.{val}")
        return self

    def neq(self, col: str, val: Any):
        self._filters.append(f"{col}=neq.{val}")
        return self

    def gt(self, col: str, val: Any):
        self._filters.append(f"{col}=gt.{val}")
        return self

    def gte(self, col: str, val: Any):
        self._filters.append(f"{col}=gte.{val}")
        return self

    def lt(self, col: str, val: Any):
        self._filters.append(f"{col}=lt.{val}")
        return self

    def lte(self, col: str, val: Any):
        self._filters.append(f"{col}=lte.{val}")
        return self

    def ilike(self, col: str, pattern: str):
        self._filters.append(f"{col}=ilike.{pattern}")
        return self

    def in_(self, col: str, values: list):
        vals = ",".join(str(v) for v in values)
        self._filters.append(f"{col}=in.({vals})")
        return self

    def order(self, col: str, desc: bool = False):
        direction = "desc" if desc else "asc"
        self._order = f"{col}.{direction}"
        return self

    def limit(self, n: int):
        self._limit = n
        return self

    def range(self, start: int, end: int):
        self._range_start = start
        self._range_end   = end
        return self

    def or_(self, filter_str: str):
        self._filters.append(f"or=({filter_str})")
        return self

    def _build_params(self) -> dict:
        params: dict = {}
        if self._action == "select":
            params["select"] = self._selects
        for f in self._filters:
            col, expr = f.split("=", 1)
            params[col] = expr
        if self._order:
            params["order"] = self._order
        if self._limit is not None:
            params["limit"] = str(self._limit)
        if self._range_start is not None:
            params["offset"] = str(self._range_start)
            params["limit"]  = str(self._range_end - self._range_start + 1)
        return params

    def execute(self) -> _Result:
        import time
        params  = self._build_params()
        headers = {**self._headers}
        if self._count_mode:
            headers["Prefer"] = f"count={self._count_mode}"

        timeout = httpx.Timeout(30.0, connect=10.0)
        last_exc = None
        for attempt in range(3):
            try:
                with httpx.Client(timeout=timeout) as client:
                    if self._action == "select":
                        r = client.get(self._url, params=params, headers=headers)
                    elif self._action == "insert":
                        r = client.post(self._url, json=self._body, params=params, headers=headers)
                    elif self._action == "update":
                        r = client.patch(self._url, json=self._body, params=params, headers=headers)
                    elif self._action == "delete":
                        r = client.delete(self._url, params=params, headers=headers)
                    elif self._action == "upsert":
                        r = client.post(self._url, json=self._body, params=params, headers=headers)
                    else:
                        raise ValueError(f"Unknown action: {self._action}")
                break  # success — exit retry loop
            except httpx.ReadTimeout as e:
                last_exc = e
                if attempt < 2:
                    time.sleep(1)
                continue
        else:
            raise RuntimeError(f"DB timeout after 3 attempts on {self._action} {self._url}") from last_exc

        if r.status_code >= 400:
            raise RuntimeError(f"HTTP {r.status_code} on {self._action} {self._url}: {r.text}")
        data = r.json() if r.content else []
        if isinstance(data, dict) and "message" in data:
            raise RuntimeError(data["message"])

        count = None
        if self._count_mode and "content-range" in r.headers:
            content_range = r.headers["content-range"]
            total_part = content_range.split("/")[-1]
            count = int(total_part) if total_part != "*" else None

        return _Result(data if isinstance(data, list) else [data], count=count)


class _StorageBucket:
    def __init__(self, base_url: str, bucket: str, headers: dict):
        self._url     = f"{base_url}/storage/v1/object"
        self._bucket  = bucket
        self._headers = headers

    def upload(self, path: str, data: bytes, options: dict = None):
        url  = f"{self._url}/{self._bucket}/{path}"
        hdrs = {**self._headers, "Content-Type": (options or {}).get("content-type", "application/octet-stream")}
        with httpx.Client(timeout=30) as client:
            r = client.post(url, content=data, headers=hdrs)
        r.raise_for_status()
        return r.json()

    def create_signed_url(self, path: str, expires_in: int = 3600) -> dict:
        url = f"{self._url.replace('/object', '/sign')}/{self._bucket}/{path}"
        with httpx.Client(timeout=10) as client:
            r = client.post(url, json={"expiresIn": expires_in}, headers=self._headers)
        r.raise_for_status()
        return r.json()

    def remove(self, paths: list):
        url = f"{self._url}/{self._bucket}"
        with httpx.Client(timeout=10) as client:
            r = client.delete(url, json={"prefixes": paths}, headers=self._headers)
        r.raise_for_status()
        return r.json()

    def download(self, path: str) -> bytes:
        url = f"{self._url}/{self._bucket}/{path}"
        with httpx.Client(timeout=30) as client:
            r = client.get(url, headers=self._headers)
        r.raise_for_status()
        return r.content


class _Storage:
    def __init__(self, base_url: str, headers: dict):
        self._base_url = base_url
        self._headers  = headers

    def from_(self, bucket: str) -> _StorageBucket:
        return _StorageBucket(self._base_url, bucket, self._headers)


class _AuthUser:
    def __init__(self, uid: str, email: str):
        self.id    = uid
        self.email = email


class _AuthSession:
    def __init__(self, access_token: str, refresh_token: str = ""):
        self.access_token  = access_token
        self.refresh_token = refresh_token


class _AuthResponse:
    def __init__(self, user: _AuthUser = None, session: _AuthSession = None):
        self.user    = user
        self.session = session


class _Auth:
    def __init__(self, base_url: str, anon_key: str):
        self._url = f"{base_url}/auth/v1"
        self._key = anon_key

    def _hdrs(self):
        return {"apikey": self._key, "Content-Type": "application/json"}

    def sign_up(self, credentials: dict) -> _AuthResponse:
        r = httpx.post(
            f"{self._url}/signup",
            json={"email": credentials["email"], "password": credentials["password"]},
            headers=self._hdrs(), timeout=15,
        )
        r.raise_for_status()
        js      = r.json()
        user    = _AuthUser(js.get("id", ""), js.get("email", ""))
        session = _AuthSession(js.get("access_token", ""), js.get("refresh_token", ""))
        return _AuthResponse(user, session)

    def sign_in_with_password(self, credentials: dict) -> _AuthResponse:
        r = httpx.post(
            f"{self._url}/token?grant_type=password",
            json={"email": credentials["email"], "password": credentials["password"]},
            headers=self._hdrs(), timeout=15,
        )
        r.raise_for_status()
        js      = r.json()
        user_js = js.get("user", {})
        user    = _AuthUser(user_js.get("id", ""), user_js.get("email", ""))
        session = _AuthSession(js.get("access_token", ""), js.get("refresh_token", ""))
        return _AuthResponse(user, session)

    def get_user(self, token: str) -> _AuthResponse:
        r = httpx.get(
            f"{self._url}/user",
            headers={**self._hdrs(), "Authorization": f"Bearer {token}"},
            timeout=10,
        )
        r.raise_for_status()
        js   = r.json()
        user = _AuthUser(js.get("id", ""), js.get("email", ""))
        return _AuthResponse(user=user)


class SupabaseClient:
    """Lightweight httpx-based Supabase REST client — no C++ required."""

    def __init__(self, url: str, key: str):
        self._url     = url.rstrip("/")
        self._key     = key
        self._headers = {
            "apikey":        key,
            "Authorization": f"Bearer {key}",
            "Content-Type":  "application/json",
        }
        self.auth    = _Auth(self._url, key)
        self.storage = _Storage(self._url, self._headers)

    def table(self, name: str) -> _QueryBuilder:
        return _QueryBuilder(self._url, name, dict(self._headers))


_client: SupabaseClient | None = None


def get_supabase_sync() -> SupabaseClient:
    global _client
    if _client is None:
        if not settings.supabase_url or not settings.supabase_service_key:
            raise ValueError("SUPABASE_URL and SUPABASE_SERVICE_KEY must be set in .env")
        _client = SupabaseClient(settings.supabase_url, settings.supabase_service_key)
    return _client


async def get_supabase() -> SupabaseClient:
    """FastAPI dependency — yields the Supabase client."""
    return get_supabase_sync()