---
name: audit-react-native-secure-storage
description: Audit React Native apps for insecure storage and transmission of sensitive data
triggers: [react-native, expo, asyncstorage, react-native-keychain, expo-secure-store, mobile, ios, android]
---

# Audit: React Native Secure Storage

## Purpose

AI generators default to `AsyncStorage` because it is the simplest, most familiar React Native storage API — it works like `localStorage`. But `AsyncStorage` is unencrypted, unprotected, and accessible to any app with filesystem access on a jailbroken or rooted device. Tokens, credentials, and PII stored there are trivially extractable.

This skill audits React Native and Expo apps for the storage and transmission patterns that AI generators get wrong by choosing the path of least resistance.

## What to Look For

### AsyncStorage for Auth Tokens

The most common critical finding in AI-generated React Native apps:

```ts
// Flag: CRITICAL — token stored in AsyncStorage
import AsyncStorage from '@react-native-async-storage/async-storage'

await AsyncStorage.setItem('token', accessToken)
await AsyncStorage.setItem('authToken', token)
await AsyncStorage.setItem('jwt', jwtString)
await AsyncStorage.setItem('accessToken', response.token)
await AsyncStorage.setItem('refreshToken', refreshToken)
await AsyncStorage.setItem('sessionToken', session.token)

// Also flag key-based reads that suggest token storage
const token = await AsyncStorage.getItem('token')
const jwt = await AsyncStorage.getItem('authToken')
```

Grep for `AsyncStorage.setItem` calls and inspect every key. Any key containing: `token`, `jwt`, `auth`, `session`, `credential`, `key`, `secret`, `access`, `refresh` is a critical finding.

### AsyncStorage for PII or Sensitive Data

```ts
// Flag: HIGH — PII or sensitive data in AsyncStorage
await AsyncStorage.setItem('userEmail', email)
await AsyncStorage.setItem('phoneNumber', phone)
await AsyncStorage.setItem('dob', dateOfBirth)
await AsyncStorage.setItem('ssn', socialSecurityNumber)
await AsyncStorage.setItem('creditCard', cardNumber)
await AsyncStorage.setItem('user', JSON.stringify(fullUserObject))
// Full user object likely contains email, phone, or other PII
```

### Secrets in the JS Bundle

```ts
// Flag: CRITICAL — API keys or secrets as string constants in source
const API_KEY = 'sk-proj-abc123...'
const STRIPE_KEY = 'pk_live_xyz...'
const SUPABASE_SERVICE_KEY = 'eyJhbGciOiJIUzI1NiJ9...'

// Flag: secrets in app.config.js or app.json extra fields
// app.config.js
export default {
  extra: {
    apiKey: 'my-secret-key',  // embedded in app bundle, extractable from APK/IPA
  }
}
```

In Expo: `Constants.expoConfig.extra.someKey` values are embedded in the app bundle and fully readable by anyone who unpacks the app. Only use `extra` for non-sensitive config values.

### Missing Certificate Pinning for Payment/Auth Endpoints

```ts
// Flag: no certificate pinning configured for sensitive API calls
// Especially when app handles payments, medical data, or financial data

// Look for: fetch(), axios, or React Native networking with no pinning config
fetch('https://api.mybank.com/transfer', { ... })
// No react-native-ssl-pinning or equivalent

// Also flag: using HTTP for internal API calls
fetch('http://api.myapp.com/user/profile')  // cleartext
```

### Unsafe Deep Link Handling

```ts
// Flag: deep link triggers auth action without validation
import { Linking } from 'react-native'

Linking.addEventListener('url', (event) => {
  const { url } = event
  // No validation of URL scheme or parameters
  const token = extractToken(url)  // attacker can craft a malicious deep link
  loginWithToken(token)
})

// Flag: Universal Links / App Links processing without validation
// Route params from deep links used directly in auth flows
```

### Expo SecureStore Not Used for Sensitive Data

```ts
// Flag: using AsyncStorage where SecureStore should be used
import AsyncStorage from '@react-native-async-storage/async-storage'
await AsyncStorage.setItem('userCredentials', JSON.stringify(creds))

// Correct for Expo:
import * as SecureStore from 'expo-secure-store'
await SecureStore.setItemAsync('userCredentials', JSON.stringify(creds))
// SecureStore uses iOS Keychain / Android Keystore
```

If the project uses Expo (has `expo` in package.json), `expo-secure-store` should be used for tokens and credentials. `AsyncStorage` is acceptable for non-sensitive user preferences only.

### react-native-keychain Not Used for Credentials

```ts
// Flag: storing credentials without keychain
await AsyncStorage.setItem('username', username)
await AsyncStorage.setItem('password', password)

// Correct pattern for bare React Native:
import * as Keychain from 'react-native-keychain'
await Keychain.setGenericPassword(username, password)
// Stored in iOS Keychain / Android Keystore — encrypted at rest
```

### Biometric Auth Not Configured for High-Value Data

```ts
// Flag: keychain item accessible without biometric auth for sensitive data
import * as Keychain from 'react-native-keychain'

// Missing: accessible and accessControl options
await Keychain.setGenericPassword(username, password)

// Better: require biometric for high-value operations
await Keychain.setGenericPassword(username, password, {
  accessible: Keychain.ACCESSIBLE.WHEN_UNLOCKED,
  accessControl: Keychain.ACCESS_CONTROL.BIOMETRY_ANY,
})
```

### Cleartext Traffic — HTTP in Production API Calls

```ts
// Flag: CRITICAL — HTTP URLs for production API endpoints
const API_BASE = 'http://api.myapp.com'  // not https
fetch('http://api.myapp.com/user/profile', { ... })
axios.get('http://payments.myapp.com/charge', { ... })

// Also flag: Android network security config allowing cleartext
// android/app/src/main/AndroidManifest.xml:
// android:usesCleartextTraffic="true"
// or missing network_security_config that permits cleartext domains
```

### Missing Screenshot Prevention on Sensitive Screens

```ts
// Flag: no FLAG_SECURE equivalent on auth or payment screens

// For React Native screens showing: PIN entry, payment info, auth tokens, medical data
// Android needs: FLAG_SECURE via react-native-screens or native module
// iOS needs: proper handling of app switcher screenshots

// Look for screens containing: password inputs, card number inputs, OTP inputs
// Check if any screenshot protection is implemented
```

### console.log in Production with Sensitive Data

```ts
// Flag: HIGH — sensitive data logged in production
console.log('User token:', authToken)
console.log('Response:', JSON.stringify(apiResponse))  // may contain tokens in response body
console.log('User:', user)  // user object may contain PII

// In React Native production builds, console.log:
// 1. Degrades performance (synchronous bridge call)
// 2. Is readable via device logs on non-jailbroken devices with USB access
// 3. Is a data exfiltration vector on compromised devices
```

### Hardcoded Device Check Bypass

```ts
// Flag: jailbreak/root detection disabled or bypassed
if (__DEV__) {
  // Skip jailbreak detection
} else {
  checkJailbreak()
}
// But production bundle has __DEV__ = false so this is fine — actually look for:

// Flag: commented-out detection
// isJailbroken() &&  // TODO: re-enable this check
navigateToApp()

// Flag: detection that always returns false
function isRooted(): boolean {
  return false  // placeholder
}
```

## Severity Classification

**Critical**
- Auth tokens (JWT, session, access, refresh) stored in AsyncStorage
- API secrets or private keys hardcoded in JS source or `app.config.js extra` field
- HTTP (non-HTTPS) URLs for production API calls

**High**
- PII (email, phone, DOB, SSN) stored in AsyncStorage
- Missing certificate pinning for payment or medical data endpoints
- Full user objects serialized and stored in AsyncStorage

**Medium**
- Unsafe deep link handling that triggers auth flows without validation
- Missing screenshot prevention on auth or payment screens
- `console.log` in production code logging API responses or user objects

**Low**
- Missing biometric protection for keychain items (defense-in-depth)
- `console.log` in production with non-sensitive data (performance issue)
- Jailbreak detection commented out or stubbed

## Finding Format

```
🔴 CRITICAL | Auth Token in AsyncStorage | src/store/auth.ts:34
AsyncStorage.setItem('authToken', token) — auth tokens stored in AsyncStorage are unencrypted and accessible on jailbroken devices.
Fix (Expo): Use expo-secure-store: await SecureStore.setItemAsync('authToken', token)
Fix (bare RN): Use react-native-keychain: await Keychain.setGenericPassword('auth', token)

🔴 CRITICAL | API Key in Bundle | src/config/api.ts:8
STRIPE_KEY hardcoded as string literal. This key is embedded in the app bundle and extractable from any downloaded APK/IPA.
Fix: Move Stripe operations to your backend API. The app should call your server which calls Stripe — never embed Stripe secret keys in the app.

🔴 CRITICAL | Cleartext HTTP | src/api/client.ts:3
API_BASE = 'http://api.myapp.com' — HTTP is interceptable on any network.
Fix: Use HTTPS. Update all URLs to https:// and remove any Android usesCleartextTraffic=true configs.

🟠 HIGH | PII in AsyncStorage | src/store/user.ts:56
AsyncStorage.setItem('user', JSON.stringify(user)) stores full user object including email and phone number unencrypted.
Fix: Store only the user ID in AsyncStorage. Fetch user details from API when needed, or store sensitive fields in SecureStore/Keychain.

🟡 MEDIUM | Unsafe Deep Link | src/navigation/DeepLinkHandler.ts:18
Token extracted from deep link URL and passed to loginWithToken() without validation. Malicious apps can craft deep links.
Fix: Validate the deep link URL against expected patterns. Require that auth tokens from deep links are also validated server-side.

🟡 MEDIUM | Console Log in Production | src/api/auth.ts:45
console.log('API Response:', response) — response body may contain auth tokens. Logs are accessible via USB on any device.
Fix: Remove console.log from production code. Use __DEV__ guard if logging is needed for debugging.
```

## Common False Positives

Do NOT flag:
- `AsyncStorage` for non-sensitive user preferences: theme, language, onboarding seen, notification preferences
- `AsyncStorage` for non-sensitive app state: last visited tab, search history (non-PII)
- `console.log` inside `if (__DEV__)` blocks — these are stripped in production builds
- HTTP URLs that are clearly for local development: `http://localhost:`, `http://10.0.2.2:` (Android emulator)
- `expo-secure-store` usage — this is the correct API for Expo, do not flag it
- `react-native-keychain` usage — this is correct, do not flag it

## Stack-Specific Notes

**Expo managed workflow**: `expo-secure-store` is the correct storage for sensitive data. It is not available in Expo Go (uses AsyncStorage fallback) — but production builds use native Keychain/Keystore. Flag `AsyncStorage` for tokens even in managed workflow apps.

**Expo bare workflow / React Native CLI**: `react-native-keychain` is the standard. `expo-secure-store` also works if the Expo modules are installed.

**Android network security**: Check `android/app/src/main/res/xml/network_security_config.xml` for `<domain cleartextTrafficPermitted="true">` entries pointing to production domains.

**iOS App Transport Security**: Check `ios/*/Info.plist` for `NSAllowsArbitraryLoads: true` or `NSAllowsLocalNetworking: true` in production context.

**Hermes engine**: In Hermes-enabled builds, `console.log` is still present in production unless explicitly removed. The Metro bundler does not strip console calls by default.

**Code Push / OTA updates**: Secrets in JS bundle are also exposed to any device that receives an OTA update — the attack surface is the same as the initial install.
