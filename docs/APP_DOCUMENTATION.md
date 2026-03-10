# PPHL Attendance System — Complete App Documentation

> **Single Source of Truth** — Last updated: March 8, 2026  
> This document describes the complete architecture, every feature, all files, data flows, security mechanisms, and implementation details of the PPHL Attendance System Flutter Android app.

> Authentication note: Login is integrated with backend `pphl_erp` via `POST /api/v1/a/login`. See `docs/AUTHENTICATION_INTEGRATION.md` for setup and API details.

> March 5, 2026 update: Face registration and attendance records are now backend-synced. Face data is persisted in backend `face_registration_android` and hydrated into app memory on login/profile fetch. Attendance check-in/check-out submits to backend `new_attendance_requests`, and attendance screens now show backend `requested` records. Any older local-only notes in this file are superseded by this update and `docs/AUTHENTICATION_INTEGRATION.md`.

> March 7, 2026 UI update: Home screen uses separate `Check In` and `Check Out` buttons instead of a single toggle action. Buttons are state-aware and prevent invalid sequences.

> March 7, 2026 integration update: Android submissions now include a persistent device identifier, backend device approval is live, and canonical employee identity for attendance/ZKTeco flows is now `employees.id`.

> March 8, 2026 device identity update: Android now prefers a stable OS-backed Android ID via `android_id` before falling back to a generated local identifier. This reduces duplicate smartphone rows in the backend attendance-device registry after app reinstall or storage reset.

> March 8, 2026 ZKTeco workflow update: backend ZKTeco attendance now also ingests ADMS `querydata` transaction history when live `rtlog` uploads are missing. Machine punches aggregate per day so the first punch becomes check-in and the last punch becomes check-out.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Technology Stack](#2-technology-stack)
3. [Project Structure](#3-project-structure)
4. [App Architecture](#4-app-architecture)
5. [Navigation Flow](#5-navigation-flow)
6. [Screen-by-Screen Reference](#6-screen-by-screen-reference)
7. [Face Recognition System](#7-face-recognition-system)
8. [Security Features](#8-security-features)
9. [Widgets](#9-widgets)
10. [Data Layer](#10-data-layer)
11. [Theme & Styling](#11-theme--styling)
12. [Android Configuration](#12-android-configuration)
13. [Dependencies](#13-dependencies)
14. [Assets](#14-assets)
15. [Build & Deployment](#15-build--deployment)
16. [Known Limitations & Future Work](#16-known-limitations--future-work)
17. [File-by-File Reference](#17-file-by-file-reference)

---

## 1. Project Overview

| Field | Value |
|---|---|
| **App Name** | PPHL Attendance System |
| **Display Name (Android)** | PPHL Attendance |
| **Package / Application ID** | `com.pphl.employee_attendance` |
| **Organization** | PPHL (Peoples Poultry & Hatchery Ltd.) |
| **Platform** | Android (Flutter cross-platform, only Android targeted) |
| **Purpose** | Employee attendance tracking with on-device face recognition and GPS verification |
| **Version** | 2.0.0+2 |
| **Dart SDK** | ^3.11.0 |
| **Flutter Channel** | Stable (3.41.2) |
| **APK Size** | ~105.6 MB (latest release build) |

### What the App Does

1. Employee logs in with email/password via backend JWT auth.
2. Employee registers their face via **5-capture multi-angle registration** (straight, left, right, up, down) with **live camera angle detection** — the system only captures when the face matches the target angle (stored on-device).
3. To check in for attendance, the employee:
  - Opens the check-in screen which activates the **front camera live preview** inside a human face-shaped container.
  - Must first place the face correctly inside the guide (size + centering gate) before any challenge can progress.
  - Completes **dynamic randomized liveness challenges (up to 5)** from the check-in page: look straight, smile, blink, turn left, turn right.
  - A **clockwise progress animation** fills around the face-shaped container as each accepted challenge is passed. If identity is verified early, remaining steps are skipped and the ring completes with a **green tick**.
  - The app verifies face identity using a **strict core-template threshold (~80% to 82% quality-aware)** with weighted top-k scoring over registration templates.
  - Identity approval requires **core consistency across multiple registration templates**; adaptive templates are supporting-only and cannot approve identity by themselves.
  - Verification uses **multi-attempt capture retry** (2 attempts during early checks, 3 attempts in final verification) and keeps the best confidence.
   - GPS location is captured and reverse-geocoded.
4. Dashboard shows attendance stats, weekly hours chart, and recent history.

---

## 2. Technology Stack

| Layer | Technology |
|---|---|
| **Framework** | Flutter 3.41.2 (Dart 3.11) |
| **Face Detection** | Google ML Kit Face Detection (`google_mlkit_face_detection: ^0.13.2`) — on-device, with landmarks + classification |
| **Face Embedding** | MobileFaceNet via TensorFlow Lite (`tflite_flutter: ^0.12.1`) — 112×112 input, 192-dim L2-normalized output |
| **Image Processing** | `image: ^4.8.0` — crop, resize, grayscale, Laplacian sharpness |
| **Camera** | `camera: ^0.11.1` — live camera preview for face scanning & registration |
| **Camera (legacy)** | `image_picker: ^1.2.1` — native camera UI (still available for fallback) |
| **GPS** | `geolocator: ^14.0.2` + `geocoding: ^4.0.0` — high accuracy + reverse geocode |
| **Permissions** | `permission_handler: ^12.0.1` — camera, location |
| **Device Identity** | `android_id: ^0.4.0` — stable Android device identifier for backend registry dedupe |
| **Local Storage** | `shared_preferences: ^2.5.4` — face embeddings, registration metadata |
| **UI/Animation** | `animate_do`, `google_fonts` (Poppins), `fl_chart`, `shimmer`, `percent_indicator`, `lottie`, `flutter_staggered_animations`, `cached_network_image` |
| **Minimum Android SDK** | API 26 (Android 8.0) — required by `tflite_flutter` |
| **Target SDK** | Flutter default (latest) |
| **Build System** | Gradle (Kotlin DSL), Flutter Gradle Plugin |

---

## 3. Project Structure

```
employee_attendance/
├── android/
│   └── app/
│       ├── build.gradle.kts          # Android build config (minSdk=26, appId=com.pphl.employee_attendance)
│       └── src/main/
│           └── AndroidManifest.xml   # Permissions: CAMERA, FINE_LOCATION, COARSE_LOCATION, INTERNET
├── assets/
│   └── models/
│       └── mobilefacenet.tflite      # MobileFaceNet model (~5.2 MB)
├── lib/
│   ├── main.dart                     # App entry point
│   ├── config/
│   │   └── theme.dart                # AppColors, AppTheme (Material 3, Poppins font)
│   ├── data/
│   │   └── dummy_data.dart           # Static dummy data for all screens
│   ├── screens/
│   │   ├── login_screen.dart         # Login UI (real backend auth)
│   │   ├── main_shell.dart           # Bottom nav shell (4 tabs)
│   │   ├── home_screen.dart          # Dashboard with stats, clock-in card, chart
│   │   ├── check_in_screen.dart      # Live camera check-in with dynamic liveness steps + circular progress
│   │   ├── face_registration_screen.dart  # 5-angle live camera face registration with face-path progress ring
│   │   ├── attendance_history_screen.dart # History list with filters
│   │   ├── notifications_screen.dart     # Notification list
│   │   └── profile_screen.dart           # Profile, settings, face registration shortcut
│   ├── services/
│   │   ├── auth_service.dart             # Backend auth API + token/session persistence
│   │   └── face_recognition_service.dart # Core ML service with angle detection (~1050 lines)
│   └── widgets/
│       ├── face_oval_guide.dart       # Face placement oval overlay
│       ├── stat_card.dart             # Dashboard stat card
│       └── attendance_tile.dart       # Attendance record row
├── pubspec.yaml                       # Dependencies & assets
├── analysis_options.yaml
└── test/
```

---

## 4. App Architecture

### Pattern
The app uses a **simple stateful widget architecture** without a state management library. Each screen manages its own state via `StatefulWidget` + `setState()`. The face recognition service is a **singleton** accessed directly.

### Key Architectural Decisions
- **No backend** — All data is local. Authentication is simulated. Face data is stored in `SharedPreferences`.
- **Singleton service** — `FaceRecognitionService` uses `factory` + `_internal()` pattern for a single instance across the app.
- **On-device ML** — No network calls for face recognition. ML Kit + TFLite run entirely on-device.
- **Camera via camera package** — Uses the Flutter `camera` package for live camera preview directly within the app. For registration, the system detects face angles in real-time and auto-captures. For check-in, challenges are evaluated live with a circular progress animation.

### Data Flow

```
User → Login (dummy) → MainShell → [Home | Attendance | Notifications | Profile]
                                      │                                    │
                                      ▼                                    ▼
                                 CheckInScreen                   FaceRegistrationScreen
                                      │                                    │
                                      ▼                                    ▼
                             FaceRecognitionService ◄──────────────────────┘
                               ├── ML Kit FaceDetector
                               ├── TFLite MobileFaceNet
                               ├── Liveness (smile + sharpness)
                               ├── Front-camera validation
                               ├── Same-person validation
                               └── SharedPreferences (embeddings)
```

---

## 5. Navigation Flow

```
LoginScreen
  └─(Sign In)→ MainShell (IndexedStack with BottomNavigationBar)
                  ├── Tab 0: HomeScreen
                  │     └─(Clock-In Card)→ CheckInScreen → (pop on success)
                  ├── Tab 1: AttendanceHistoryScreen
                  ├── Tab 2: NotificationsScreen
                  └── Tab 3: ProfileScreen
                        ├─(Register Face)→ FaceRegistrationScreen
                        └─(Sign Out)→ LoginScreen (pushAndRemoveUntil)
```

- **MainShell** uses `IndexedStack` to keep all 4 tab screens alive.
- **CheckInScreen** is pushed as a `MaterialPageRoute` from HomeScreen and pops after success.
- **FaceRegistrationScreen** is pushed from ProfileScreen's "Quick Actions → Register Face" card.

---

## 6. Screen-by-Screen Reference

### 6.1 LoginScreen (`login_screen.dart`, 402 lines)

| Aspect | Detail |
|---|---|
| **State** | `StatefulWidget` |
| **Auth** | Real backend auth via `POST /api/v1/a/login` |
| **Flow** | Backend-authenticated sign-in → profile hydration → `pushReplacement` to `MainShell` |
| **UI** | Dark gradient background (`AppColors.darkGradient`), animated PPHL GIF logo from `peoplespoultry.com`, login card with email/password fields, remember me checkbox |
| **Logo URL** | `https://peoplespoultry.com/assets/front/img/1730297252134723053.gif` |

### 6.2 MainShell (`main_shell.dart`, 126 lines)

| Aspect | Detail |
|---|---|
| **State** | `StatefulWidget` |
| **Tabs** | Home, Attendance, Alerts, Profile |
| **Nav Bar** | Custom `Row` of `GestureDetector` items with animated containers, rounded corners on the bar itself |
| **Screen Stack** | `IndexedStack` — all screens stay alive |

### 6.3 HomeScreen (`home_screen.dart`, 545 lines)

| Aspect | Detail |
|---|---|
| **State** | `StatefulWidget` (tracks `_isClockedIn`, `_checkInTime`) |
| **Header** | Gradient card with live backend avatar letters, employee name, designation/employee ID, greeting (dynamic AM/PM), today's check-in/out/hours |
| **Quick Stats** | 4 `StatCard` widgets: Present (18), Absent (1), Late (2), Leave (1) |
| **Clock-In Card** | Gradient card that navigates to `CheckInScreen`. On success callback: sets `_isClockedIn = true`, updates `_checkInTime` |
| **Weekly Chart** | `BarChart` from `fl_chart` showing Mon–Sun hours |
| **Recent Attendance** | List of top 5 `AttendanceTile` widgets |

### 6.4 CheckInScreen (`check_in_screen.dart`, ~1260 lines)

| Aspect | Detail |
|---|---|
| **State** | `StatefulWidget` with `TickerProviderStateMixin` |
| **Props** | `VoidCallback onCheckIn` — called on success |
| **Layout** | Fixed top (camera + face-path progress), scrollable middle (challenge status, verification/GPS cards), fixed bottom (action button) |
| **Camera** | Live front-camera preview using `camera` package, displayed inside a human face-shaped clip container (normal non-mirrored orientation) |
| **Flow** | Face-placement-gated dynamic challenge flow. See [Check-In Flow](#check-in-flow) below |

#### Check-In Flow

| Phase | What Happens |
|---|---|
| **Initializing** | Camera + FaceRecognitionService initialization, verify face is registered |
| **Scanning** | Live camera preview active. Each step is gated by face placement (must be centered and sized correctly in the face guide). Placement validation uses actual captured frame dimensions (not only preview metadata), includes width/height orientation fallback, and uses check-in centering tolerance tuned to ±35%. Liveness challenges run in randomized order with periodic `takePicture()` every 700ms. |
| **Verifying** | Early verification starts only after at least **2** challenges are passed (up to 2 captures). If a match is found, remaining steps are skipped; otherwise scanning continues. If all challenges are consumed, a final verification runs with up to 3 captures and best-confidence selection. |
| **GPS** | Face verified → capture GPS coordinates via `Geolocator` (high accuracy, 15s timeout) → reverse geocode address |
| **Success** | All steps complete → "Done ✓" button pops the screen and calls `onCheckIn` callback |
| **Error** | Any failure → error card + "Retry" button resets challenges |

#### Liveness Challenges (up to 5, randomized order)

| Challenge | Detection Method | Criteria |
|---|---|---|
| **Look Straight** | `isTargetAngle(face, FaceAngle.straight)` | \|yaw\| < 14° AND \|pitch\| < 14°, held for 2 frames (~1.4s) |
| **Smile** | `isSmiling(face)` | `smilingProbability ≥ 55%` |
| **Blink** | State machine: eyes open → eyes closed → eyes open | `leftEyeOpenProbability` + `rightEyeOpenProbability` thresholds |
| **Turn Left** | `isTargetAngle(face, FaceAngle.left)` | yaw in [15°, 55°], held for 2 frames |
| **Turn Right** | `isTargetAngle(face, FaceAngle.right)` | yaw in [-55°, -15°], held for 2 frames |

#### Face-Path Progress Animation

- Custom `_FaceScanProgressPainter` draws a clockwise progress path around a human face-shaped guide
- Progress fills in 20% increments for each accepted challenge and can jump to completion on early verification
- Track color: white 15% opacity; progress color: `AppColors.primary` (blue) → `AppColors.success` (green) when complete
- On 100%: `ScaleTransition` with `Curves.elasticOut` shows a green circle with checkmark icon
- Stroke width: 5px (track) / 6px (progress path) with rounded caps/joins

### 6.5 FaceRegistrationScreen (`face_registration_screen.dart`, ~1000 lines)

| Aspect | Detail |
|---|---|
| **State** | `StatefulWidget` with `TickerProviderStateMixin` |
| **Camera** | Live front-camera preview using `camera` package in normal non-mirrored orientation, with face-shaped guide and progress ring |
| **Flow** | Delete old registration → Auto-detect angle 1 (straight) → Auto-capture → Angle 2 (left) → ... → Angle 5 (down) → Done |
| **Angle Detection** | Periodic `takePicture()` every 700ms → face placement gate (orientation-robust width/height fallback + ±28% centering tolerance) → live quality gate (also evaluated with orientation fallback) → `isTargetAngle(face, targetAngle)`. When target angle is held for 2 frames (~1.4s), auto-captures. |
| **5 Angles** | Straight (\|yaw\|<14, \|pitch\|<14), Left (yaw 15–55°), Right (yaw -55– -15°), Up (pitch 9–45°), Down (pitch -70– -6°) |
| **Same-Person** | Each new embedding checked against all previous captures via cosine similarity ≥ 65% |
| **Quality** | Every step is pre-validated in live analysis (`checkFrontCamera` placement + `checkFaceQuality`) before angle hold/capture. Capture-time validation still runs via `registerFaceCapture()` pipeline. |
| **UI** | Step indicator dots (5), camera preview with face-shaped overlay (`_FaceOvalOverlayPainter`), animated face-path progress ring (`_FaceRegistrationProgressPainter`), angle icon + instruction overlay, capture flash animation, completion overlay with green checkmark, progress list card, tips card, done button |

### 6.6 AttendanceHistoryScreen (`attendance_history_screen.dart`, 349 lines)

| Aspect | Detail |
|---|---|
| **State** | `StatefulWidget` with `_selectedFilter` (All/Present/Absent/Late/Leave) |
| **Header** | Gradient card with `CircularPercentIndicator` (81.8%), month label |
| **Summary** | Working Days / Present / Late / Absent / Leave counts |
| **Filters** | Chip row that filters `DummyData.recentAttendance` |
| **Records** | Filtered list of `AttendanceTile` widgets |

### 6.7 NotificationsScreen (`notifications_screen.dart`, 307 lines)

| Aspect | Detail |
|---|---|
| **State** | `StatelessWidget` |
| **Sections** | "Today" (4 notifications from DummyData) + "Earlier" (3 hardcoded extras) |
| **UI** | Each notification tile has icon mapping (alarm→warning, check_circle→success, etc.) and read/unread state |

### 6.8 ProfileScreen (`profile_screen.dart`, 472 lines)

| Aspect | Detail |
|---|---|
| **State** | `StatelessWidget` |
| **Sections** | Header (avatar, name, designation, employee ID), Personal Info card, Quick Actions (Leave Request, View Reports, **Register Face**, My QR Code), Settings (Notifications, Location, Dark Mode, Language, Password, Help, About), Sign Out |
| **Face Reg** | "Register Face" quick action card navigates to `FaceRegistrationScreen` |
| **Sign Out** | `pushAndRemoveUntil` → `LoginScreen` |

---

## 7. Face Recognition System

### 7.1 Overview

The face recognition pipeline is implemented entirely on-device in `FaceRecognitionService` (singleton, ~1050 lines). It combines Google ML Kit for face detection/analysis and MobileFaceNet (TFLite) for face embedding generation.

### 7.2 FaceRecognitionService API

#### Constants

| Constant | Value | Purpose |
|---|---|---|
| `_inputSize` | 112 | MobileFaceNet input image size (112×112 pixels) |
| `_embeddingSize` | 192 | Output embedding dimensionality |
| `_matchThreshold` | 0.80 | Base minimum cosine similarity for **core** identity match (quality-aware to ~82% for lower quality) |
| `_strongMatchThreshold` | 0.88 | Strong **core-template** similarity with consistency requirement |
| `_adaptiveEnrollmentThreshold` | 0.86 | Minimum core confidence required before adding adaptive templates |
| `_samePersonThreshold` | 0.65 | Minimum cosine similarity between registration captures to confirm same person |
| `_smileThreshold` | 0.55 | Minimum `smilingProbability` from ML Kit for smile liveness |
| `_minFaceRatioForSelfie` | 0.06 | Minimum face-area-to-image-area ratio (6%) for front camera validation |
| `_minSharpnessScore` | 15.0 | Minimum Laplacian variance for sharpness/screen detection |
| `registrationCaptures` | 5 | Number of photos taken during multi-capture registration |
| `registrationAngles` | [straight, left, right, up, down] | Ordered list of target angles for registration |

#### SharedPreferences Keys

| Key | Type | Purpose |
|---|---|---|
| `registered_face_embeddings` | `String` (JSON array of arrays) | All individual capture embeddings |
| `registered_face_avg_embedding` | `String` (JSON array) | Averaged + L2-normalized embedding |
| `registered_face_adaptive_embeddings` | `String` (JSON array of arrays) | Rolling templates auto-learned from successful verifications (max 20) |
| `face_registration_time` | `String` (ISO 8601) | Registration timestamp |
| `face_registration_count` | `int` | Number of captures used |

#### Public Methods

| Method | Signature | Description |
|---|---|---|
| `initialize()` | `Future<void>` | Loads TFLite model + creates ML Kit FaceDetector |
| `detectFaces(File)` | `Future<List<Face>>` | Raw ML Kit face detection |
| `checkLiveness(File, {bool requireSmile})` | `Future<LivenessResult>` | Full liveness analysis (multi-face, smile, eyes, face size, sharpness) |
| `checkFrontCamera(Face, int, int, {bool requireCentering = true, double centerTolerance = 0.3})` | `FrontCameraCheckResult` | Validates front-camera selfie via face size, and optionally centering |
| `detectFaceAngle(Face)` | `FaceAngle` | Detect current face angle from ML Kit euler angles |
| `isTargetAngle(Face, FaceAngle)` | `bool` | Check if face matches a target angle with tolerance |
| `isSmiling(Face)` | `bool` | Check if smilingProbability ≥ 55% |
| `areEyesClosed(Face)` | `bool` | Check if both eyes are closed (probability < 0.3) |
| `areEyesOpen(Face)` | `bool` | Check if both eyes are open (probability > 0.5, with angled-capture quality check tolerance handled in `checkFaceQuality`) |
| `detectFacesFromInputImage(InputImage)` | `Future<List<Face>>` | Detect faces from InputImage (for live camera frames) |
| `angleDisplayName(FaceAngle)` | `String` (static) | Human-readable angle name |
| `angleInstruction(FaceAngle)` | `String` (static) | Instruction text for registration |
| `challengeInstruction(ChallengeType)` | `String` (static) | Instruction text for check-in challenges |
| `isSamePerson(List<double>, List<List<double>>)` | `bool` | Compares new embedding against all existing embeddings |
| `checkFaceQuality(Face, int, int, {skipRotationCheck})` | `FaceQualityResult` | Face size, rotation (yaw/pitch/roll), centering, eye-open checks. `skipRotationCheck` skips yaw/pitch/roll penalties (used for angled registration captures). |
| `generateEmbedding(File, {checkQuality, checkLivenessSmile, checkFrontCam, requireFrontCamCentering, skipRotationCheck})` | `Future<EmbeddingResult>` | Full pipeline: detect → validate quality → validate front camera → check sharpness → check smile → crop → robust variant embeddings (original, flipped, grayscale, grayscale+flipped) → averaged embedding → L2 normalize. `requireFrontCamCentering` controls centering strictness; `skipRotationCheck` passed through to quality check. |
| `registerFaceCapture(File, {int captureNumber, FaceAngle? targetAngle})` | `Future<FaceRegistrationResult>` | Single capture in a multi-capture registration flow. `targetAngle` enables `skipRotationCheck` for non-straight angles. |
| `registerFace(File)` | `Future<FaceRegistrationResult>` | Legacy single-photo registration |
| `verifyFace(File, {bool requireSmile})` | `Future<FaceVerificationResult>` | Full verification: generate robust embedding with all checks → compare against stored average + registration captures (core templates) → weighted top-k + core-hit consistency decision (quality-aware threshold) → evaluate adaptive templates as supporting signals only → auto-enroll adaptive template only on high-confidence core matches |
| `isFaceRegistered()` | `Future<bool>` | Check if embeddings exist in SharedPreferences |
| `getRegistrationTime()` | `Future<String?>` | Get stored registration timestamp |
| `getRegistrationCaptureCount()` | `Future<int>` | Get number of captures used |
| `deleteRegisteredFace()` | `Future<void>` | Remove all stored face data |
| `dispose()` | `void` | Close detector + interpreter |

#### Result Classes

| Class | Fields | Purpose |
|---|---|---|
| `LivenessResult` | `isLive`, `issues` (list), `smileProbability`, `sharpnessScore` | Full liveness check result |
| `FrontCameraCheckResult` | `isFrontCamera`, `faceRatio`, `issue` | Front camera validation result |
| `FaceQualityResult` | `score` (0–100), `issues` (list), `isAcceptable`, `faceRatio`, `yaw`, `pitch` | Face quality assessment |
| `EmbeddingResult` | `embedding` (192-dim or null), `quality`, `error` | Embedding generation result |
| `FaceRegistrationResult` | `success`, `message`, `quality`, `captureNumber`, `totalCaptures`, `isPartial`, `isDifferentPerson` | Registration capture result |
| `FaceVerificationResult` | `isMatch`, `confidence` (0–100), `message`, `quality` | Verification result |

### 7.3 Processing Pipeline

#### Registration Pipeline (per capture, 5 angles)

```
Live Camera Preview (front, non-mirrored, periodic takePicture every 700ms)
  → ML Kit Face Detection (accurate mode, minFaceSize 0.25)
    → Placement Gate: face must be centered and correctly sized in guide (orientation-aware width/height fallback)
    → Live Quality Gate: quality checks must pass before step progression
    → Angle Detection: isTargetAngle(face, targetAngle)
    → Must hold target angle for 2 frames (~1.4s)
    → Auto-capture when angle matches
    → Reject if 0 faces or >1 face
    → Front Camera Validation (face ratio ≥ 6%; centering required for straight capture, relaxed for non-straight captures)
    → Face Quality Check (size, centering, eyes open; rotation checks SKIPPED for non-straight angles)
    → Sharpness Check (Laplacian variance ≥ 15.0 on face region)
    → Same-Person Check (cosine similarity ≥ 65% against all previous captures)
    → Crop face (40% padding, make square)
    → Generate 4 embedding variants (original, mirrored, grayscale, grayscale+mirrored)
    → Average variant embeddings
    → L2 normalization
    → Store in SharedPreferences
    → If final capture (5th): compute averaged embedding, store alongside individuals, clear adaptive templates
```

#### Verification Pipeline (check-in with live challenges)

```
Live Camera Preview (front, face-shaped container, non-mirrored display)
  → Periodic frame analysis (takePicture every 700ms)
  → Placement Gate: face must be centered and correctly sized in face guide (orientation-aware width/height fallback)
  → Randomized Liveness Challenges (dynamic, up to 5):
    1. Look Straight — isTargetAngle(straight), hold 2 frames
    2. Smile — smilingProbability ≥ 55%
    3. Blink — state machine: eyes open → closed → open
    4. Turn Left — isTargetAngle(left), hold 2 frames
    5. Turn Right — isTargetAngle(right), hold 2 frames
  → Clockwise face-path progress ring fills as accepted steps complete
  → After at least 2 completed challenges: early `verifyFace()` attempt (up to 2 image captures)
    → If matched: skip remaining challenges, show completion tick, continue to GPS
    → If not matched: continue with next challenge
  → If all challenges are used without early match: final verification (up to 3 image captures)
  → Full embedding pipeline:
    → ML Kit Face Detection
    → Reject if 0 faces or >1 face
    → Front Camera Validation
    → Face Quality Check
    → Sharpness Check (Laplacian variance)
    → Crop → variant embeddings (normal/flipped/grayscale) → averaged embedding
    → Load stored average embedding from SharedPreferences
    → Cosine similarity against average + each registration embedding (core)
    → Weighted top-k aggregate on core templates (top1 60%, top2 25%, top3 15%)
    → Require core consistency (minimum core-hit count) plus quality-aware threshold (~80% / ~82%)
    → Evaluate adaptive-template similarity only as supporting signal (not approval source)
    → On high-confidence core success: auto-save embedding as adaptive template (deduped, rolling max 20)
  → GPS capture (high accuracy, 15s timeout)
  → Reverse geocode
  → Success
```

### 7.4 Enums

#### FaceAngle
| Value | Detection Criteria |
|---|---|
| `straight` | \|yaw\| < 14° AND \|pitch\| < 14° |
| `left` | yaw ∈ [15°, 55°] |
| `right` | yaw ∈ [-55°, -15°] |
| `up` | pitch ∈ [9°, 45°] |
| `down` | pitch ∈ [-70°, -6°] |
| `unknown` | Does not match any of the above |

#### ChallengeType
| Value | Instruction |
|---|---|
| `lookStraight` | "Look straight at the camera" |
| `smile` | "Smile! 😄" |
| `blink` | "Blink your eyes" |
| `turnLeft` | "Turn your face slightly left" |
| `turnRight` | "Turn your face slightly right" |

### 7.5 Embedding Math

- **Cosine Similarity**: `dot(a, b)` where `a` and `b` are L2-normalized (so cosine similarity = dot product). Clamped to [-1, 1].
- **L2 Normalization**: `v[i] / sqrt(sum(v[j]²))` — ensures unit-length vectors.
- **Averaging Embeddings**: Element-wise mean of N embeddings, then L2-normalize the result.
- **Thresholds**: 80% base core match (quality-aware up to 82%), 88% strong core-match override (with consistency), 86% minimum core similarity for adaptive enrollment, 65% for same-person validation.

### 7.6 Sharpness Analysis (Anti-Screen-Photo)

1. Crop raw image to face bounding box region.
2. Resize to 64×64 for fast computation.
3. Convert to grayscale using standard luminance weights (0.299R + 0.587G + 0.114B).
4. Apply 3×3 Laplacian kernel: `[0 1 0 / 1 -4 1 / 0 1 0]`.
5. Compute variance (mean of squared Laplacian values).
6. If variance < 15.0: reject as possible photo-of-screen.

---

## 8. Security Features

### 8.1 Liveness Detection (Anti-Spoofing)

| Check | Method | Threshold |
|---|---|---|
| **Smile Challenge** | ML Kit `smilingProbability` — user must smile during check-in liveness challenges | ≥ 55% |
| **Blink Challenge** | ML Kit `leftEyeOpenProbability` + `rightEyeOpenProbability` — state machine detects open→closed→open transition | < 30% (closed), > 50% (open) |
| **Angle Challenges** | ML Kit `headEulerAngleY` (yaw) + `headEulerAngleX` (pitch) — user must turn face to specified directions | Target ranges per FaceAngle enum |
| **Sharpness Analysis** | Laplacian variance on face region — photos of screens have lower edge contrast | ≥ 15.0 |
| **Eye Openness** | ML Kit `leftEyeOpenProbability` + `rightEyeOpenProbability` — both-eyes-closed suggests a still photo | ≥ 40% each |
| **Multi-Face Rejection** | If >1 face detected, reject (prevents showing a group photo) | Exactly 1 face |
| **Guide Alignment Gate** | Face must be aligned to the face guide before registration/check-in steps can progress | Centered + front-camera face ratio checks |

### 8.2 Back Camera Prevention

The app uses the Flutter `camera` package to programmatically select the front camera. The `CameraController` is initialized with `CameraLensDirection.front`. Additionally, **post-capture validation** is still applied:

| Check | Logic | Threshold |
|---|---|---|
| **Face Size Ratio** | `faceArea / imageArea` — front-camera selfies have large faces; back-camera shots have smaller faces | ≥ 6% |
| **Face Centering** | Face center must be within ±30% of image center — selfies are centered | Within bounds |
| **Camera Selection** | `CameraController` initialized with `CameraLensDirection.front` | Programmatic (not just a hint) |

### 8.3 Same-Person Validation (Registration Integrity)

During multi-capture registration (5 photos, each at a different angle):

| Check | Logic | Threshold |
|---|---|---|
| **Inter-Capture Similarity** | Each new embedding is compared against all previously stored captures via cosine similarity | ≥ 65% |
| **Failure Handling** | If a different person is detected, a prominent dialog warns the user and the capture is rejected (user can retry the same capture) | N/A |

### 8.4 Face Quality Gates

Every face capture (registration and check-in) passes through quality checks:

| Quality Check | Condition | Impact |
|---|---|---|
| Face too far | `faceRatio < 5%` | -40 score, rejected |
| Face a bit far | `faceRatio < 10%` | -20 score |
| Face too close | `faceRatio > 70%` | -20 score |
| Excessive yaw | `abs(yaw) > 25°` | -30 score |
| Slight yaw | `abs(yaw) > 15°` | -15 score |
| Excessive pitch | `abs(pitch) > 20°` | -25 score |
| Excessive roll | `abs(roll) > 15°` | -15 score |
| Off-center | Face center > ±25% from image center | -20 score |
| Eyes closed | `eyeOpenProbability < 50%` | -20 score |
| **Acceptable** | `score ≥ 50` AND no "too far" issue | Pass |

---

## 9. Widgets

### 9.1 FaceOvalGuide (`face_oval_guide.dart`, 344 lines)

A reusable face placement overlay widget used by both `CheckInScreen` and `FaceRegistrationScreen`.

| Feature | Detail |
|---|---|
| **Oval Cutout** | Custom `CustomPaint` with `PathFillType.evenOdd` — semi-transparent background with oval hole |
| **Corner Marks** | 4 L-shaped corner marks positioned at oval boundaries |
| **Eye Guides** | 2 small circles at eye-level position (hidden during processing/success) |
| **Alignment Lines** | Horizontal + vertical dashed center lines (hidden during processing) |
| **Instruction Text** | Configurable text below the oval |
| **States** | Normal (guide color), Processing (orange, thicker border), Success (green) |
| **Animated Variant** | `AnimatedFaceOvalGuide` — pulsing opacity via `AnimationController` (1800ms repeat) |

### 9.2 StatCard (`stat_card.dart`, 68 lines)

A compact card showing a single statistic (used in HomeScreen quick stats row).

| Prop | Type | Purpose |
|---|---|---|
| `label` | `String` | Label text (e.g., "Present") |
| `value` | `String` | Numeric value (e.g., "18") |
| `icon` | `IconData` | Status icon |
| `color` | `Color` | Theme color for icon background |

### 9.3 AttendanceTile (`attendance_tile.dart`, 199 lines)

A row widget displaying a single attendance record.

| Prop | Type | Purpose |
|---|---|---|
| `record` | `Map<String, dynamic>` | Contains `date`, `day`, `checkIn`, `checkOut`, `status`, `workHours`, `verifiedBy` |

**Status colors**: present→green, absent→red, late→warning, leave→info, weekend→hint gray.

---

## 10. Data Layer

### 10.1 DummyData (`dummy_data.dart`)

`DummyData` still exists for visual placeholders, but the app now uses live backend APIs for login, profile identity, face registration, and attendance history.

| Data | Source |
|---|---|
| **User profile** | Live backend profile from `GET /api/v1/get-my-info` |
| **Attendance stats** | Hard-coded: 22 working days, 18 present, 1 absent, 2 late, 1 leave, 81.8% |
| **Today's status** | Hard-coded: not clocked in, no check-in/out times |
| **Recent attendance** | Hard-coded list of 10 records (Feb 15–24, 2026) |
| **Weekly hours** | Hard-coded: Mon 9.0, Tue 9.2, Wed 0.0, Thu 9.5, Fri 8.5, Sat 0.0, Sun 0.0 |
| **Notifications** | Hard-coded list of 4 + 3 "earlier" items |
| **Team members** | Hard-coded list of 6 (not displayed currently) |

### 10.2 SharedPreferences (Face Data)

| Key | Content |
|---|---|
| `registered_face_embeddings` | JSON array of 1–5 individual 192-dim embedding arrays |
| `registered_face_avg_embedding` | JSON array of 1 averaged 192-dim embedding |
| `registered_face_adaptive_embeddings` | JSON array of adaptive verification-time embeddings (up to 20) |
| `face_registration_time` | ISO 8601 timestamp string |
| `face_registration_count` | Integer count of captures (1–5) |

### 10.3 GPS Data

GPS coordinates and reverse-geocoded address are captured at check-in time but **only displayed on the check-in screen**. They are **not persisted** to any storage after the screen is closed.

---

## 11. Theme & Styling

### 11.1 AppColors

| Color | Hex | Usage |
|---|---|---|
| `primary` | `#1A73E8` | Buttons, links, active nav items |
| `primaryDark` | `#0D47A1` | Dark variant |
| `primaryLight` | `#BBDEFB` | Light variant |
| `accent` | `#00BFA5` | Secondary actions, location step |
| `success` | `#00C853` | Check-in success, "present" status |
| `warning` | `#FFAB00` | Late status, retry buttons |
| `error` | `#FF1744` | Absent status, delete actions |
| `info` | `#2979FF` | Leave status, info badges |
| `background` | `#F5F7FA` | Scaffold background (light screens) |
| `surface` | `#FFFFFF` | Cards, inputs |
| `textPrimary` | `#1A1A2E` | Main text |
| `textSecondary` | `#6B7280` | Secondary text |
| `textHint` | `#9CA3AF` | Hint text, inactive items |

### 11.2 Gradients

| Name | Colors | Usage |
|---|---|---|
| `primaryGradient` | `#1A73E8 → #6C63FF` | Headers, clock-in card |
| `successGradient` | `#00C853 → #00BFA5` | Checked-in state |
| `warmGradient` | `#FF6B6B → #FFAB00` | Not currently used |
| `darkGradient` | `#1A1A2E → #16213E` | Login screen background |

### 11.3 Dark Theme Screens

The following screens use a dark background (`Color(0xFF0A0E21)`), not `AppColors.background`:
- `CheckInScreen`
- `FaceRegistrationScreen`

All other screens use the light `AppColors.background`.

### 11.4 Typography

- **Font**: Google Fonts Poppins (all weights from 400 to 800)
- **Sizes**: h1=28, h2=24, h3=20, title=18, body=14-16, caption=10-12

---

## 12. Android Configuration

### 12.1 build.gradle.kts

```kotlin
namespace = "com.pphl.employee_attendance"
applicationId = "com.pphl.employee_attendance"
minSdk = 26        // Required for tflite_flutter
targetSdk = flutter.targetSdkVersion
compileSdk = flutter.compileSdkVersion
```

- **Java/Kotlin**: Java 17 compatibility
- **Signing**: Debug keys for release (TODO: production signing)
- **NDK**: Flutter default

### 12.2 AndroidManifest.xml Permissions

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-feature android:name="android.hardware.camera" android:required="false"/>
<uses-feature android:name="android.hardware.location.gps" android:required="false"/>
```

### 12.3 App Label

```xml
android:label="PPHL Attendance"
```

---

## 13. Dependencies

### Production Dependencies

| Package | Version | Purpose |
|---|---|---|
| `flutter` | SDK | Core framework |
| `cupertino_icons` | ^1.0.8 | iOS-style icons |
| `google_fonts` | ^8.0.2 | Poppins font |
| `intl` | ^0.20.2 | Internationalization/date formatting |
| `fl_chart` | ^1.1.1 | Bar chart on home screen |
| `shimmer` | ^3.0.0 | Loading shimmer effects |
| `animate_do` | ^4.2.0 | Entry animations (FadeIn, FadeInUp, FadeInDown) |
| `cached_network_image` | ^3.4.1 | Logo image caching |
| `percent_indicator` | ^4.2.5 | Circular attendance percentage |
| `lottie` | ^3.3.2 | Lottie animations (available but not currently used in UI) |
| `flutter_staggered_animations` | ^1.1.1 | Staggered list animations (available but not currently used) |
| `image_picker` | ^1.2.1 | Camera access (legacy, available for fallback) |
| `camera` | ^0.11.1 | Live camera preview for face scanning & registration |
| `geolocator` | ^14.0.2 | GPS coordinates |
| `geocoding` | ^4.0.0 | Reverse geocoding (coords → address) |
| `permission_handler` | ^12.0.1 | Runtime permission requests |
| `google_mlkit_face_detection` | ^0.13.2 | On-device face detection with landmarks + classification |
| `tflite_flutter` | ^0.12.1 | TensorFlow Lite inference for MobileFaceNet |
| `image` | ^4.8.0 | Image decoding, cropping, resizing, pixel access |
| `shared_preferences` | ^2.5.4 | Local key-value storage for face embeddings |

### Dev Dependencies

| Package | Version | Purpose |
|---|---|---|
| `flutter_test` | SDK | Testing framework |
| `flutter_lints` | ^6.0.0 | Lint rules |

---

## 14. Assets

| Asset | Path | Size | Purpose |
|---|---|---|---|
| MobileFaceNet | `assets/models/mobilefacenet.tflite` | ~5.2 MB | Face embedding model (112×112 → 192-dim) |

Declared in `pubspec.yaml`:
```yaml
assets:
  - assets/models/mobilefacenet.tflite
```

---

## 15. Build & Deployment

### Build Command

```powershell
cd C:\Users\ciphe\OneDrive\Documents\GitHub\employee_attendance
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
& "C:\flutter\bin\flutter.bat" build apk --release --target-platform android-arm,android-arm64
```

### Build Output

```
build\app\outputs\flutter-apk\app-release.apk  (~105.6 MB, latest release build)
```

### Environment

| Tool | Path / Version |
|---|---|
| Flutter SDK | `C:\flutter` (3.41.2, stable) |
| Android SDK | `C:\Users\ciphe\AppData\Local\Android\Sdk` (36.1.0) |
| Java | JDK 17 (via Android Studio) |
| OS | Windows 11 (25H2) |
| Project | `C:\Users\ciphe\OneDrive\Documents\GitHub\employee_attendance` |

### Known Build Notes

- OneDrive sync can cause file locking during builds — clean `build/` folder first.
- If CMake/NDK configure fails in OneDrive path (for example `:app:configureCMakeRelease[arm64-v8a]`), build in a non-OneDrive path such as `C:\temp\employee_attendance_build`, then copy the APK back.
- If release fails on `:app:stripReleaseDebugSymbols` with missing `...\out\lib\x86`, build with explicit ABIs: `--target-platform android-arm,android-arm64`.
- APK size depends on ABI selection (the current full release build is ≈105.6 MB; ABI-targeted builds are smaller).
- The build uses debug signing keys — a release keystore is needed for production.

---

## 16. Known Limitations & Future Work

### Current Limitations

| Area | Limitation |
|---|---|
| **Authentication** | Requires live backend JWT auth from `pphl_erp`; offline login is not supported |
| **Data persistence** | Core attendance, profile, face registration, and approval data are backend-driven; some dashboard widgets still use static/demo values |
| **Backend** | Live API integration is required for production flows; the app is no longer an offline-only prototype |
| **Face data** | Stored in `SharedPreferences` (plain JSON) — not encrypted |
| **GPS data** | Captured but not persisted after screen closes |
| **Camera** | Uses `camera` package for live preview — full programmatic control over front camera. Angle detection, smile/blink checks done in real-time via periodic `takePicture()` calls. |
| **Single user** | Only one face can be registered at a time (single-tenant) |
| **Liveness** | Passive (smile + sharpness) — no active 3D depth or IR checks |
| **Notifications** | Static dummy data, no push notification integration |
| **Settings** | Toggle switches in Profile are non-functional |
| **APK size** | Large due to ML Kit + TFLite + camera native libs (ABI-targeted build reduces size) |
| **iOS** | Not tested or configured (Android only) |

### Suggested Future Enhancements

| Priority | Enhancement |
|---|---|
| **High** | Backend API integration (auth, attendance records, user management) |
| **High** | Real database (SQLite/Hive for local cache, REST/GraphQL for server) |
| **High** | Encrypt stored face embeddings (AES/flutter_secure_storage) |
| **High** | Production signing key for release APK |
| **Medium** | Geofencing — restrict check-in to within X meters of office coordinates |
| **Medium** | Check-out flow (currently only check-in exists) |
| **Medium** | Multiple user support / login switching |
| **Medium** | Admin dashboard (manager can see team attendance) |
| **Medium** | Leave request submission flow |
| **Medium** | Push notifications (Firebase Cloud Messaging) |
| **Medium** | Add guided re-registration flow for major appearance changes (new glasses style, heavy beard changes) |
| **Low** | Active liveness (head-turn challenge, blink detection) |
| **Low** | Dark mode toggle (currently only Login/CheckIn/FaceReg use dark backgrounds) |
| **Low** | Localization (currently English only) |
| **Low** | App size reduction (split APK per ABI) |
| **Low** | iOS support |

### Face Recognition Library Research (Web, Feb 2026)

The current stack uses **ML Kit for detection** and **MobileFaceNet for identity**. From public docs/repositories reviewed:

| Option | Fit for This App | Notes |
|---|---|---|
| **Current (MobileFaceNet + ML Kit)** | ✅ Already integrated | Fast on-device, lightweight, but lower invariance to appearance shifts than newer SOTA embeddings. |
| **ArcFace/InsightFace family** | ✅ Strong technical candidate | Widely used high-accuracy models; robust to occlusion/appearance in many benchmarks. Integration in Flutter typically requires custom native bridge (JNI/FFI) and careful licensing review. |
| **InspireFace SDK (InsightFace ecosystem)** | ✅ Practical migration path (Android) | Cross-platform C/C++/Android SDK with detection, embedding, comparison, liveness modules. Better out-of-box tooling, but commercial use/licensing should be confirmed with vendor. |
| **DeepFace** | ⚠️ Backend-oriented | Great experimentation wrapper (many models), but Python-centric and less suitable for direct on-device Flutter embedding pipeline. |
| **ML Kit only** | ❌ Not enough for identity | ML Kit docs explicitly state it detects faces and attributes, but does **not** recognize people identities. |

**Recommended migration strategy if current improvements are still insufficient:**
1. Keep current implementation as fallback path.
2. Prototype ArcFace-class embedding model (or InspireFace SDK) in an Android native module.
3. Run A/B benchmark on real employee set (glasses on/off, beard/moustache on/off, indoor/outdoor lighting).
4. Promote the better model behind a feature flag after threshold calibration.

---

## 17. File-by-File Reference

### `lib/main.dart` (32 lines)
- Entry point. Calls `runApp(AttendEaseApp())`.
- Sets status bar to transparent with light icons.
- Root widget: `MaterialApp` with title "PPHL Attendance System", `AppTheme.lightTheme`, home: `LoginScreen`.

### `lib/config/theme.dart` (~190 lines)
- `AppColors`: 24 color constants + 4 gradient definitions.
- `AppTheme.lightTheme`: Material 3 theme with Poppins font, custom card/button/input/appbar/navbar themes.

### `lib/data/dummy_data.dart` (~170 lines)
- Static class with all dummy data: user profile, attendance stats, recent records, weekly hours, notifications, team members.

### `lib/services/face_recognition_service.dart` (~1048 lines)
- Singleton service handling all face recognition, liveness, camera validation, angle detection, and registration.
- New enums: `FaceAngle` (straight, left, right, up, down, unknown), `ChallengeType` (lookStraight, smile, blink, turnLeft, turnRight).
- New methods: `detectFaceAngle()`, `isTargetAngle()`, `isSmiling()`, `areEyesClosed()`, `areEyesOpen()`, `detectFacesFromInputImage()`, plus static instruction helpers.
- `registrationCaptures` changed from 3 to 5 with `registrationAngles` list.
- `checkFaceQuality()` accepts `skipRotationCheck` and applies a relaxed eye-open threshold (0.35) for angled registration captures.
- `generateEmbedding()` now performs robust embedding fusion from 4 variants (normal + mirrored + grayscale + grayscale mirrored).
- `verifyFace()` now uses weighted top-k similarity over **core registration templates** with quality-aware thresholding and minimum-hit consistency checks.
- Adaptive templates are treated as supporting signals only and cannot directly approve identity.
- Adaptive templates (`registered_face_adaptive_embeddings`, max 20, deduped) are auto-enrolled only on high-confidence core matches.
- See [Section 7](#7-face-recognition-system) for complete API documentation.

### `lib/screens/login_screen.dart` (402 lines)
- Animated login screen with PPHL GIF logo, email/password fields, dummy auth (2s delay), social login buttons.

### `lib/screens/main_shell.dart` (126 lines)
- Bottom navigation shell with 4 tabs (Home, Attendance, Alerts, Profile) using `IndexedStack`.

### `lib/screens/home_screen.dart` (545 lines)
- Dashboard with gradient header, stats row (4 StatCards), clock-in card (navigates to CheckInScreen), weekly bar chart, recent attendance list.

### `lib/screens/check_in_screen.dart` (~1318 lines)
- Live-camera check-in with randomized, dynamic liveness challenges (up to 5): look straight, smile, blink, turn left, turn right.
- Front camera preview displayed in normal non-mirrored orientation inside a human face-shaped clipped container.
- Every step is gated by face placement (center/size) before challenge logic progresses.
- Face-placement gate uses decoded captured-frame dimensions first, then fallback to preview dimensions; both normal and swapped width/height mappings are evaluated to prevent false "not centered" failures on some devices.
- Check-in centering tolerance is relaxed to ±35% to improve robustness across device camera metadata/layout differences.
- `_FaceScanProgressPainter` custom painter draws an animated clockwise progress path around the face guide.
- Green tick animation (`ScaleTransition` + `Curves.elasticOut`) on completion (including early-verified completion).
- Performs early identity verification after at least 2 completed challenges; if matched, remaining steps are skipped and GPS flow starts.
- Early verification now uses up to 2 captures and final verification uses up to 3 captures, taking the best confidence.
- If no early match, falls back to final multi-attempt verification after remaining challenges.
- Layout: fixed camera section (top), scrollable challenge/status cards (middle), fixed action button (bottom).
- Phases: initializing → scanning → verifying → gps → success | error.
- Blink detection uses a 3-phase state machine: `waitingOpen` → `waitingClosed` → `waitingReopen` → `done`.

### `lib/screens/face_registration_screen.dart` (~1000 lines)
- 5-angle live-camera face registration: straight, left, right, up, down.
- Front camera preview with face-shaped overlay (`_FaceOvalOverlayPainter`) plus animated face-path progress ring (`_FaceRegistrationProgressPainter`).
- Periodic `takePicture()` every 700ms for real-time angle detection.
- Each step is gated by placement and live quality checks before angle hold begins.
- Placement + live quality gates use orientation-robust dimension fallback to avoid being stuck on face-placement messaging when camera metadata orientation differs.
- Auto-captures when target angle is held for 2 frames (~1.4s) for improved capture clarity.
- Step indicator dots (5), capture flash animation, completion overlay.
- Same-person validation between captures (cosine similarity ≥ 65%).
- Different-person alert dialog.

### `lib/screens/attendance_history_screen.dart` (349 lines)
- Attendance history with circular percentage indicator, monthly summary, filter chips, record list.

### `lib/screens/notifications_screen.dart` (307 lines)
- Notification list with "Today" and "Earlier" sections, icon/color mapping per notification type.

### `lib/screens/profile_screen.dart` (472 lines)
- Profile header, personal info card, quick actions (including Face Registration navigation), settings toggles, logout.

### `lib/widgets/face_oval_guide.dart` (344 lines)
- Face placement oval overlay with cutout, corner marks, eye guides, alignment lines. Has animated variant.

### `lib/widgets/stat_card.dart` (68 lines)
- Compact stat card widget for dashboard.

### `lib/widgets/attendance_tile.dart` (199 lines)
- Attendance record row with date badge, status icon, check-in/out times.

### `android/app/build.gradle.kts` (44 lines)
- Android build config: `com.pphl.employee_attendance`, minSdk 26, Java 17, debug signing.

### `android/app/src/main/AndroidManifest.xml` (52 lines)
- App label "PPHL Attendance", permissions for camera + location + internet, single-top launch mode.

### `pubspec.yaml` (111 lines)
- Package name `employee_attendance`, version 2.0.0+2, Dart SDK ^3.11.0, 18 production dependencies, MobileFaceNet asset.

### `assets/models/mobilefacenet.tflite` (~5.2 MB)
- Pre-trained MobileFaceNet TensorFlow Lite model. Input: 1×112×112×3 float32 (pixel values normalized to [-1,1]). Output: 1×192 float32 embedding.

---

*End of document.*
