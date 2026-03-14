#!/usr/bin/env python3
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

from openai import OpenAI

MODEL = os.environ.get("OPENAI_MODEL", "gpt-4.1-mini")
ROOT = Path(__file__).resolve().parent.parent

SYSTEM_PROMPT = """You are a local development assistant for the vMoonGen project.

Rules:
- You may propose shell commands, file writes, or git actions.
- Never execute destructive actions automatically.
- Prefer one safe step at a time.
- Return JSON only.
- JSON schema:
{
  "summary": "short explanation",
  "actions": [
    {
      "type": "shell" | "write_file",
      "command": "shell command",
      "path": "relative/path",
      "content": "file content"
    }
  ]
}
- For shell actions, use project-relative commands where possible.
- Avoid rm -rf, sudo, chmod -R, git push --force unless explicitly requested.
"""

client = OpenAI()


def ask_model(user_prompt: str) -> dict:
    resp = client.responses.create(
        model=MODEL,
        input=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": f"""Project root: {ROOT}
User request: {user_prompt}

Current goal:
- vMoonGen uses MoonGen as control plane
- VPP is dataplane + TCP/session engine
- thin adapter for orchestration and observability
- Lua defines profiles, not individual flows

Return JSON only.
""",
            },
        ],
    )
    text = getattr(resp, "output_text", "").strip()
    if not text:
        raise RuntimeError("Empty model response")
    return json.loads(text)


def run_shell(command: str) -> int:
    print(f"\n$ {command}")
    completed = subprocess.run(
        command,
        cwd=ROOT,
        shell=True,
    )
    return completed.returncode


def write_file(path: str, content: str) -> None:
    full = ROOT / path
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(content, encoding="utf-8")
    print(f"\n[wrote] {path}")


def confirm(prompt: str) -> bool:
    answer = input(f"{prompt} [y/N]: ").strip().lower()
    return answer in {"y", "yes"}


def main() -> int:
    if not os.environ.get("OPENAI_API_KEY"):
        print("OPENAI_API_KEY is not set", file=sys.stderr)
        return 1

    if len(sys.argv) < 2:
        print('usage: python3 tools/dev_assistant.py "your request here"', file=sys.stderr)
        return 1

    user_prompt = " ".join(sys.argv[1:])
    plan = ask_model(user_prompt)

    print("\nPlan:")
    print(plan.get("summary", "(no summary)"))

    actions = plan.get("actions", [])
    if not isinstance(actions, list):
        print("Invalid plan: actions must be a list", file=sys.stderr)
        return 1

    for i, action in enumerate(actions, start=1):
        a_type = action.get("type")
        print(f"\nAction {i}: {a_type}")

        if a_type == "shell":
            command = action.get("command", "")
            print(command)
            if confirm("Run this command?"):
                code = run_shell(command)
                if code != 0:
                    print(f"Command failed with exit code {code}", file=sys.stderr)
                    return code

        elif a_type == "write_file":
            path = action.get("path", "")
            content = action.get("content", "")
            print(f"write {path}")
            if confirm("Write this file?"):
                write_file(path, content)

        else:
            print(f"Unknown action type: {a_type}", file=sys.stderr)
            return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

