#!/usr/bin/env python3
"""Local evidence runner. No shell evaluation, remote DB, reset or existing cleanup.

Usage: python3 scripts/orchestration/checks.py inventory|unit|sql|agents|smoke
`sql` requires --authorize-disposable for this invocation, AFTER user consent.
Evidence directories are unique; failures retain their real exit status.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[2]
AGENTS = ["ctt-release-orchestrator", "ctt-local-e2e", "ctt-integration-engineer",
          "ctt-staging-validator", "ctt-release-engineer", "ctt-quality-gate-auditor"]


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def capture(argv):
    return subprocess.check_output(argv, cwd=ROOT, text=True).strip()


def manifest():
    paths = capture(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"]).split("\0")
    hashes = {}
    for name in sorted(set(paths)):
        if not name or name.startswith(("docs/orchestration/evidence/", "docs/qa/reports/evidence/")):
            continue
        path = ROOT / name
        if path.is_file() and not path.is_symlink() and not re.search(r"(^|/)(\.env|auth\.json)|\.pem$", name):
            hashes[name] = sha(path)
    return {"head": capture(["git", "rev-parse", "HEAD"]),
            "status": capture(["git", "status", "--short"]), "sha256": hashes}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("mode", choices=["inventory", "unit", "sql", "agents", "smoke", "reconcile", "delegate"])
    ap.add_argument("--prompt-file", type=Path)
    ap.add_argument("--authorize-disposable", action="store_true")
    ap.add_argument("--model", default="openai/gpt-6-astra",
                    help="provider/model for smoke|delegate (must exist in `opencode models`)")
    ap.add_argument("--timeout", type=int, default=600, help="seconds for smoke|delegate")
    args = ap.parse_args()
    if args.mode == "sql" and not args.authorize_disposable:
        ap.error("SQL requires explicit user consent and --authorize-disposable for this run")
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid4().hex[:8]
    evidence = ROOT / "docs/orchestration/evidence" / (args.mode + "-" + run_id)
    evidence.mkdir(parents=True, exist_ok=False)
    result = {"run_id": run_id, "mode": args.mode, "started": now(),
              "baseline": manifest(), "commands": [], "exit_code": 1}
    print(f"Evidence: {evidence.relative_to(ROOT)}", flush=True)

    def run(argv, stdin=None, timeout=180, check=True):
        n = len(result["commands"])
        started = now()
        try:
            proc = subprocess.run(argv, input=stdin, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, cwd=ROOT, timeout=timeout)
            output, code = proc.stdout.decode(errors="replace"), proc.returncode
        except subprocess.TimeoutExpired as error:
            output, code = (error.stdout or b"").decode(errors="replace") + "\nTIMEOUT\n", 124
        logfile = f"{n:03d}.log"
        (evidence / logfile).write_text(output)
        result["commands"].append({"argv": argv, "started": started, "finished": now(),
                                   "exit_code": code, "log": logfile})
        print(f"[{code}] {' '.join(argv[:6])} -> {logfile}", flush=True)
        if check and code:
            raise RuntimeError(f"Command failed ({code}), inspect {evidence / logfile}")
        return output, code

    try:
        if args.mode == "inventory":
            for command in (["opencode", "--version"], ["node", "--version"], ["npm", "--version"],
                            ["git", "diff", "--check"], ["git", "diff", "--stat"],
                            ["opencode", "models", "openai"]):
                run(command)
        elif args.mode == "unit":
            pkg = json.loads((ROOT / "package.json").read_text())
            if pkg["scripts"].get("test") != "ng test" or any(k in pkg["scripts"] for k in ("pretest", "posttest")):
                raise RuntimeError("Test scripts changed: inspect before executing")
            run(["npm", "test", "--", "--watch=false"], timeout=300)
        elif args.mode == "sql":
            # Reject remote Docker authority; no ports, host mounts or existing DB used.
            if os.environ.get("DOCKER_HOST") or os.environ.get("DOCKER_CONTEXT"):
                raise RuntimeError("Explicit Docker environment override: inspect and remove before running")
            context = capture(["docker", "context", "show"])
            endpoint = capture(["docker", "context", "inspect", context,
                                "--format", "{{.Endpoints.docker.Host}}"])
            if not endpoint.startswith("unix://"):
                raise RuntimeError("Only a verified local Unix Docker socket is allowed")
            docker = ["docker", "--context", context]
            image, _ = run(docker + ["image", "inspect", "postgres:17-alpine", "--format", "{{.Id}}"])
            name = "ctt-release-qa-" + run_id.lower()
            result["destination"] = {"context": context, "endpoint": endpoint,
                                     "name": name, "image": image.strip(), "ports": [],
                                     "volumes": [], "network": "none"}
            cid = None
            try:
                output, _ = run(docker + ["run", "-d", "--name", name,
                    "--label", f"ctt.release.run={run_id}", "--network", "none",
                    "--tmpfs", "/var/lib/postgresql/data:rw", "--env", "POSTGRES_PASSWORD=qa-disposable-only",
                    image.strip()])
                cid = output.strip()
                if not re.fullmatch(r"[0-9a-f]{64}", cid):
                    raise RuntimeError("Unexpected container identity; do not clean up by name")
                result["destination"]["id"] = cid
                psql = docker + ["exec", "-i", cid, "psql", "--username", "postgres", "--dbname", "postgres",
                                "--no-psqlrc", "--quiet", "--set", "ON_ERROR_STOP=1"]
                ready = 0
                for _ in range(120):
                    _, code = run(psql + ["-Atc", "SELECT 1"], check=False)
                    ready = ready + 1 if code == 0 else 0
                    if ready >= 3:
                        break
                    time.sleep(.5)
                if ready < 3:
                    raise RuntimeError("PostgreSQL not ready")
                files = sorted((ROOT / "supabase/tests/harness").glob("*.sql"))
                files += sorted((ROOT / "supabase/migrations").glob("*.sql"))
                files += [ROOT / "supabase/seed.sql"]
                suites = sorted((ROOT / "supabase/tests").glob("*_test.sql"))
                result["suites_total"] = len(suites)
                result["suites_passed"] = []
                for path in files + suites:
                    run(psql, stdin=path.read_bytes())
                    result["commands"][-1]["sql_file"] = str(path.relative_to(ROOT))
                    result["commands"][-1]["sha256"] = sha(path)
                    if path in suites:
                        result["suites_passed"].append(path.name)
            finally:
                if cid and re.fullmatch(r"[0-9a-f]{64}", cid):
                    label, _ = run(docker + ["inspect", cid, "--format", '{{index .Config.Labels "ctt.release.run"}}'])
                    if label.strip() != run_id:
                        raise RuntimeError("Ownership mismatch: cleanup refused")
                    run(docker + ["rm", "--force", cid])
                    result["cleanup"] = "removed exact owned container; tmpfs data discarded"
        elif args.mode == "agents":
            configs = {}
            for name in AGENTS:
                output, _ = run(["opencode", "debug", "agent", name])
                cfg = json.loads(output)
                assert cfg["mode"] == ("primary" if name == AGENTS[0] else "subagent"), name
                assert cfg["native"] is False, name
                assert cfg.get("prompt") and cfg.get("description"), name
                configs[name] = cfg
            def permission(cfg, action, resource):
                effect = "ask"
                for rule in cfg["permission"]:
                    def matches(pattern, value):
                        return re.fullmatch(re.escape(pattern).replace(r"\*", ".*"), value) is not None
                    if matches(rule["permission"], action) and matches(rule["pattern"], resource):
                        effect = rule["action"]
                return effect
            # Assertions on rules resolved by the actual installed OpenCode loader.
            auditor = configs[AGENTS[-1]]
            for action in ("edit", "bash", "task", "gsap-master_anything"):
                assert permission(auditor, action, "*") == "deny", action
            primary = configs[AGENTS[0]]
            assert permission(primary, "task", "general") == "deny"
            for name in AGENTS[1:]:
                assert permission(primary, "task", name) == "allow", name
                assert permission(configs[name], "task", "general") == "deny", name
            for cfg in configs.values():
                assert permission(cfg, "external_directory", "/unapproved/location/*") == "ask"
                assert permission(cfg, "bash", "git push origin main") != "allow"
                assert permission(cfg, "bash", "supabase db reset --linked") == "deny"
            result["permission_checks"] = "PASS: six loaded; modes, auditor denials, delegation allowlist, external and remote controls"
        elif args.mode == "reconcile":
            comparisons = []
            current = result["baseline"]["sha256"]
            for prior in sorted((ROOT / "docs/orchestration/evidence").glob("*/result.json")):
                old = json.loads(prior.read_text())
                if old["mode"] not in ("unit", "sql"):
                    continue
                changes = [name for name, digest in old["baseline"]["sha256"].items()
                           if name.startswith(("src/", "supabase/")) or name in
                           ("package.json", "package-lock.json", "angular.json", "tsconfig.json", "tsconfig.app.json", "tsconfig.spec.json")
                           if current.get(name) != digest]
                comparisons.append({"source": str(prior.relative_to(ROOT)), "tested_head": old["baseline"]["head"],
                                    "current_head": result["baseline"]["head"], "changed_test_inputs": changes,
                                    "source_exit_code": old["exit_code"],
                                    "suites_total": old.get("suites_total"),
                                    "suites_passed": len(old.get("suites_passed", []))})
                if changes:
                    raise RuntimeError(f"Test inputs changed since {prior}: {changes}")
            result["comparisons"] = comparisons
            print(json.dumps(comparisons, indent=2))
        elif args.mode in ("smoke", "delegate"):
            prompt = ("SMOKE DE CONFIGURACION, no ejecutar ninguna fase ni pruebas de producto. "
                "Usa task para invocar realmente a cada uno de tus cinco subagentes configurados "
                "(ctt-local-e2e, ctt-integration-engineer, ctt-staging-validator, ctt-release-engineer, "
                "ctt-quality-gate-auditor). Cada uno debe leer docs/orchestration/QUALITY-GATES.md "
                "y devolver su AGENTE, FASE, alcance, prerrequisito y un criterio con referencia. "
                "No editar archivos ni ejecutar shell, no tocar BD, no fase3/4/5. "
                "Esto solo comprueba descubrimiento/invocacion de perfiles reales. "
                "Al terminar informa los cinco task/session IDs y confirma que ninguno aprueba gates.")
            if args.mode == "delegate":
                if not args.prompt_file:
                    raise RuntimeError("delegate requires --prompt-file within docs/orchestration")
                path = args.prompt_file.resolve()
                if not path.is_relative_to(ROOT / "docs/orchestration"):
                    raise RuntimeError("Prompt must be within docs/orchestration")
                prompt = path.read_text()
            output, _ = run(["opencode", "run", "--agent", AGENTS[0], "-m", args.model,
                              "--format", "json", prompt], timeout=args.timeout)
            result["model"] = args.model
            events = [json.loads(line) for line in output.splitlines() if line.startswith("{")]
            if any(e.get("type") == "error" for e in events):
                raise RuntimeError("Model/runtime error; CLI exit alone is insufficient")
            invoked = set()
            responses = []
            for event in events:
                part = event.get("part", {})
                state = part.get("state", {})
                if part.get("tool") == "task" and state.get("status") == "completed":
                    invoked.add(state.get("input", {}).get("subagent_type"))
                    responses.append({"agent": state.get("input", {}).get("subagent_type"),
                                      "metadata": state.get("metadata"), "output": state.get("output")})
            (evidence / "child-responses.json").write_text(json.dumps(responses, indent=2) + "\n")
            result["invoked_subagents"] = sorted(x for x in invoked if x)
            if args.mode == "smoke" and not set(AGENTS[1:]).issubset(invoked):
                raise RuntimeError("Missing completed child tasks; inspect runtime event log")
            if args.mode == "delegate" and not invoked:
                raise RuntimeError("No completed child task: delegation not demonstrated")
        result["exit_code"] = 0
    except Exception as error:
        result["error"] = str(error)
        print(str(error), file=sys.stderr)
    finally:
        result["finished"] = now()
        (evidence / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
