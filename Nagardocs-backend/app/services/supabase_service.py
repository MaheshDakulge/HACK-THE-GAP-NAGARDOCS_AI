import httpx
from fastapi import HTTPException
from app.core.config import settings

_headers = {
    "apikey": settings.supabase_service_key,
    "Authorization": f"Bearer {settings.supabase_service_key}",
    "Content-Type": "application/json",
    "Prefer": "return=representation",
}

BASE_URL = f"{settings.supabase_url}/rest/v1"



def create_user(data: dict) -> dict:
    """Insert a new user row. Raises HTTPException on failure."""
    response = httpx.post(
        f"{BASE_URL}/users",
        json=data,
        headers=_headers,
        timeout=10,
    )
    if response.status_code not in (200, 201):
        raise HTTPException(
            status_code=response.status_code,
            detail=f"DB error creating user: {response.text}",
        )
    result = response.json()
    return result[0] if isinstance(result, list) else result


def get_user_by_email(email: str) -> list:
    """Fetch users matching the given email. Returns a list (usually 0 or 1 item)."""
    response = httpx.get(
        f"{BASE_URL}/users",
        params={"email": f"eq.{email}", "select": "*"},
        headers=_headers,
        timeout=10,
    )
    if response.status_code != 200:
        raise HTTPException(
            status_code=response.status_code,
            detail=f"DB error fetching user: {response.text}",
        )
    return response.json()


def update_user(user_id: str, data: dict) -> dict:
    """Partially update a user row by id."""
    response = httpx.patch(
        f"{BASE_URL}/users",
        params={"id": f"eq.{user_id}"},
        json=data,
        headers=_headers,
        timeout=10,
    )
    if response.status_code not in (200, 204):
        raise HTTPException(
            status_code=response.status_code,
            detail=f"DB error updating user: {response.text}",
        )
    result = response.json()
    return result[0] if isinstance(result, list) and result else {}
