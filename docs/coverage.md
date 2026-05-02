# Coverage & Standards

## Industry Standards

| Standard | What It Covers |
|----------|----------------|
| **OWASP Top 10:2025** | Injection, broken auth, SSRF, security misconfiguration, cryptographic failures |
| **OWASP ASVS 5.0** | Application Security Verification Standard — auth, session, access control, validation |
| **PCI-DSS** | Payment data handling, Stripe webhook verification, secret key exposure |
| **App Store Guidelines** | Secure storage, certificate pinning, deep link validation (React Native) |
| **AI-Specific Patterns** | Prompt injection, insecure defaults from code generators, mock data left in prod, agentic safety |
| **Supply Chain** | Dependency risks, lockfile integrity, typosquatting signals |

## Audit Dimensions

Every finding is tagged with one of six dimensions:

| Dimension | What Gets Checked |
|-----------|-------------------|
| **Security** | Auth, injection, secrets, crypto, access control |
| **Quality** | Error handling, dead code, AI slop patterns, type safety |
| **Performance** | Bundle size, edge config, function cold starts, query cost |
| **Compliance** | PCI-DSS (Stripe), App Store guidelines (RN), data access (Supabase) |
| **Documentation** | TODO/auth comments, undocumented security assumptions |
| **Testing** | Swallowed errors, untested auth paths, missing edge case coverage signals |

## Severity Scale

| Level | Meaning |
|-------|---------|
| 🔴 CRITICAL | Ship-blocker. Do not deploy until fixed. |
| 🟠 HIGH | Fix before next release. Real exploit path exists. |
| 🟡 MEDIUM | Fix this sprint. Low-effort attack or data leak. |
| 🟢 LOW | Fix when convenient. Best practice gap. |
| ℹ️ INFO | Observation. No direct risk. May warrant a decision. |
