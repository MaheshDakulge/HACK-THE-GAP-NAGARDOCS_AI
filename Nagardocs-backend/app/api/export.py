
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from app.core.database import get_supabase, SupabaseClient
from app.core.security import get_current_user

import io
import zipfile
import csv

router = APIRouter(prefix="/export", tags=["export"])


@router.get("/folder/{folder_id}")
async def export_folder(
    folder_id: str,
    format:    str    = Query(default="zip", enum=["zip", "csv"]),
    supabase: SupabaseClient = Depends(get_supabase),
    user:      dict   = Depends(get_current_user),
):
    """
    Exports all documents in a folder.
    ZIP mode: bundles original files + a metadata CSV inside the archive.
    CSV mode: just the metadata sheet — useful for HOD reporting.
    Mirrors the export_project() pattern from Marksheet export.py exactly.
    """
    # Verify folder belongs to user's department
    folder = (
        supabase.table("folders")
        .select("id, name")
        .eq("id", folder_id)
        .eq("department_id", user["department_id"])
        .execute()
    )
    if not folder.data:
        raise HTTPException(status_code=404, detail="Folder not found.")

    folder_name = folder.data[0]["name"]

    # Fetch all documents in this folder with their extracted fields
    docs = (
        supabase.table("documents")
        .select("*, document_fields(*), users(name, designation)")
        .eq("folder_id", folder_id)
        .order("created_at")
        .execute()
    )
    if not docs.data:
        raise HTTPException(status_code=404, detail="No documents in this folder.")

    # ── CSV metadata export ────────────────────────────────────────────────────
    if format == "csv":
        buf = io.StringIO()
        writer = csv.writer(buf)

        # Build header: fixed columns + all unique field labels across all docs
        all_labels = []
        seen = set()
        for doc in docs.data:
            for f in doc.get("document_fields", []):
                lbl = f.get("label", "")
                if lbl and lbl not in seen:
                    all_labels.append(lbl)
                    seen.add(lbl)

        header = ["Sr No", "Doc Type", "Filename", "Uploaded By", "Upload Date",
                  "Tamper Flag", "OCR Confidence"] + all_labels
        writer.writerow(header)

        for sr, doc in enumerate(docs.data, 1):
            fields_by_label = {
                f.get("label"): f.get("value", "")
                for f in doc.get("document_fields", [])
            }
            row = [
                sr,
                doc.get("doc_type", ""),
                doc.get("filename", ""),
                (doc.get("users") or {}).get("name", ""),
                str(doc.get("created_at", ""))[:10],
                "YES" if doc.get("is_tampered") else "NO",
                f"{(doc.get('ocr_confidence') or 0) * 100:.1f}%",
            ] + [fields_by_label.get(lbl, "") for lbl in all_labels]
            writer.writerow(row)

        buf.seek(0)
        safe_name = folder_name.replace(" ", "_")
        return StreamingResponse(
            iter([buf.getvalue()]),
            media_type="text/csv",
            headers={"Content-Disposition": f'attachment; filename="{safe_name}.csv"'},
        )

    # ── ZIP export ─────────────────────────────────────────────────────────────
    zip_buf = io.BytesIO()
    with zipfile.ZipFile(zip_buf, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:

        # Write metadata CSV inside the ZIP
        meta_buf = io.StringIO()
        writer   = csv.writer(meta_buf)
        writer.writerow(["Filename", "Doc Type", "Tamper Flag", "OCR Confidence",
                         "Upload Date", "Uploaded By"])
        for doc in docs.data:
            writer.writerow([
                doc.get("filename", ""),
                doc.get("doc_type", ""),
                "YES" if doc.get("is_tampered") else "NO",
                f"{(doc.get('ocr_confidence') or 0) * 100:.1f}%",
                str(doc.get("created_at", ""))[:10],
                (doc.get("users") or {}).get("name", ""),
            ])
        zf.writestr("metadata.csv", meta_buf.getvalue())

        # Fetch and bundle the actual files from Supabase Storage
        for doc in docs.data:
            storage_path = doc.get("storage_path")
            if not storage_path:
                continue
            try:
                file_bytes = supabase.storage.from_("nagardocs").download(storage_path)
                zf.writestr(doc.get("filename", "document"), file_bytes)
            except Exception as e:
                # Log but don't fail the whole export if one file is missing
                print(f"[export] Could not fetch {storage_path}: {e}")

    zip_buf.seek(0)
    safe_name = folder_name.replace(" ", "_")
    return StreamingResponse(
        iter([zip_buf.getvalue()]),
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{safe_name}.zip"'},
    )


@router.get("/document/{doc_id}")
async def export_single_document(
    doc_id:   str,
    supabase: SupabaseClient = Depends(get_supabase),
    user:     dict   = Depends(get_current_user),
):
    """
    Returns the original file bytes for a single document.
    Used by the Result screen's share / download button.
    Streams the original image or PDF directly — no conversion.
    """
    doc = (
        supabase.table("documents")
        .select("filename, storage_path")
        .eq("id", doc_id)
        .eq("department_id", user["department_id"])
        .execute()
    )
    if not doc.data:
        raise HTTPException(status_code=404, detail="Document not found.")

    storage_path = doc.data[0]["storage_path"]
    filename     = doc.data[0]["filename"]

    try:
        file_bytes = supabase.storage.from_("nagardocs").download(storage_path)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Could not retrieve file: {e}")

    # Determine content type from file extension
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "bin"
    mime_map = {
        "pdf":  "application/pdf",
        "jpg":  "image/jpeg",
        "jpeg": "image/jpeg",
        "png":  "image/png",
    }
    mime = mime_map.get(ext, "application/octet-stream")

    return StreamingResponse(
        iter([file_bytes]),
        media_type=mime,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
