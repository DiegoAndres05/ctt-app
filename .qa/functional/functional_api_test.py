#!/usr/bin/env python3
"""CTTAdmin functional API QA suite — v2 (firmas RPC verificadas)."""
import json
import urllib.request
import urllib.error
import uuid

API = "http://127.0.0.1:54321"
ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
ORG_A = "00000000-0000-4000-a000-000000000001"

results = []


def call(method, path, token=None, payload=None):
    url = API + path
    body = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("apikey", ANON)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    if body:
        req.add_header("Content-Type", "application/json")
        req.add_header("Prefer", "return=representation")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return r.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw
    except Exception as e:
        return -1, str(e)


def rpc(name, payload, token=None):
    return call("POST", f"/rest/v1/rpc/{name}", token, payload)


def rid(d):
    return d.get("id") if isinstance(d, dict) else (d if isinstance(d, str) else None)


def msg(d):
    return d.get("message", "") if isinstance(d, dict) else ""


def login(email, pwd):
    st, d = call("POST", "/auth/v1/token?grant_type=password", None,
                 {"email": email, "password": pwd})
    return d.get("access_token") if st == 200 else None


def check(tid, desc, cond, detail=""):
    results.append((tid, desc, "PASS" if cond else "FAIL", detail))
    print(f"{'PASS' if cond else 'FAIL'} {tid} {desc} {detail}")


# ── tokens ──
tk_admin = login("admin@demo-turismo.test", "DemoPass123!")
tk_oper = login("operador@demo-turismo.test", "DemoPass123!")
tk_agent = login("agente@demo-turismo.test", "DemoPass123!")
tk_b = login("agencia2@gmail.com", "OrgB-Admin123!")

check("T001", "Login admin Org A", bool(tk_admin))
check("T002", "Login operador Org A", bool(tk_oper))
check("T003", "Login agente Org A", bool(tk_agent))
check("T004", "Login admin Org B", bool(tk_b))

st, d = call("POST", "/auth/v1/token?grant_type=password", None,
             {"email": "admin@demo-turismo.test", "password": "mala"})
check("T005", "Login password incorrecta → 400", st == 400, f"status={st}")

st, _ = call("GET", "/rest/v1/organizations?select=id", None)
check("T006", "GET anon tablas protegidas → 401", st == 401, f"status={st}")

# ── RBAC ──
st, d = rpc("create_product", {
    "p_type": "experience", "p_name": "QA RBAC operador",
    "p_description": "temp", "p_category_ids": [],
    "p_experience": {"duration_minutes": 60, "min_capacity": 1, "max_capacity": 8}}, tk_oper)
pid_oper = rid(d) if st == 200 else None
check("T010", "operador crea producto → OK", bool(pid_oper), f"st={st} msg={msg(d)[:80]}")

st, d = rpc("create_product", {
    "p_type": "experience", "p_name": "QA RBAC agente",
    "p_description": "temp", "p_category_ids": [],
    "p_experience": {"duration_minutes": 60, "min_capacity": 1, "max_capacity": 8}}, tk_agent)
check("T011", "agente crea producto → FORBIDDEN", st == 403 and "PERMISSION" in msg(d).upper(), f"st={st} msg={msg(d)[:80]}")

st, d = rpc("create_internal_user", {
    "p_full_name": "QA X", "p_email": f"qa-rbac-{uuid.uuid4().hex[:8]}@test.com",
    "p_role": "agent", "p_temporary_password": "TempPass123!"}, tk_oper)
check("T012", "operador crea usuario → FORBIDDEN", st == 403, f"st={st} msg={msg(d)[:80]}")

st, d = call("GET", "/rest/v1/products?select=id&limit=1", tk_agent)
check("T013", "agente lee productos → OK", st == 200, f"status={st}")

st, d = rpc("save_public_category", {"p_payload": {
    "id": "qa_no_auth", "name_es": "X", "name_en": "X", "is_active": False}}, tk_agent)
check("T014", "agente guarda categoría pública → FORBIDDEN", st == 403, f"st={st} msg={msg(d)[:80]}")

st, d = rpc("complete_public_cutover", {}, tk_oper)
check("T015", "operador ejecuta cutover → FORBIDDEN", st == 403, f"st={st} msg={msg(d)[:80]}")

# ── CRUD + validaciones ──
st, d = rpc("create_product", {"p_type": "INVALID_TYPE", "p_name": "X",
                               "p_category_ids": [], "p_experience": {}}, tk_admin)
check("T020", "producto tipo inválido → VALIDATION_ERROR", st == 400 and msg(d) == "VALIDATION_ERROR", f"st={st} msg={msg(d)[:60]}")

st, d = rpc("create_product", {
    "p_type": "experience", "p_name": "QA E2E producto temporal",
    "p_description": "temporal para auditoria", "p_category_ids": [],
    "p_experience": {"duration_minutes": 120, "min_capacity": 1, "max_capacity": 10}}, tk_admin)
pid_qa = rid(d) if st == 200 else None
check("T021", "crear experiencia válida → OK", bool(pid_qa), f"st={st} msg={msg(d)[:80]}")

st, d = rpc("set_product_status", {"p_product_id": pid_qa, "p_status": "active"}, tk_admin)
check("T022", "activar sin precio → PRODUCT_HAS_NO_VALID_PRICE", st == 400 and msg(d) == "PRODUCT_HAS_NO_VALID_PRICE", f"st={st} msg={msg(d)[:80]}")

st, d = rpc("upsert_pricing_scheme", {
    "p_product_id": pid_qa, "p_currency": "COP", "p_base_amount": 50000,
    "p_charge_type": "per_person"}, tk_admin)
check("T023", "crear esquema de precio → OK", st == 200, f"st={st} msg={msg(d)[:80]}")

st, d = rpc("set_product_status", {"p_product_id": pid_qa, "p_status": "active"}, tk_admin)
check("T024", "activar con precio → OK", st == 200, f"st={st} msg={msg(d)[:80]}")

st, d = rpc("create_package", {
    "p_name": "QA paquete", "p_description": "temp", "p_total_days": 1, "p_total_nights": 0,
    "p_items": [{"component_product_id": pid_qa, "day_number": 1, "sort_order": 1}]}, tk_admin)
pid_pkg = rid(d) if st == 200 else None
check("T025", "crear paquete con 1 producto → OK", bool(pid_pkg), f"st={st} msg={msg(d)[:80]}")

st, d = rpc("create_package", {
    "p_name": "QA paquete nesting", "p_total_days": 1, "p_total_nights": 0,
    "p_items": [{"component_product_id": pid_pkg, "day_number": 1, "sort_order": 1}]}, tk_admin)
check("T026", "paquete dentro de paquete → PACKAGE_NESTING_NOT_ALLOWED", st == 400 and msg(d) == "PACKAGE_NESTING_NOT_ALLOWED", f"st={st} msg={msg(d)[:80]}")

# ── multi-tenant ──
st, d = call("GET", "/rest/v1/products?select=id,name", tk_b)
names = [r.get("name", "") for r in (d or [])]
leak = [n for n in names if "QA E2E" in n or "QA RBAC" in n or "manifiesto" in n]
check("T030", "Org B no ve productos Org A", st == 200 and not leak, f"st={st} leak={leak[:3]}")

st, d = call("GET", f"/rest/v1/products?id=eq.{pid_qa}&select=id", tk_b)
check("T031", "Org B lee producto Org A por id → vacío", st == 200 and d == [], f"st={st} d={str(d)[:60]}")

st, d = rpc("set_product_status", {"p_product_id": pid_qa, "p_status": "inactive"}, tk_b)
check("T032", "Org B modifica producto Org A → VALIDATION_ERROR (not-found org-scoped, sin fuga)",
      st == 400 and msg(d) == "VALIDATION_ERROR", f"st={st} msg={msg(d)[:80]}")

st, d = call("GET", "/rest/v1/user_profiles?select=id", tk_b)
leak2 = [r for r in (d or []) if r.get("id") in ("00000000-0000-4000-b000-000000000001",)]
check("T033", "Org B no ve perfiles Org A", st == 200 and not leak2, f"st={st} leak={leak2}")

# ── feature 009 ──
st, d = call("GET", "/rest/v1/public_categories?select=id", tk_admin)
check("T040", "listar categorías públicas → OK", st == 200 and isinstance(d, list), f"st={st} count={len(d) if isinstance(d, list) else '?'}")

st, d = rpc("save_public_category", {"p_payload": {
    "id": "qa_cat_tmp", "name_es": "QA cat tmp", "name_en": "QA cat tmp", "is_active": False}}, tk_admin)
ok41 = st == 200 and isinstance(d, dict) and d.get("id") == "qa_cat_tmp"
check("T041", "crear categoría pública (bilingüe) → OK", ok41, f"st={st} d={str(d)[:80]}")

st, d = rpc("save_public_category", {"p_payload": {
    "id": "qa_cat_tmp", "name_es": "solo_es", "name_en": "", "is_active": False}}, tk_admin)
check("T042", "categoría sin par bilingüe → BILINGUAL_PAIR_INCOMPLETE", st == 400 and msg(d) == "BILINGUAL_PAIR_INCOMPLETE", f"st={st} msg={msg(d)[:80]}")

st, d = rpc("complete_public_cutover", {}, tk_admin)
check("T043", "cutover repetido → CUTOVER_ALREADY_COMPLETED", st == 400 and msg(d) == "CUTOVER_ALREADY_COMPLETED", f"st={st} msg={msg(d)[:80]}")

st, d = rpc("get_public_site", {"p_organization_id": ORG_A}, None)
src = (d or {}).get("source") if isinstance(d, dict) else None
n_off = len((d or {}).get("offers", []) or []) if isinstance(d, dict) else -1
check("T044", "get_public_site anon → source=panel", st == 200 and src == "panel", f"st={st} src={src} offers={n_off}")

st, d = rpc("save_public_listing", {"p_payload": {
    "product_id": pid_qa, "placement": "catalog",
    "public_slug": f"qa-e2e-{uuid.uuid4().hex[:6]}", "currency": "COP",
    "display_price": None, "status": "draft"}}, tk_admin)
lid = rid(d) if st == 200 else None
st_p, d_p = rpc("publish_public_listing", {"p_listing_id": lid}, tk_admin)
check("T045", "publicar draft incompleto → PUBLIC_LISTING_INCOMPLETE",
      bool(lid) and st_p == 400 and msg(d_p) == "PUBLIC_LISTING_INCOMPLETE",
      f"st={st} lid={lid} st_pub={st_p} msg={msg(d_p)[:80]}")

# ── manejo de errores / edge cases ──
st, d = rpc("get_public_site", {"p_wrong_param": "x"}, None)
check("T050", "RPC con params inválidos → 404 PGRST202", st == 404 and d.get("code") == "PGRST202", f"st={st}")

req_st = -1
try:
    req = urllib.request.Request(API + "/rest/v1/rpc/create_product", data=b"{not json", method="POST")
    req.add_header("apikey", ANON)
    req.add_header("Content-Type", "application/json")
    urllib.request.urlopen(req, timeout=10)
except urllib.error.HTTPError as e:
    req_st = e.code
except Exception:
    req_st = -2
check("T051", "JSON malformado → 400", req_st == 400, f"st={req_st}")

st, d = rpc("create_product", {"p_type": "experience", "p_name": "X"}, None)
check("T052", "RPC protegida sin token → 401", st == 401, f"st={st}")

st, d = call("GET", "/rest/v1/rpc/set_product_status", tk_agent, "GET")
check("T053", "método no permitido → 4xx", st >= 400 and st < 500, f"st={st}")

st, d = rpc("create_product", {"p_type": "experience", "p_name": "   ",
                               "p_experience": {"duration_minutes": 1, "min_capacity": 1, "max_capacity": 1}}, tk_admin)
check("T054", "nombre vacío → VALIDATION_ERROR", st == 400 and msg(d) == "VALIDATION_ERROR", f"st={st} msg={msg(d)[:60]}")

print("\n=== RESUMEN ===")
p = sum(1 for r in results if r[2] == "PASS")
f = sum(1 for r in results if r[2] == "FAIL")
for tid, desc, res, detail in results:
    if res == "FAIL":
        print(f"FAIL {tid} {desc} :: {detail}")
print(f"\n{p} PASS / {f} FAIL / {len(results)} total")
print(f"\nCREADOS: pid_oper={pid_oper} pid_qa={pid_qa} pid_pkg={pid_pkg} listing={lid}")
