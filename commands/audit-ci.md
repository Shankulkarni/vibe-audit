# Command: /audit:ci

Run a security audit and exit with a non-zero code if Critical findings are detected. Designed for use inside CI/CD pipelines (GitHub Actions, GitLab CI, Bitbucket Pipelines, etc.) to block merges or deploys when the codebase has ship-blocking issues.

## Usage

```
/audit:ci
```

## When to Use

- On every pull request as a required status check
- As a pre-deploy gate in your CD pipeline
- In a git pre-push hook to block pushing known-vulnerable code

---

## Execution

### Step 1 — Stack Detection

Run:

```bash
bash "${HOME}/.claude/plugins/vibeaudit/scripts/detect-stack.sh"
```

Record stack flags to determine which security skills are relevant.

### Step 2 — Cache Check

Run:

```bash
bash "${HOME}/.claude/plugins/vibeaudit/scripts/cache-check.sh"
```

Identify which files have changed since the last audit. In CI mode, if no previous audit cache exists, treat ALL files as changed (full scan on first run).

### Step 3 — Quick Scan

Run:

```bash
bash "${HOME}/.claude/plugins/vibeaudit/scripts/quick-scan.sh"
bash "${HOME}/.claude/plugins/vibeaudit/scripts/find-secrets.sh"
```

Collect grep hits as candidate findings for deep analysis.

### Step 4 — Load Security Skills Only

Load only the skills below that match the detected stack. Do not load quality or performance skills — CI mode is security-gated only.

| Always | `skills/audit-vibecode-patterns/` (security patterns only) |
|---|---|
| `HAS_NEXTJS` | `skills/audit-nextjs-server-actions/` |
| `HAS_SUPABASE` | `skills/audit-supabase-rls/` |
| `HAS_STRIPE` | `skills/audit-stripe-integration/` |
| `HAS_REACT_NATIVE` | `skills/audit-react-native-secure-storage/` |
| `HAS_NODE_API` | `skills/audit-node-api-auth/` |
| `HAS_LLM` | `skills/audit-llm-prompt-injection/` |
| Any web stack | `skills/audit-react-xss/` |

### Step 5 — Deep Analysis

Read each file in `FILES_TO_AUDIT`. Apply all loaded skill rules. Classify grep hits as true or false positives using full file context. Emit findings in the standard format.

### Step 6 — Output in Machine-Readable JSON

**Always output a JSON block** regardless of finding count. This is what CI parsers, GitHub Actions annotations, and dashboards consume.

```json
{
  "auditedAt": "<ISO-8601 timestamp from: date -u +%Y-%m-%dT%H:%M:%SZ>",
  "stack": ["Next.js", "Supabase"],
  "filesAudited": 12,
  "passed": false,
  "exitCode": 1,
  "summary": {
    "critical": 2,
    "high": 3,
    "medium": 4,
    "low": 1,
    "info": 0
  },
  "findings": [
    {
      "severity": "critical",
      "category": "LLM Output Execution",
      "file": "src/lib/code-runner.ts",
      "line": 28,
      "description": "LLM-generated code passed to eval(). Attacker can produce arbitrary JS.",
      "fix": "Remove eval. Use a sandboxed runtime (vm2, isolated-vm) if code execution is required."
    }
  ]
}
```

After the JSON block, print a human-readable summary line:

```
vibeAudit CI: FAILED — 2 critical findings detected. Resolve before merging.
```

or if clean:

```
vibeAudit CI: PASSED — No critical findings detected.
```

### Step 7 — Exit Code

| Condition | Exit Code |
|---|---|
| Zero Critical findings | `0` (CI passes) |
| One or more Critical findings | `1` (CI fails) |

**Only Critical findings block CI.** High/Medium/Low findings are reported in the JSON output but do not cause a non-zero exit. This keeps the gate focused on must-fix issues and avoids alert fatigue from lower-severity findings.

### Step 8 — Cache Update

Run:

```bash
bash "${HOME}/.claude/plugins/vibeaudit/scripts/cache-update.sh"
```

Persist findings and file hashes so the next CI run only re-audits changed files.

---

## GitHub Actions Integration

```yaml
# .github/workflows/vibeaudit.yml
name: vibeAudit Security Gate

on:
  pull_request:
  push:
    branches: [main]

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # needed for git diff in cache-check.sh

      - name: Install Claude Code
        run: npm install -g @anthropic-ai/claude-code

      - name: Run vibeAudit CI
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: claude --print /audit:ci

      - name: Upload audit results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: vibeaudit-results
          path: .claude/vibeaudit/
```

### Annotations (Optional)

Parse the JSON output to post inline PR annotations:

```yaml
      - name: Annotate PR with findings
        if: failure()
        run: |
          jq -r '.findings[] | select(.severity == "critical") |
            "::error file=\(.file),line=\(.line)::\(.description)"' \
            .claude/vibeaudit/ci-results.json
```

---

## Scope

- Only 🔴 Critical findings block CI (exit code 1)
- All findings (Critical through Info) are included in the JSON output
- Quality and performance findings are not surfaced in CI mode — use `/audit` or `/audit:full` locally for those
- This command does not write `AUDIT_REPORT.md` — use `/audit:report` for human-readable reports
