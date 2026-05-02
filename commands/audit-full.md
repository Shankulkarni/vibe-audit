# Command: /audit:full

Run a complete, cache-bypassing audit of the entire codebase. This is the most thorough audit mode — it ignores the cache, packs the full codebase into a compressed context, and applies all relevant skills.

## Usage

```
/audit:full
```

## When to Use

- Initial audit of a new project
- Before a major release or security review
- When you suspect cached findings are stale or incomplete
- After a large refactor that touched many files

This mode costs more tokens than `/audit` but provides the most thorough coverage.

---

## Auto-Update

Before anything else, pull the latest plugin code:

```bash
bash scripts/auto-update.sh
```

This is silent and non-blocking — if the network is unavailable or the pull fails, the audit continues with the current version.

---

## Execution

### Step 1 — Stack Detection

Run:

```bash
bash scripts/detect-stack.sh
```

Record stack flags: `HAS_NEXTJS`, `HAS_SUPABASE`, `HAS_STRIPE`, `HAS_REACT_NATIVE`, `HAS_NODE_API`, `HAS_LLM`, `HAS_VERCEL`.

### Step 2 — Pack Full Codebase Context

Run:

```bash
bash scripts/pack-context.sh
```

This uses repomix to create a compressed, token-efficient snapshot of the entire codebase. Read the output file it produces. This is the primary input for analysis.

### Step 3 — Load All Applicable Skills

Based on stack flags, load every relevant skill directory. In full mode, do not skip skills — load all that match any detected flag:

| Stack flag | Skills to load |
|---|---|
| Always | `skills/audit-vibecode-patterns/`, `skills/audit-typescript-any-escape/` |
| `HAS_NEXTJS` | `skills/audit-nextjs-server-actions/` |
| `HAS_SUPABASE` | `skills/audit-supabase-rls/` |
| `HAS_STRIPE` | `skills/audit-stripe-integration/` |
| `HAS_REACT_NATIVE` | `skills/audit-react-native-secure-storage/`, `skills/audit-react-xss/` |
| `HAS_NODE_API` | `skills/audit-node-api-auth/` |
| `HAS_LLM` | `skills/audit-llm-prompt-injection/` |
| `HAS_VERCEL` | `skills/audit-vercel-deployment/` |

### Step 4 — Deep Analysis

Apply all loaded skills to the packed codebase context. For each skill:
- Identify every file in the packed context that is in scope for this skill
- Apply the skill's rules
- Emit findings in standard format

Run all three reviewer agents in sequence:
1. Load `agents/audit-security-reviewer.md` — security pass
2. Load `agents/audit-quality-reviewer.md` — quality pass
3. Load `agents/audit-performance-reviewer.md` — performance pass

### Step 5 — Write AUDIT_REPORT.md

After analysis is complete, write a full `AUDIT_REPORT.md` to the project root. Use the format defined in `/audit:report`.

### Step 6 — Update Cache

Run:

```bash
bash scripts/cache-update.sh
```

Persist all findings and current file hashes so future `/audit` runs can skip unchanged files.

---

## Output

All findings printed to terminal, then:

```
## Audit Summary
| Severity | Count |
|----------|-------|
| 🔴 Critical | N |
| 🟠 High | N |
| 🟡 Medium | N |
| 🟢 Low | N |
| ℹ️ Info | N |

Stack detected: [list]
Files audited: N (full scan, cache bypassed)

AUDIT_REPORT.md written to project root.
```
