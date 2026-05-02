# Command: /audit:security

Run a deep, security-only audit of the current project. Focuses exclusively on Critical and High findings. Loads only security-relevant skills.

## Usage

```
/audit:security
```

## When to Use

- Pre-launch security review
- After adding a new authentication or authorization flow
- After integrating a payment provider (Stripe, etc.)
- After adding an LLM integration or user-facing AI feature
- When a security concern has been raised and you want a focused investigation

---

## Execution

### Step 1 — Stack Detection

Run:

```bash
bash scripts/detect-stack.sh
```

Record stack flags to determine which security skills are relevant.

### Step 2 — Load Security-Relevant Skills Only

Load only the skills below that match the detected stack. Do not load quality or performance skills.

| Always | `skills/audit-vibecode-patterns/` (security patterns only) |
|---|---|
| `HAS_NEXTJS` | `skills/audit-nextjs-server-actions/` |
| `HAS_SUPABASE` | `skills/audit-supabase-rls/` |
| `HAS_STRIPE` | `skills/audit-stripe-integration/` |
| `HAS_REACT_NATIVE` | `skills/audit-react-native-secure-storage/` |
| `HAS_NODE_API` | `skills/audit-node-api-auth/` |
| `HAS_LLM` | `skills/audit-llm-prompt-injection/` |
| Any web stack | `skills/audit-react-xss/` |

### Step 3 — Run Quick Scan (Security Patterns Only)

Run:

```bash
bash scripts/quick-scan.sh
bash scripts/find-secrets.sh
```

Record all hits as candidate findings for deep analysis.

### Step 4 — Load Security Reviewer Agent

Load `agents/audit-security-reviewer.md`.

Run a deep security analysis pass:
- Read every file that had a quick-scan hit
- Read all authentication, authorization, and API handler files even without hits
- Read all payment integration files even without hits
- Apply all loaded skill rules
- Classify quick-scan hits as true or false positives in full context

### Step 5 — Output Security Report

Print only Critical and High findings. Do not surface Medium, Low, or Info security findings in this mode — this keeps the output focused on what requires immediate action.

```
## Security Audit — [project name]
Date: [today]
Stack: [detected stacks]

---

[findings in standard format, Critical first]

---

## Security Summary
| Severity | Count |
|---|---|
| 🔴 Critical | N |
| 🟠 High | N |

N issues require immediate attention.
```

If there are zero Critical and High findings:

```
No Critical or High security findings detected.

Run /audit for a full audit including Medium and Low findings.
```

---

## Scope

This command only outputs 🔴 Critical and 🟠 High severity findings. This is intentional — security reviews are most useful when they surface only what must be fixed before launch, not every best-practice deviation.

If you want to see Medium and Low security findings alongside quality and performance findings, use `/audit` or `/audit:full`.
