
from fastapi import APIRouter, Depends, HTTPException, Query
from typing import List, Optional
from app.core.database import get_supabase, SupabaseClient
from app.core.security import get_current_user
from app.schemas.search_schema import SearchResultResponse

import re

router = APIRouter(prefix="/search", tags=["search"])


def _highlight(text: str, query: str) -> str:
    """
    Wraps all case-insensitive occurrences of 'query' in 'text' with ^^ markers.
    Flutter's RichText widget can split on ^^ to render highlighted spans.
    """
    if not text or not query:
        return text or ""
    pattern = re.compile(re.escape(query), re.IGNORECASE)
    return pattern.sub(lambda m: f"^^{m.group()}^^", text)


def _build_highlights(doc: dict, query: str) -> list:
    """Produces a list of highlight objects across all searchable fields."""
    highlights = []

    # Search in doc_type
    if doc.get("doc_type") and query.lower() in doc["doc_type"].lower():
        highlights.append({
            "field":   "Document Type",
            "value":   doc["doc_type"],
            "snippet": _highlight(doc["doc_type"], query),
        })

    # Search in filename
    if doc.get("filename") and query.lower() in doc["filename"].lower():
        highlights.append({
            "field":   "Filename",
            "value":   doc["filename"],
            "snippet": _highlight(doc["filename"], query),
        })

    # Search inside extracted fields (Name, Date, Issue Authority, etc.)
    for field in doc.get("document_fields", []):
        val = field.get("value") or ""
        if query.lower() in val.lower():
            highlights.append({
                "field":   field.get("label", "Field"),
                "value":   val,
                "snippet": _highlight(val, query),
            })

    return highlights


@router.get("", response_model=List[SearchResultResponse])
async def search_documents(
    q:         str            = Query(..., min_length=1, description="Search query"),
    doc_type:  Optional[str]  = Query(default=None, description="Filter by document type"),
    folder_id: Optional[str]  = Query(default=None, description="Limit search to one folder"),
    limit:     int            = Query(default=20, le=100),
    offset:    int            = Query(default=0),
    supabase: SupabaseClient = Depends(get_supabase),
    user:      dict           = Depends(get_current_user),
):
    """
    Full-text search across all documents in the user's department.

    Strategy: Supabase's full-text search on document_fields.value using
    Postgres 'ilike' for simplicity — sufficient for the doc volumes in a
    government department cabinet. Can be upgraded to pg_trgm or tsvector
    for larger deployments.

    Flutter calls this on every keystroke with a 300ms debounce.
    """
    if not q.strip():
        return []

    # First fetch candidate documents where any field matches the query.
    # We use .ilike on doc_type + filename as a first pass, then match
    # document_fields in Python (Supabase JS client supports this natively
    # but the Python client is easier to filter post-fetch for now).
    base_query = (
        supabase.table("documents")
        .select("*, document_fields(*), users(name), folders(name)")
    )
    # If user has no department_id (legacy/unassigned), scope to their own docs
    if user.get("department_id"):
        base_query = base_query.eq("department_id", user["department_id"])
    else:
        base_query = base_query.eq("user_id", user["id"])

    if doc_type:
        base_query = base_query.eq("doc_type", doc_type)
    if folder_id:
        base_query = base_query.eq("folder_id", folder_id)

    # Broad fetch — we'll filter precisely in Python for highlight quality.
    all_docs = base_query.order("created_at", desc=True).limit(50).execute()

    results = []
    q_lower = q.strip().lower()

    for doc in (all_docs.data or []):
        # Check if query matches doc_type, filename, or any extracted field
        searchable = (
            (doc.get("doc_type") or "").lower() + " " +
            (doc.get("filename") or "").lower() + " " +
            " ".join(
                (f.get("value") or "").lower()
                for f in doc.get("document_fields", [])
            )
        )
        if q_lower not in searchable:
            continue

        highlights = _build_highlights(doc, q.strip())
        if not highlights:
            continue

        results.append({
            **doc,
            "match_highlights": highlights,
            "folder_name":      (doc.get("folders") or {}).get("name", ""),
            "uploaded_by":      (doc.get("users")   or {}).get("name", ""),
        })

    # Paginate in Python (move to DB-level pagination in production)
    return results[offset: offset + limit]
