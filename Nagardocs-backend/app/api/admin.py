from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Optional
from datetime import datetime, timedelta, timezone

from app.core.database import get_supabase
from app.core.security import get_current_admin

router = APIRouter(prefix="/admin", tags=["admin"])


# =========================================================
# 🟢 TAB 1: PRESENCE (ONLINE USERS)
# =========================================================
@router.get("/presence")
async def get_presence(supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    now = datetime.now(timezone.utc)
    cutoff_online = (now - timedelta(minutes=5)).isoformat()
    cutoff_away   = (now - timedelta(minutes=30)).isoformat()

    query = supabase.table("users").select("id, name, designation, last_seen, role")
    
    dept = admin.get("department_id")
    if dept:
        query = query.eq("department_id", dept)

    users = query.execute()

    result = []

    for user_item in (users.data or []):
        last_seen = user_item.get("last_seen") or ""

        if last_seen >= cutoff_online:
            status = "online"
        elif last_seen >= cutoff_away:
            status = "away"
        else:
            status = "offline"

        result.append({**user_item, "presence_status": status})

    order = {"online": 0, "away": 1, "offline": 2}
    result.sort(key=lambda x: order[x["presence_status"]])

    return result


# =========================================================
# 📊 TAB 2: ACTIVITY FEED
# =========================================================
@router.get("/activity")
async def get_activity(supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    query = supabase.table("upload_jobs").select(
        "id, status, error_message, created_at, filename, users(name)"
    )
    
    dept = admin.get("department_id")
    if dept:
        query = query.eq("department_id", dept)

    jobs = query.order("created_at", desc=True).limit(20).execute()

    return jobs.data or []


# =========================================================
# 🚨 TAB 3: SECURITY ALERTS
# =========================================================
@router.get("/security")
async def get_security_alerts(supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    dept = admin.get("department_id")

    # 🚨 Tampered documents
    tamper_query = supabase.table("documents").select(
        "id, filename, doc_type, tamper_flags, created_at, users(name)"
    ).eq("is_tampered", True)
    if dept:
        tamper_query = tamper_query.eq("department_id", dept)
    tampered_docs = tamper_query.order("created_at", desc=True).limit(10).execute()

    # ❌ Failed jobs
    jobs_query = supabase.table("upload_jobs").select(
        "id, filename, error_message, created_at, users(name)"
    ).eq("status", "failed")
    if dept:
        jobs_query = jobs_query.eq("department_id", dept)
    failed_jobs = jobs_query.order("created_at", desc=True).limit(10).execute()

    # 🛌 Stale or suspicious accounts
    now = datetime.now(timezone.utc)
    stale_cutoff = (now - timedelta(days=30)).isoformat()
    
    stale_query = supabase.table("users").select(
        "id, name, email, last_seen, status"
    ).lt("last_seen", stale_cutoff)
    if dept:
        stale_query = stale_query.eq("department_id", dept)
    stale_users = stale_query.execute()

    return {
        "tampered_documents": tampered_docs.data or [],
        "failed_jobs": failed_jobs.data or [],
        "stale_accounts": stale_users.data or [],
        "summary": {
            "tamper_count": len(tampered_docs.data or []),
            "failed_count": len(failed_jobs.data or []),
            "stale_count": len(stale_users.data or []),
        },
    }


# =========================================================
# 👑 ADMIN ACTIONS
# =========================================================
@router.post("/resolve-tamper/{doc_id}")
async def resolve_tamper_flag(doc_id: str, supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    doc = (
        supabase.table("documents")
        .select("id, filename")
        .eq("id", doc_id)
        .eq("department_id", admin["department_id"])
        .execute()
    )

    if not doc.data:
        raise HTTPException(404, "Document not found")

    supabase.table("documents").update({
        "is_tampered": False,
        "tamper_flags": []
    }).eq("id", doc_id).execute()

    return {"message": "Tamper flag cleared"}


@router.post("/ban-user/{user_id}")
async def ban_user(user_id: str, supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    if user_id == admin["id"]:
        raise HTTPException(400, "Cannot ban yourself")

    supabase.table("users").update({"status": "banned"}).eq("id", user_id).execute()

    return {"message": "User banned"}


@router.post("/approve-user/{user_id}")
async def approve_user(user_id: str, supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    if user_id == admin["id"]:
        raise HTTPException(400, "Cannot approve yourself")

    supabase.table("users").update({"status": "verified"}).eq("id", user_id).execute()

    return {"message": "User approved"}


@router.post("/promote-user/{user_id}")
async def promote_user(user_id: str, supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    if user_id == admin["id"]:
        raise HTTPException(400, "Cannot promote yourself")

    supabase.table("users").update({"role": "admin"}).eq("id", user_id).execute()

    return {"message": "User promoted to admin"}


@router.get("/users")
async def list_users(
    status: Optional[str] = Query(default=None),
    supabase=Depends(get_supabase),
    admin: dict = Depends(get_current_admin),
):
    query = supabase.table("users").select("*")
    
    dept = admin.get("department_id")
    if dept:
        query = query.eq("department_id", dept)

    if status:
        query = query.eq("status", status)

    result = query.execute()
    return result.data or []