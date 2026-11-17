#!/usr/bin/env python3
"""Reproducible local checks; SQL needs current explicit consent for owned resources.

python3 scripts/orchestration/checks.py unit|sql|agents|delegate
SQL: --authorize-disposable. Delegation: --prompt-file docs/orchestration/handoff.md
No shell evaluation, deployment, reset, existing-container cleanup or remote DB.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[2]
NAMES = ["ctt-release-orchestrator", "ctt-local-e2e", "ctt-integration-engineer",
         "ctt-staging-validator", "ctt-release-engineer", "ctt-quality-gate-auditor"]


def capture(args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["unit", "sql", "agents", "delegate"])
    parser.add_argument("--authorize-disposable", action="store_true")
    parser.add_argument("--prompt-file", type=Path)
    args = parser.parse_args()
    if args.mode == "sql" and not args.authorize_disposable:
        parser.error("Obtain user consent for new disposable resources, then pass --authorize-disposable")
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid4().hex[:8]
    out = ROOT / "docs/orchestration/evidence" / (args.mode + "-" + run_id)
    out.mkdir(parents=True, exist_ok=False)
    result = {"run_id": run_id, "mode": args.mode, "head": capture(["git", "rev-parse", "HEAD"]),
              "branch": capture(["git", "branch", "--show-current"]),
              "status": capture(["git", "status", "--short"]), "commands": [], "exit_code": 1}
    inputs = sorted(p for folder in ("src", "supabase") for p in (ROOT / folder).rglob("*")
                    if p.is_file() and not p.is_symlink() and ".temp" not in p.parts
                    and p.suffix in (".ts", ".html", ".scss", ".sql", ".toml"))
    inputs += [ROOT / p for p in ("package.json", "package-lock.json", "angular.json", "tsconfig.json")]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    (out / "input-hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
    print(f"Evidence: {out.relative_to(ROOT)}", flush=True)

    def run(argv, data=None, timeout=180, check=True, label=None):
        started = datetime.now(timezone.utc).isoformat()
        try:
            process = subprocess.run(argv, input=data, cwd=ROOT, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, timeout=timeout)
            text, code = process.stdout.decode(errors="replace"), process.returncode
        except subprocess.TimeoutExpired as error:
            text, code = (error.stdout or b"").decode(errors="replace") + "\nTIMEOUT", 124
        # API errors may include provider-private response headers; preserve only diagnosis.
        if argv[0] == "opencode" and "run" in argv:
            lines = []
            for line in text.splitlines():
                try:
                    event = json.loads(line)
                    if event.get("type") == "error":
                        info = event.get("error", {}).get("data", {})
                        event["error"] = {"message": info.get("message"), "statusCode": info.get("statusCode")}
                    lines.append(json.dumps(event))
                except ValueError:
                    lines.append(line)
            text = "\n".join(lines)
        filename = f"{len(result['commands']):03d}.txt"
        (out / filename).write_text(text)
        result["commands"].append({"argv": argv, "label": label, "started": started,
                                   "exit_code": code, "output": filename})
        print(f"[{code}] {label or ' '.join(argv[:4])} -> {filename}", flush=True)
        if check and code:
            raise RuntimeError(f"Failed command: {filename}, exit {code}")
        return text, code

    try:
        if args.mode == "unit":
            pkg = json.loads((ROOT / "package.json").read_text())["scripts"]
            if pkg.get("test") != "ng test" or "pretest" in pkg or "posttest" in pkg:
                raise RuntimeError("Inspect changed test scripts before execution")
            run(["npm", "test", "--", "--watch=false"], timeout=300)
        elif args.mode == "sql":
            if os.environ.get("DOCKER_HOST") or os.environ.get("DOCKER_CONTEXT"):
                raise RuntimeError("Docker environment overrides require inspection")
            context = capture(["docker", "context", "show"])
            endpoint = capture(["docker", "context", "inspect", context, "--format", "{{.Endpoints.docker.Host}}"])
            if not endpoint.startswith("unix://"):
                raise RuntimeError("Refusing nonlocal Docker endpoint")
            docker = ["docker", "--context", context]
            image = capture(docker + ["image", "inspect", "postgres:17-alpine", "--format", "{{.Id}}"])
            result["destination"] = {"endpoint": endpoint, "image": image, "network": "none", "host_mounts": []}
            cid = None
            try:
                text, _ = run(docker + ["run", "-d", "--name", "ctt-release-qa-" + run_id.lower(),
                    "--label", "ctt.release.run=" + run_id, "--network", "none",
                    "--tmpfs", "/var/lib/postgresql/data:rw", "--env", "POSTGRES_PASSWORD=qa-disposable-only", image])
                cid = text.strip()
                if not re.fullmatch("[a-f0-9]{64}", cid):
                    raise RuntimeError("Unexpected container identity")
                result["destination"]["id"] = cid
                sql = docker + ["exec", "-i", cid, "psql", "-U", "postgres", "-d", "postgres", "-X", "-q", "-v", "ON_ERROR_STOP=1"]
                successes = 0
                for _ in range(120):
                    _, code = run(sql + ["-Atc", "SELECT 1"], check=False, label="readiness")
                    successes = successes + 1 if code == 0 else 0
                    if successes >= 3:
                        break
                    time.sleep(.5)
                if successes < 3:
                    raise RuntimeError("Database readiness timeout")
                setup = sorted((ROOT / "supabase/tests/harness").glob("*.sql"))
                setup += sorted((ROOT / "supabase/migrations").glob("*.sql")) + [ROOT / "supabase/seed.sql"]
                suites = sorted((ROOT / "supabase/tests").glob("*_test.sql"))
                result["suites_total"], result["suites_passed"] = len(suites), []
                for path in setup + suites:
                    run(sql, data=path.read_bytes(), label=str(path.relative_to(ROOT)))
                    if path in suites:
                        result["suites_passed"].append(path.name)
            finally:
                if cid and re.fullmatch("[a-f0-9]{64}", cid):
                    owner = capture(docker + ["inspect", cid, "--format", '{{index .Config.Labels "ctt.release.run"}}'])
                    if owner != run_id:
                        raise RuntimeError("Cleanup refused: owner mismatch")
                    run(docker + ["rm", "--force", cid], label="cleanup owned container")
                    result["cleanup"] = "removed exact owned ID; tmpfs discarded"
        elif args.mode == "agents":
            for name in NAMES:
                text, _ = run(["opencode", "debug", "agent", name])
                cfg = json.loads(text)
                assert cfg["mode"] == ("primary" if name == NAMES[0] else "subagent")
                assert cfg["native"] is False and cfg.get("prompt")
                if name == NAMES[-1]:
                    assert all(not cfg["tools"].get(t, False) for t in ("edit", "write", "bash", "task"))
            result["discovery"] = "6/6 loaded; auditor edit/write/bash/task disabled"
        else:
            if not args.prompt_file or not args.prompt_file.resolve().is_relative_to(ROOT / "docs/orchestration"):
                raise RuntimeError("Use --prompt-file within docs/orchestration")
            text, code = run(["opencode", "run", "--agent", NAMES[0], "-m", "openai/gpt-6-astra",
                              "--format", "json", args.prompt_file.read_text()], timeout=600, check=False)
            children, errors = [], []
            for line in text.splitlines():
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if event.get("type") == "error":
                    errors.append(event["error"])
                part = event.get("part", {})
                state = part.get("state", {})
                if part.get("tool") == "task" and state.get("status") == "completed":
                    children.append({"agent": state["input"].get("subagent_type"), "output": state.get("output")})
            (out / "children.json").write_text(json.dumps(children, indent=2) + "\n")
            result["child_agents"] = [c["agent"] for c in children]
            if code or errors or not children:
                raise RuntimeError(f"Delegation incomplete: exit={code}, errors={errors}, completed_children={len(children)}")
        result["exit_code"] = 0
    except Exception as error:
        result["error"] = str(error)
        print(str(error), file=sys.stderr)
    finally:
        changed = [str(p.relative_to(ROOT)) for p in inputs
                   if not p.exists() or hashlib.sha256(p.read_bytes()).hexdigest() != hashes[str(p.relative_to(ROOT))]]
        result["changed_inputs_during_run"] = changed
        if changed:
            result["exit_code"] = 1
        result["finished"] = datetime.now(timezone.utc).isoformat()
        (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
