# 🏛️ NagarDocs AI Backend Architecture & Security Guide

This document outlines the architecture, data flow, and bank-grade security features built into the NagarDocs AI backend. It serves as a reference for how the system processes, secures, and audits municipal government documents.

---

## 1. 🛡️ Absolute Security (The "Super-Admin" Approach)
The backend does **not** rely on frontend Row Level Security (RLS) for its core processing. Instead, the Python FastAPI server communicates with Supabase using the `SUPABASE_SERVICE_KEY`. 

This means:
* The backend acts as an omnipotent **Super-Admin**.
* It completely **bypasses RLS** during processing, ensuring background tasks (like auto-sorting and tamper checks) never fail due to frontend permission issues.
* **Privacy Controls:** Even though it bypasses RLS, the backend manually enforces privacy in the `/cabinet` endpoints. By using the `is_private` boolean, the backend intentionally hides private documents from unauthorized users, allowing only the original uploader or an `admin` to view them.

---

## 2. 🧠 The "Smart" Digitalization Pipeline (Upload Flow)
The moment a physical scan is uploaded via the `/upload` API, an asynchronous background worker (`upload.py`) takes over to prevent the user from waiting. The pipeline triggers the following live, granular steps (tracked via the `progress` JSONB column):

1. **OCR Text Extraction:** Uses Tesseract (`pytesseract`) to pull raw textual data from the physical scan.
2. **AI Classification & Extraction:** Passes the raw text and image to a strict `GPT-4o-mini` prompt. 
   * **Dynamic Targeting:** The AI is hard-coded to recognize and flawlessly extract specific fields for the **8 most common government forms**. For example, it will instantly look for `PRN`, `Semester`, and `SGPA` on Marksheets, or `Plot Number` on Land Records.
3. **Auto-Sort Classification:** The `autosort_service.py` evaluates the AI's confidence score. If it is confident (>90%), the document is instantly routed to the correct department folder (e.g., "Birth Certificates"). If unsure, it is safety-routed to a "Needs Review" folder.

---

## 3. 🔒 Cryptographic Tamper & Duplicate Prevention
Government documents must maintain an unshakeable chain of custody and integrity.
* **SHA-256 Hashing:** The `tamper_service.py` computes an irreversible cryptographic hash of the raw uploaded file bytes *immediately* upon upload.
* **Live Duplicate Blocking:** Before the document is processed, the backend queries the entire database against that exact SHA-256 hash. 
* **Tamper Flags:** If another citizen already uploaded the exact same scan, the AI attaches an aggressive `tamper_flags` note (e.g., *"Duplicate of existing document ID: XYZ"*) and marks `is_tampered = True`.

---

## 4. ✍️ The "Human-in-the-Loop" Review API
Because OCR can rarely misinterpret a smudged letter or number on a dirty physical document, the backend provides complete **Manual Verification APIs**.
* **`PUT /cabinet/documents/{doc_id}/fields`**: Allows an officer to send corrected fields (e.g., fixing a Name or SGPA) via the frontend Review screen before saving it permanently to the cabinet.
* **Image Retention Law:** We store the raw image in the Supabase `nagardocs` bucket *immediately* upon upload. This guarantees the frontend always has a physical comparison image to display side-by-side with the extracted text during the Review Step, ensuring the unedited physical truth is never lost.

---

## 5. 👁️ Administrator Oversight & Auditing
Everything is tracked automatically in the `activity_log` table. 
* The `admin.py` router strictly enforces that only users manually approved as `role: 'admin'` in the Supabase database can access it.
* **Audit Trails:** Every upload generates an immutable trail representing *who* uploaded the file and *when*. Admins can pull the entire department's history via `GET /admin/activity`.
* **User Management:** Admins can natively approve new (Pending) officers or ban malicious accounts using strictly gated endpoints (`/ban-user/{id}`, `/approve-user/{id}`).
