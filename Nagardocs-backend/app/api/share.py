
from fastapi import APIRouter, Depends, HTTPException
from app.core.database import get_supabase_sync
from app.core.security import get_current_user
from app.services.share_service import share_service
from app.services.activity_service import activity_service
from app.schemas.share_schema import ShareLinkCreate, ShareLinkResponse, ShareEmailRequest

router = APIRouter(prefix="/share", tags=["share"])


@router.post("/link", response_model=ShareLinkResponse)
async def create_share_link(
    payload: ShareLinkCreate,
    user: dict = Depends(get_current_user),
):
    """Generate a time-limited public link for a document."""
    supabase = get_supabase_sync()

    # Verify doc belongs to user's department
    doc = supabase.table("documents").select("id, filename").eq("id", payload.document_id).eq("department_id", user["department_id"]).execute()
    if not doc.data:
        raise HTTPException(status_code=404, detail="Document not found.")

    result = share_service.create_public_link(
        document_id=payload.document_id,
        created_by=user["id"],
        expires_in_hours=payload.expires_in_hours,
        password=payload.password,
    )
    activity_service.log_share(user["id"], user["department_id"], payload.document_id, "public_link")
    return {
        "share_id":   result["share_id"],
        "url":        f"/share/access/{result['token']}",
        "expires_at": result["expires_at"],
    }


@router.post("/email")
async def share_via_email(
    payload: ShareEmailRequest,
    user: dict = Depends(get_current_user),
):
    """Share a document with a user by email — grants access or sends invite."""
    supabase = get_supabase_sync()

    doc = supabase.table("documents").select("id, filename").eq("id", payload.document_id).eq("department_id", user["department_id"]).execute()
    if not doc.data:
        raise HTTPException(status_code=404, detail="Document not found.")

    result = share_service.share_via_email(
        document_id=payload.document_id,
        shared_by=user["id"],
        department_id=user["department_id"],
        email=payload.email,
    )
    activity_service.log_share(user["id"], user["department_id"], payload.document_id, payload.email)
    return result


@router.get("/access/{token}")
async def access_shared_document(token: str):
    """Public endpoint — access a document via share token (no auth required)."""
    link = share_service.validate_public_link(token)
    if not link:
        raise HTTPException(status_code=404, detail="Share link is invalid or expired.")

    # Return document metadata (not the file itself — frontend fetches signed URL separately)
    return {
        "document":   link.get("documents"),
        "expires_at": link.get("expires_at"),
    }
