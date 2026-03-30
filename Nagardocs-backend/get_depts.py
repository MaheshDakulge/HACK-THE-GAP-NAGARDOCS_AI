import sys
import os
sys.path.insert(0, os.getcwd())

from app.core.database import get_supabase_sync

supabase = get_supabase_sync()
res = supabase.table("departments").select("id, code, name").execute()
print("\n--- VALID DEPARTMENTS ---")
for r in res.data:
    print(f"Code: {r['code']} | ID: {r['id']}")
print("-------------------------\n")
