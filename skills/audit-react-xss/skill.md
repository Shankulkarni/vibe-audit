---
name: audit-react-xss
description: Audit React applications for XSS vectors that AI generators commonly introduce
triggers: [react, xss, dangerouslySetInnerHTML, innerHTML, href, src, sanitize, dompurify]
---

# Audit: React XSS

## Purpose

React's JSX model prevents most XSS by default — it escapes all string values before rendering. But there are specific escape hatches that AI generators use without thinking, re-introducing the same vulnerabilities React was designed to prevent. The most dangerous are `dangerouslySetInnerHTML` with dynamic content, unvalidated `href`/`src` attributes from user data, and DOM manipulation via refs that bypasses React's escaping.

## What to Look For

### dangerouslySetInnerHTML with Dynamic Content

```tsx
// Flag: CRITICAL — user or API content rendered as raw HTML
<div dangerouslySetInnerHTML={{ __html: user.bio }} />
<div dangerouslySetInnerHTML={{ __html: post.content }} />
<div dangerouslySetInnerHTML={{ __html: apiResponse.html }} />
<div dangerouslySetInnerHTML={{ __html: `<b>${name}</b>` }} />

// Flag: variable that could contain user content
const html = formatMarkdown(userInput)
<div dangerouslySetInnerHTML={{ __html: html }} />

// Safe: sanitized with DOMPurify before rendering
import DOMPurify from 'dompurify'
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(content) }} />

// Safe: static string (hardcoded, not user-controlled)
<div dangerouslySetInnerHTML={{ __html: '<b>Static content</b>' }} />
```

Grep for `dangerouslySetInnerHTML` and inspect the `__html` value in each case. If it traces back to user input, API response, database content, or any non-hardcoded source without sanitization — flag it.

### URL Injection — javascript: Protocol via href

```tsx
// Flag: CRITICAL — user-supplied URL in href without validation
<a href={user.website}>Visit</a>
<a href={post.link}>Read more</a>
<a href={formData.redirectUrl}>Continue</a>

// A malicious user sets: website = "javascript:alert(document.cookie)"
// This executes when the link is clicked

// Safe: validate URL before use
function isSafeUrl(url: string): boolean {
  try {
    const parsed = new URL(url)
    return ['http:', 'https:'].includes(parsed.protocol)
  } catch {
    return false
  }
}
<a href={isSafeUrl(user.website) ? user.website : '#'}>Visit</a>

// Safe: prefix with known domain
<a href={`https://myapp.com${internalPath}`}>Visit</a>
```

Look for: `href={` followed by a variable that is not a hardcoded string, not prefixed with `/` for relative paths, and not validated.

### URL Injection via src

```tsx
// Flag: HIGH — user-supplied URL in src
<img src={user.avatarUrl} />     // could be javascript: or data: URI
<iframe src={user.embedUrl} />   // iframe with user URL is high risk
<script src={externalUrl} />     // dynamic script loading

// Safe: validate URLs or use a whitelist
const TRUSTED_IMAGE_DOMAINS = ['cdn.myapp.com', 'images.unsplash.com']
function isTrustedImageUrl(url: string): boolean {
  try {
    return TRUSTED_IMAGE_DOMAINS.includes(new URL(url).hostname)
  } catch {
    return false
  }
}
```

### Link Components with Dynamic href

Framework Link components have the same vulnerability:

```tsx
// Flag: Next.js Link with user-supplied href
import Link from 'next/link'
<Link href={user.profileUrl}>Profile</Link>

// Flag: React Router Link
import { Link } from 'react-router-dom'
<Link to={destination}>Go</Link>

// Where destination comes from user input, URL params, or API data without validation
```

### innerHTML, document.write, insertAdjacentHTML

Direct DOM manipulation that bypasses React's sanitization:

```tsx
// Flag: direct innerHTML assignment
useEffect(() => {
  if (ref.current) {
    ref.current.innerHTML = userContent  // bypasses React escaping
  }
}, [userContent])

// Flag: document.write
document.write(apiResponse.script)

// Flag: insertAdjacentHTML
element.insertAdjacentHTML('beforeend', userHtml)
```

### iframe src from User Input

```tsx
// Flag: HIGH — user controls iframe src
<iframe src={user.videoUrl} />
<iframe src={embedCode} />  // where embedCode comes from user or API

// Embedded iframes can run arbitrary JavaScript in a different origin context
// This is especially dangerous for content from unknown sources
```

### Style Injection

```tsx
// Flag: computed CSS property name from user data
<div style={{ [userKey]: userValue }} />

// Flag: CSS value from user that could inject expressions (in older browsers)
<div style={{ backgroundImage: `url(${userUrl})` }} />

// Flag: style string from user
<div style={user.customStyle} />  // user can set: "background: url('javascript:...')"
```

### Template Literals in href/src

```tsx
// Flag: user data interpolated in URL strings used as href/src
<a href={`https://redirect.com?next=${userInput}`}>
// If the redirect service follows the 'next' param, this is an open redirect

<img src={`/api/image?path=${filename}`} />
// If filename = '../../etc/passwd' or contains special chars — path traversal
```

### SVG Injection

```tsx
// Flag: rendering user-supplied SVG content
<div dangerouslySetInnerHTML={{ __html: svgFromUser }} />

// SVGs can contain <script> tags and event handlers
// <svg><script>alert(1)</script></svg> executes in most browsers

// Safe: strip SVG of scripts before rendering
import DOMPurify from 'dompurify'
const cleanSvg = DOMPurify.sanitize(svgFromUser, { USE_PROFILES: { svg: true } })
```

### Markdown Renderers with Raw HTML Enabled

```tsx
// Flag: markdown renderer with HTML passthrough enabled
import ReactMarkdown from 'react-markdown'

<ReactMarkdown>{userContent}</ReactMarkdown>
// Default ReactMarkdown is safe — it strips HTML

// Flag: explicitly enabling HTML in markdown
<ReactMarkdown remarkPlugins={[remarkHtml]}>{userContent}</ReactMarkdown>
<ReactMarkdown allowDangerousHtml>{userContent}</ReactMarkdown>
// These allow raw HTML in markdown which enables XSS
```

### React ref Misuse for DOM Manipulation

```tsx
// Flag: using ref to set innerHTML with dynamic content
const divRef = useRef<HTMLDivElement>(null)
useEffect(() => {
  if (divRef.current) {
    divRef.current.innerHTML = `<p>${description}</p>`  // XSS if description is user data
  }
}, [description])
```

### RSC Props Over-Serialization — Sensitive Data Embedded in HTML

In React Server Components, props passed from a server component to a client component are serialized directly into the HTML response. This is not XSS in the traditional sense, but it is an information disclosure vector: fields that should never reach the browser end up in the page source.

```tsx
// Flag: passing entire DB object to a client component
// Server component:
const user = await db.users.findById(id)
return <ProfileCard user={user} />  // user includes: passwordHash, stripeCustomerId, internalNotes

// The full user object is serialized to HTML — visible to anyone who views source

// Correct: project only what the client component needs
return <ProfileCard name={user.name} avatarUrl={user.avatarUrl} />

// Flag: passing raw API response to client component
const apiData = await fetchFromInternalAPI('/admin/stats')
return <StatsWidget data={apiData} />
// apiData may contain fields only an admin should see

// Flag: spreading props from server data into a client component
const { sensitiveField, ...rest } = serverData
return <Widget {...rest} />  // rest might still contain unexpected fields
```

**What to look for**: Server components that pass objects (not primitives) to `'use client'` components. Check whether those objects contain fields like `passwordHash`, `internalId`, `stripeCustomerId`, `apiKey`, `serviceToken`, `adminNotes`, or `role`.

**Severity**: High if the serialized props include credentials or auth tokens. Medium for PII (emails, phone numbers) that the client component doesn't need to render.

### Missing Content-Security-Policy

Not a code pattern but a configuration gap. Check:
- `next.config.js` / `next.config.ts` for security headers
- `vercel.json` for headers configuration
- Express/middleware for `helmet` or manual CSP header

```ts
// Flag: no CSP configured
// next.config.js with no headers() function, or headers() that doesn't set CSP
```

## Severity Classification

**Critical**
- `dangerouslySetInnerHTML` with user-supplied or API-sourced content, no sanitization
- `href={userInput}` or `<a href={variable}` where variable traces to user data without URL validation
- `src={userInput}` on `<img>`, `<iframe>`, or `<script>` tags

**High**
- `iframe src` from user input or unvalidated API data
- `innerHTML` assignment from user content in useEffect/event handlers
- SVG from user rendered via `dangerouslySetInnerHTML` without sanitization
- Markdown renderer with HTML passthrough enabled on user content
- RSC props passing credentials or auth tokens to client components (serialized to HTML)

**Medium**
- Template literals constructing URLs with unvalidated user data as a parameter value
- Style injection via computed property names from user data
- Open redirect via user-controlled redirect URL parameter
- RSC props passing PII (email, phone) to client components that don't need to render it

**Low**
- Missing Content-Security-Policy headers (defense in depth, not a direct code flaw)
- ref-based DOM manipulation that is currently safe but bypasses React's protections (fragile)

## Finding Format

```
🔴 CRITICAL | XSS via dangerouslySetInnerHTML | src/components/UserProfile.tsx:34
user.bio is rendered as raw HTML without sanitization. A user with a crafted bio can execute arbitrary JavaScript.
Fix: Import DOMPurify and sanitize: dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(user.bio) }}
Or avoid HTML rendering entirely and use a whitelist-based markdown renderer.

🔴 CRITICAL | href Injection | src/components/LinkCard.tsx:18
href={post.link} where post.link comes from API response with no URL validation. A malicious value of 'javascript:alert(1)' executes on click.
Fix: Validate URL protocol before use:
  const safeHref = /^https?:\/\//.test(post.link) ? post.link : '#'

🟠 HIGH | iframe src from User | src/components/EmbedViewer.tsx:9
<iframe src={user.embedUrl}> — user controls the iframe source. Embedded pages can execute JS in their own context and use postMessage to interact with the parent.
Fix: Validate against an allowlist of trusted embed domains. Add sandbox attribute: sandbox="allow-scripts allow-same-origin".

🟠 HIGH | innerHTML with User Content | src/components/RichText.tsx:55
ref.current.innerHTML = content inside useEffect where content traces to API response. Bypasses React's XSS protections.
Fix: Use React's JSX rendering pipeline instead. If HTML is necessary, sanitize with DOMPurify before assignment.

🟡 MEDIUM | Open Redirect via Template Literal | src/pages/auth/callback.tsx:22
<a href={'/redirect?to=' + returnUrl}> where returnUrl comes from searchParams. If your redirect endpoint follows the 'to' param, this is an open redirect.
Fix: Validate returnUrl is a path on your own domain before using it.

🔵 LOW | Missing CSP | next.config.ts
No Content-Security-Policy header configured. CSP is a critical defense-in-depth layer against XSS.
Fix: Add a CSP header in the headers() config in next.config.ts. Start with a report-only policy.

🟠 HIGH | Credentials in RSC Props | src/app/dashboard/page.tsx:14
Full user object passed to <DashboardHeader user={user} /> — includes passwordHash and stripeCustomerId, both serialized to the page HTML.
Fix: Pass only display fields: <DashboardHeader name={user.name} avatarUrl={user.avatarUrl} />
```

## Common False Positives

Do NOT flag:
- `dangerouslySetInnerHTML` with fully hardcoded static string literals (no variables)
- `dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(...) }}` — this is the correct pattern
- `href="/internal/path"` — relative paths are safe
- `href={`/users/${userId}`}` — paths constructed from your own IDs (not user-controlled content)
- `src={avatarUrl}` where `avatarUrl` is generated by your own system (e.g., a Supabase storage URL your server creates), not directly from user text input
- `ReactMarkdown` without `allowDangerousHtml` — safe by default
- `next/link` with `href` from your router's typed routes (route-safe)

## Stack-Specific Notes

**Next.js**: `next/image` validates URLs via the `domains` or `remotePatterns` config in `next.config.js`. `<img>` without `next/image` does not get this protection — flag unvalidated `src` on plain `<img>` tags.

**React Native**: `dangerouslySetInnerHTML` does not exist in React Native. The XSS surface is different: focus on `WebView` with `source={{ uri: userUrl }}` or `source={{ html: userHtml }}` — both need validation and sanitization.

**Remix**: Same React XSS rules apply. Check `dangerouslySetInnerHTML` in route components and the `meta` function for injected meta content.

**Gatsby**: Static rendering reduces some XSS risk but dynamic data fetched at runtime (via GraphQL or REST) still needs the same protections.

**rich text editors (TipTap, Slate, Quill)**: These generate HTML internally. The output they produce should still be sanitized before storing to DB and re-sanitized before rendering via `dangerouslySetInnerHTML` in a different context.
