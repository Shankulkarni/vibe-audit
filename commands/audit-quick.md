# Command: /audit:quick

Run a fast bash-only scan of the codebase. No AI tokens. No deep analysis. Results in ~5 seconds.

## Usage

```
/audit:quick
```

---

## Auto-Update

Before anything else, pull the latest plugin code:

```bash
bash scripts/auto-update.sh
```

This is silent and non-blocking — if the network is unavailable or the pull fails, the scan continues with the current version.

---

## What This Does

Runs two grep-based scripts against the codebase and prints raw hits. This is a triage tool — it finds suspicious patterns quickly, but does not classify them. Expect false positives. Use `/audit` for verified, context-aware findings.

---

## Execution

### Step 1 — Pattern Scan

Run:

```bash
bash scripts/quick-scan.sh
```

This greps for 50+ vibecode and security anti-patterns across all source files. Output is raw `file:line: matched text` hits grouped by pattern category.

### Step 2 — Secret Detection

Run:

```bash
bash scripts/find-secrets.sh
```

This checks for exposed credentials, API keys, tokens, and other secrets in source files. Output is raw hits with file and line references.

### Step 3 — Print Results

Print all hits from both scripts, organized by category:

```
## Quick Scan Results
> These are unfiltered grep hits. False positives are expected.
> Use /audit for context-aware, verified findings.

### Secrets / Credentials
src/lib/stripe.ts:14: sk_live_...
...

### Missing Auth Checks
src/app/api/admin/users/route.ts:8: export async function GET(
...

### SQL Injection Patterns
src/db/queries.ts:34: `SELECT * FROM users WHERE id = ${userId}`
...

### Swallowed Errors
src/hooks/useData.ts:22: } catch (e) {}
...

[additional categories]
```

### Step 4 — Print Summary Counts

```
## Quick Scan Summary
| Category | Hits |
|---|---|
| Secrets / Credentials | N |
| Missing Auth Checks | N |
| SQL Injection Patterns | N |
| Swallowed Errors | N |
| XSS Risk | N |
| Dead Code | N |
| Type Safety Escapes | N |
| TODO / FIXME (security-adjacent) | N |
| [other categories] | N |
| **Total** | **N** |

Scan completed in ~Xs. Run /audit to verify these hits with full context analysis.
```

---

## Important Caveats

Print this notice before results:

```
NOTE: /audit:quick is a raw grep scan. Results are NOT verified findings.
- A "Missing Auth Check" hit may be a public route — that is correct behavior.
- A "Secret" hit may be a placeholder or public key.
- Use /audit for Claude-verified findings with false positives removed.
```
