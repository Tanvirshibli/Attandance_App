# Biometric Authentication (Fingerprint + Face)

Last updated: November 14, 2026 · build `2.5.5+9038`

Fingerprint sign-in and fingerprint check-in sit beside the existing on-device
face mechanism. Face additionally becomes a **login** method. Everything is
switched on from **Profile → Biometrics** after a normal password sign-in.

---

## 0. Login works out of the box (2026-11-16)

Three defects made biometric sign-in dead in the shipped build:

1. **Face login checked memory, not the device.** `loginWithFace` gated on
   `isFaceRegistered()`, which reads the in-memory template. That template is
   only hydrated *after* a successful login, so on the login screen it was
   always empty and every attempt answered "needs a face registered on this
   server". The template is now **persisted** in secure storage
   (`face_login_template`) on every hydrate and rehydrated by
   `restorePersistedRegistration()` at login and on cold start. Only the derived
   embedding is stored, never an image.
2. **The face button keyed off the wrong flag.** It rendered from
   `biometricFaceLoginEnabled`, which `setBiometricFaceLoginEnabled` could leave
   out of step with `biometricLoginFace`. The two are now kept in sync.
   Visibility is driven by the **switch alone**: an early fix also required a
   persisted template before showing the button, which hid it from every existing
   user whose template had not been captured yet. The template is now captured
   when the switch is turned on in Profile (`_persistFaceTemplateForLogin`), and
   a missing template is reported inside the flow instead of hiding the button.
3. **Fingerprint login needed a manual enrolment that never happened.** The
   Keystore key and credential exist only after "Enrol fingerprint", so a fresh
   install never showed the button. Enrolment is now automatic (below).
4. **Face sign-in captured with an external camera intent.** The flow used
   `ImagePicker(source: ImageSource.camera)`, which launches another package's
   camera activity. Android 11+ refuses to resolve that intent unless `<queries>`
   declares it, and the thrown exception was swallowed into "no photo was
   captured" — instant, unexplained, on every attempt. Check-in was unaffected
   because it uses the in-process `camera` plugin.

   Face sign-in now captures in `FaceLoginCaptureScreen`, on the same `camera`
   package check-in uses, and verifies locally there. **The capture runs before
   the transaction overlay opens**, because that overlay covers every route and a
   camera pushed underneath it would be invisible. `loginWithFace` therefore
   takes the already-matched photo (`matchedPhoto`) and only performs the session
   exchange; its external-intent fallback was removed so the broken path cannot
   be reached again. The manifest also declares `IMAGE_CAPTURE` and `GET_CONTENT`
   for the remaining `image_picker` uses elsewhere in the app.
5. **Clearing memory deleted the device template.** `clearRegistrationMemory()`
   also called `_clearPersistedRegistration()`, and it runs from
   `hydrateRegistration(null)` — which `AuthService` calls on every session
   hydration with `profile?.faceRegistration`. Any profile response without that
   field (omitted, partial, after a logout) therefore erased the device copy, and
   the next visit to the login screen reported "needs a face registered on this
   server" on every phone. Face check-in was unaffected because it hydrates from
   the live profile inside a session.

   `clearRegistrationMemory()` is now memory-only; `deleteRegisteredFace()` is the
   single place that erases the device copy, for a real unregister.

   Sign-in also **self-heals**: when the device copy is missing but a stored
   sign-in token exists, `_ensureFaceTemplate()` reads the registration back with
   `GET /api/v1/mobile/face-registration` (`Authorization: Bearer <stored token>`)
   and adopts it. The "register a face first" message is now only produced when
   both the device copy and the server — queried with that token — have nothing.
   Pinned by `test/face_template_persistence_test.dart`.
6. **"Face verified, but the session could not be renewed."** Face sign-in was
   authenticating with the *access token* and renewing through
   `POST /api/v1/refresh`. That could never be durable:

   - `config/jwt.php` sets `ttl = 1440` minutes, so a phone left alone for a day
     presented an **expired** token and `JWTAuth::refresh()` threw;
   - `JWTAuth::refresh()` **blacklists** the token it consumes, so even a fresh
     token worked only **once** — the app never re-stored the new one.

   Face sign-in now uses a **device-bound credential**, the same shape as the
   fingerprint one: at enrolment the app generates a 32-byte secret
   (`Random.secure`), keeps it in secure storage and uploads only
   `Hash::make(secret)`. Sign-in posts to `POST /api/v1/mobile/face-login` and the
   server mints a JWT from the credential — no expiry, revocable from the SPA
   biometric console, one active face credential per device. Enrolment happens
   while a session exists (after a password login, from the dashboard hydrate, or
   when Face login is switched on).

### Face sign-in uses the check-in capture mechanism

`FaceLoginCaptureScreen` runs the same in-process camera pipeline as
check-in/check-out (front camera, oval guide, retry budget, local template match)
and now also tracks location: camera and location permission, a high-accuracy fix
with a 15 s budget requested alongside the camera, and the result shown in the
footer (`Location captured (±N m)` / `Location unavailable`).

The fix travels with the credential use and is stored on the credential row
(`lastUsedLatitude`, `lastUsedLongitude`, `lastUsedAccuracyMeters`) for HR.

**Location never gates sign-in.** A slow or disabled GPS must not lock an officer
out of their own account, so a missing fix simply means "unavailable" and the
sign-in proceeds.

### Defaults and auto-enrolment

- All four biometric settings start **on**. The first successful password login
  pushes them to the server once (`applyDefaultsOnce`, flagged locally) because
  the backend defaults every preference to false and would otherwise overwrite
  them on the next `load()`. A user who later turns something off keeps that
  choice; the push never runs again.
- After that push, `ensureEnrolled()` asks **once** ("Enable fingerprint
  sign-in?") and remembers the answer. On acceptance it creates the Keystore key
  and registers the public half. A phone with no usable sensor, or no fingerprint
  set up in Android, defers with the reason — Android cannot create a biometric
  for the user. A deliberate "Remove fingerprint" records `declined`.
- The same preparation runs from the dashboard, because a restored session never
  passes through the login form.

### A punch can never be blocked by a missing method

The server only requires a fingerprint authorization when
`checkin.fingerprint` is on **and** `checkin.face` is off. Face is on by default,
so either method works and a phone without a fingerprint still punches. The app
refuses any save that would turn **both** check-in methods off, and likewise both
login methods (`BiometricPreferencesService.invalidCombinationReason`).


Android provides **no API that reads fingerprint templates**. A fingerprint is
captured and matched by the system, inside the sensor's trusted component, and
an app only ever learns "this fingerprint matched" — never *which* finger, and
never the template. Uploading a reusable template, as the face flow does with
its 512-d embeddings, is therefore impossible.

What is enrolled instead is a **key binding**:

```
Keystore key (ECDSA P-256, auth-per-use)
  ├── private half  → never leaves the device's secure hardware
  └── public half   → registered with the backend (X.509 SPKI, base64)
```

- `KeyProperties.PURPOSE_SIGN`, `setDigests(SHA256)`,
  `setUserAuthenticationRequired(true)`,
  `setInvalidatedByBiometricEnrollment(true)`.
- API 30+: `setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)` — every
  single signature needs a fresh prompt.
- API 26–29: `setUserAuthenticationValidityDurationSeconds(-1)` — the same
  auth-per-use behaviour.

A signature is only produced when `BiometricPrompt` hands the authorised
`CryptoObject` back to the app, so **the device's own enrolled fingerprint is
the factor**; the app cannot forge it, and the backend can verify the result
with the stored public key alone.

---

## 2. Credential lifecycle

| Step | What happens | Where |
|---|---|---|
| Enrol | `generateKey(alias)` → read public key → `POST /api/v1/mobile/biometric-credentials` | Profile → Biometrics → *Enroll fingerprint* |
| Challenge | `POST /api/v1/mobile/biometric-challenge` with `{credentialId, purpose}` | `BiometricApiService.requestChallenge` |
| Sign | `BiometricPrompt` authorises `SHA256withECDSA` over the UTF-8 bytes of `nonce` | `BiometricKeystoreChannel.kt` |
| Verify | Server checks the signature against the stored public key | HRM backend |
| Use | login → session token; punch → short-lived authorisation id | `BiometricAuthService` |
| Revoke | `DELETE /api/v1/mobile/biometric-credentials/{credentialId}` + `deleteKey(alias)` | Profile → Biometrics → *Remove fingerprint* |

- Alias: `pphl_bio_<credentialId>`.
- `credentialId`: client-generated RFC 4122 v4 UUID from `Random.secure()`.
- Signature encoding: ECDSA `SHA256withECDSA`, **DER**, base64 (no wrap).
- Public key encoding: `KeyPair.public.encoded` (X.509 SubjectPublicKeyInfo),
  base64.
- Algorithm advertised to the backend: `ES256`.

A re-enrol replaces the alias's key pair (the old entry is deleted first) and
reuses the existing `credentialId` when this device already has one, so a
re-enrolment does not leave duplicate rows on the server.

---

## 3. Endpoint table

All of these ride the **HRM base URL** (`AppConfig.authApiBaseUrlCandidates`,
endpoint-config key prefix `biometric.`), the same family as
`/api/v1/mobile/face-registration` — not the ZKTeco base.

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/api/v1/mobile/biometric-challenge` | none/bearer | Issue a `nonce` for `purpose: "login" \| "punch"` |
| POST | `/api/v1/mobile/biometric-login` | none | `{credentialId, nonce, signature}` → `{token, user}` |
| POST | `/api/v1/mobile/biometric-punch-authorization` | JWT | `{credentialId, nonce, signature, direction, deviceIdentifier}` → `{authorization_id}` |
| GET | `/api/v1/mobile/biometric-credentials` | JWT | Credentials for this user + `preferences` |
| POST | `/api/v1/mobile/biometric-credentials` | JWT | Register the public key |
| DELETE | `/api/v1/mobile/biometric-credentials/{credentialId}` | JWT | Revoke |
| PUT | `/api/v1/mobile/biometric-preferences` | JWT | `{login:{face,fingerprint}, checkin:{face,fingerprint}}` |

The punch itself is still the existing ZKTeco
`POST /api/v1/mobile/attendance-requests`, now carrying
`biometric_method: "face" | "fingerprint"` and, for fingerprint,
`biometric_authorization_id`.

---

## 4. Settings prerequisites

`Profile → Biometrics` renders four switches and one enrolment row. A switch is
disabled (with the reason as its subtitle) until its prerequisite is met —
never silently inert.

| Row | Prerequisite | Server pref key |
|---|---|---|
| Fingerprint login | a local credential (`biometric_credential_id`) | `login.fingerprint` |
| Face login | a registered face template | `login.face` |
| Fingerprint check-in | a local credential | `checkin.fingerprint` |
| Face check-in | a registered face template | `checkin.face` |
| Enroll / Remove fingerprint | device has strong biometrics enrolled | — |

`face check-in` defaults to **on** so an officer who already had the face flow
keeps it after the update.

The switches are mirrored locally (`SharedPreferences`:
`biometric_login_fingerprint`, `biometric_login_face`,
`biometric_checkin_fingerprint`, `biometric_checkin_face`,
`biometric_credential_id`, `biometric_key_alias`,
`biometric_face_login_enabled`) so the login screen and the check-in flow work
with no network. `BiometricPreferencesService` treats the server as the source
of truth: `load()` adopts the server's `preferences`, and `save()` updates
locally first (optimistic) then **rolls back** if the PUT fails — including a
422 for a combination the backend refuses.

---

## 5. Flows

### Login (no password)

**Fingerprint** — `BiometricLoginService.loginWithFingerprint()`

1. Local credential must exist, otherwise the button is not even shown.
2. `canAuthenticate(BIOMETRIC_STRONG)` must report success.
3. Challenge (`purpose: "login"`) → prompt → signature.
4. `POST /api/v1/mobile/biometric-login` → session body.
5. `AuthService.applyBiometricSession(body)` stores the token and runs the same
   hydration a password login does (permission clear, zone scope, geo, FCM,
   background profile + face template).

**Face** — `BiometricLoginService.loginWithFace()`

1. `faceLoginBlocker()` first restores a usable template from the device copy.
   If that copy is missing, the template is fetched from
   `GET /api/v1/mobile/face-registration`; an expired stored token is refreshed
   once from the device-bound credential. No registration, no device link and a
   server outage are reported as three distinct cases.
2. Up to **3** front-camera captures are verified in-app with
   `FaceRecognitionService.verifyFace` — the same strong core-template
   thresholds the check-in flow uses.
3. On a match, `POST /api/v1/mobile/face-login` with the device-bound credential
   mints the session, which `AuthService.applyBiometricSession(body)` stores and
   hydrates.

Both flows are cancellable (the login screen shows a Cancel link while one is
running) and never throw to the UI: every failure is a message.

### Check-in / check-out

`HomeScreen._openCheckFlow` decides:

| Check-in prefs | Behaviour |
|---|---|
| neither ready | existing path — face registration is forced if no template |
| only face | straight to `CheckInScreen(method: face)` |
| only fingerprint | straight to `CheckInScreen(method: fingerprint)` |
| both | small bottom sheet: *Face recognition* / *Fingerprint* |

The fingerprint path is: challenge (`purpose: "punch"`) → prompt → signature →
`POST /api/v1/mobile/biometric-punch-authorization` → the **existing** punch
submission, now carrying `biometric_method: "fingerprint"` and
`biometric_authorization_id`. The face path is unchanged and sends
`biometric_method: "face"` with `face_verified: true`.

### When a biometric punch is refused

Both paths send `biometric_method`, so both go through
`AttendanceRequestService.submitSelfPunch`'s biometric candidate list, which
puts HRM first because HRM owns the credential, the nonce and the preference
flags. ZKTeco is the fallback only for an **outage**.

The server's refusals are 4xx carrying a machine code, and
`UserFacingError.forPunchRefusal` names each one instead of returning
`generic` — which is what previously made a refusal look like a dead
deployment:

| Server `message` | What the employee is told |
|---|---|
| `gps_required` | Location is required to punch. Turn on GPS and try again. |
| `gps_untrusted` | Location looks fake or too far from the office. |
| `client_time_required` | Phone time is needed to punch. Enable automatic date and time. |
| `device_time_untrusted` | Phone clock is wrong, so the punch was refused. |
| `app_outdated` | This version of the app is too old to punch. |
| `biometric_authorization_required` | This punch needs a fresh face or fingerprint check. |
| shift-window prose | Passed through verbatim — it already names the shift, the anchor time and the grace deadline |

"Server is unreachable. Please try again later." is reserved for a real HTTP
5xx or a TLS handshake failure. A 4xx is returned immediately and never falls
through to ZKTeco: the ZKTeco BFF accepts a bare punch and would answer 201,
turning a refused biometric into a phantom success. Only a 5xx or a transport
failure advances to the next candidate, and each attempt logs its url, status
and message for field diagnosis.

---

## 6. Threat model

| Threat | Fingerprint | Face |
|---|---|---|
| Stolen unlocked phone, no biometrics | Blocked — an auth-per-use Keystore key cannot sign without a prompt | **Weaker** — a photo-quality frame of the owner can pass; the local matcher is a convenience factor, not a security boundary |
| Attacker adds their own fingerprint to the phone | Key is invalidated by `setInvalidatedByBiometricEnrollment(true)`; credential is auto-revoked | N/A (the encrypted token is not bound to biometrics) |
| Replay of a captured signature | Nonce is single-use and expiring (`expires_at`) | N/A |
| Server-side public key only | The server never holds anything that can sign | The refresh token is the secret; it is wrapped by the platform keystore (`flutter_secure_storage`, `encryptedSharedPreferences`) |
| Password stored for biometric use | Never | **Never** — face login refreshes a token, it does not replay a password |
| Losing the device | Revoke from any other session (DELETE credential); key never leaves the device | Same: revoke face login, which clears the encrypted token on next sign-out |

Because the local face match is the weak link, face login is **opt-in per user**,
defaults **off**, and is only offered once the user has a registered face plus a
password login on that device. Fingerprint is the stronger of the two: it cannot
be satisfied without the OS biometric prompt.

---

## 7. Key invalidation

`KeyPermanentlyInvalidatedException` (raised when the device's fingerprint set
changes, or the key is destroyed) is reported by the channel as
`result.error("key_invalidated", …)`. The Dart side maps that to
`BiometricFailure.keyInvalidated` and then:

1. `DELETE`s the server credential (best effort — offline is fine, the key is
   already unusable),
2. deletes the Keystore entry,
3. clears `biometric_credential_id` / `biometric_key_alias` and both fingerprint
   switches,
4. tells the user: *"This device's fingerprint changed, so the saved key was
   disabled. Sign in with your password and enroll your fingerprint again in
   Profile → Biometrics."*

`hasKey(alias)` is checked before every challenge, so a credential whose key
disappeared (restore to a new device, factory reset) is retired the same way.

---

## 8. Revocation

- **In-app**: Profile → Biometrics → *Remove fingerprint* → confirm → DELETE +
  `deleteKey` + local flags cleared. If the server is unreachable the device
  side is still removed and the row explains that the server copy may remain.
- **Sign-out does not revoke.** A biometric credential is device-bound, not
  session-bound — that is the point of it: it must still work after signing out,
  or it could never be used to sign back in.
- **Face login**: switching it off calls `AuthService.clearFaceLoginSecrets()`
  and deletes the encrypted token immediately.

---

## 9. Offline behaviour

Every network call degrades to a message rather than an exception:

| Situation | Result |
|---|---|
| No network on challenge | "The server could not issue a fingerprint challenge…" |
| No network on punch authorization | "Attendance could not be authorized… or use face verification" |
| No network on preferences PUT | local switches roll back and a snackbar explains |
| No network on credentials GET | local mirror stays in charge |
| Channel missing (non-Android, old build) | `canAuthenticate` reports unavailable; buttons never appear |

---

## 10. Code map

| File | Role |
|---|---|
| `lib/services/biometric_platform_service.dart` | MethodChannel wrapper + typed failure enum |
| `lib/services/biometric_api_service.dart` | The seven HTTP calls |
| `lib/services/biometric_auth_service.dart` | Enrol / sign / punch-authorize / revoke |
| `lib/services/biometric_login_service.dart` | Fingerprint and face login flows |
| `lib/services/biometric_preferences_service.dart` | Server-backed switches with local mirror |
| `lib/services/app_settings_service.dart` | Local mirror + credential id/alias persistence |
| `lib/screens/login_screen.dart` | Biometric sign-in section under the password form |
| `lib/screens/profile_screen.dart` | Biometrics settings group |
| `lib/screens/check_in_screen.dart` | `BiometricMethod` + fingerprint punch path |
| `lib/screens/home_screen.dart` | Method selection before the punch |
| `android/app/src/main/kotlin/com/pphl/employee_attendance/BiometricKeystoreChannel.kt` | Keystore key + `BiometricPrompt` |
