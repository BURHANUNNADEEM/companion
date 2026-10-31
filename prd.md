# Companion: Product Requirements Document

**Status:** Draft v0.3  
**Platform:** Android only (Flutter + Kotlin native module), FastAPI backend, Neon Postgres, Firebase Auth, Gemini (LLM)  
**Type:** Hackathon prototype (time-boxed build, then demo and user testing)

---

## 1. Overview

Companion is a guided home screen for people who are not comfortable with technology, mainly older parents. It notices when the user is lost, works out the task they probably want, and gently guides them there with a highlighted overlay, and can take them straight to the right screen across the phone. It also offers voice help in Urdu and a "check this message" scam helper. A linked family member (caregiver) can see a privacy-respecting summary and receive alerts, so they get fewer "I'm stuck" phone calls.

### One-line pitch
A calm, learning home screen that notices when you're stuck, offers the next step, and quietly keeps your family in the loop, with your consent.

## 2. Problem

People who grew up with technology find it automatic. Their parents often do not:

- They get stuck on things others find trivial: apps that log out, video calls that fail, confusing forms.
- They fear breaking something or looking foolish, so they avoid tools that would help them.
- They are targets for scam messages that look real.
- Every problem becomes a phone call to a family member.

## 3. Goals and non-goals

### Goals
1. Reduce the time and taps a parent needs to finish a basic task.
2. Detect confusion early and offer one clear next step, without being annoying.
3. Help parents recognize scam messages and know what to do.
4. Give caregivers just enough visibility to help, with the parent's explicit consent.
5. Keep sensitive content (messages, contacts) off our servers by default.
6. Take the user to the right place across the phone, and with their permission help with the taps, instead of only describing where to go.

### Non-goals (this version)
- Open-ended autonomous agents that plan their own actions in any app. Navigation uses predefined, user-confirmed flows (F10).
- Operating banking, payment or other sensitive apps.
- Automatic scanning of SMS or notifications.
- iOS (the product is Android only), payments, or any financial transactions.
- Medical, legal or financial advice.
- Replacing a bank's or government's own security tools.

## 4. Users

| Persona | Description | Needs |
|---|---|---|
| **Parent (primary)** | 55+, uses a smartphone for calls, messages, photos. Anxious about mistakes. | Big, simple screens. Reassurance. Help in their language. Voice instead of typing. |
| **Caregiver (secondary)** | Adult child or relative, comfortable with technology. | Know when the parent is struggling or targeted by a scam, without spying. Fewer emergency calls. |

## 5. Scope

All items below are in scope for the product. Priority tells the build order for the time-boxed prototype.

| # | Feature | Priority |
|---|---|---|
| F1 | Guided home screen (large task tiles) | P0 |
| F2 | Behavior tracking and struggle detection (on-device) | P0 |
| F3 | Task suggestion engine | P0 |
| F4 | Guidance overlay (coach marks) | P0 |
| F5 | Authentication and consent | P0 |
| F6 | Scam check | P1 |
| F7 | Voice assistant | P1 |
| F8 | LLM layer (explanations, free-text help) | P1 |
| F9 | Caregiver dashboard and alerts | P2 |
| F10 | Navigation assistant (Tier 1 intents, Tier 2 accessibility) | P0 (Tier 1), P1 (Tier 2) |

P0 is the demonstrable core loop. P1 and P2 are specified here and built in order as time allows.

---

## 6. Functional requirements

### F1. Guided home screen
- Shows 4 to 6 large tiles (e.g. Call, Messages, Photos, Pay a bill, Check a message, Ask for help).
- Minimum font size 20sp, minimum tap target 56dp, high contrast, a "bigger text" toggle.
- Tiles open the real action (dialer via `tel:`, messaging app, gallery) and then log `task_completed`.
- A persistent **Ask my family** button calls or messages the saved helper.

**Acceptance:** a first-time user can reach any tile's action in at most 2 taps from the home screen.

### F2. Behavior tracking and struggle detection
Events logged (actions only, never content): `screen_view`, `tap`, `back`, `idle`, `task_started`, `task_completed`, `suggestion_shown`, `suggestion_accepted`, `suggestion_dismissed`, `something_else_tapped`, `nav_started`, `nav_completed`, `nav_aborted`. Each carries `session_id` and a timestamp.

Struggle signals, computed **on the device**:

| Signal | Example rule |
|---|---|
| Backtracking | 3 or more back actions within 20 seconds |
| Idle hesitation | 10 or more seconds on a screen without a tap |
| Repeated taps | Same target tapped 3 or more times in 5 seconds |
| Looping | Same 2 to 3 screens visited repeatedly |
| No completion | 45 or more seconds of navigation without completing a task |

A weighted score above a configurable threshold triggers a suggestion. Only summaries and outcomes are sent to the backend.

**Acceptance:** each rule can be triggered in a scripted test, and the threshold is adjustable without a code change (remote or settings value).

### F3. Task suggestion engine
- Backend endpoint returns the top 1 to 3 likely tasks.
- Ranking combines: what the user did after the last task (sequence counts), what they usually do at this time of day, and defaults for new users.
- Always offers **Something else**. Suggestions are never executed automatically.
- Accept, dismiss and "something else" outcomes feed back into ranking.
- Backs off after 3 consecutive dismissals.

**Acceptance:** top-3 contains the task the user actually completes next in at least 60% of cases on seeded demo data. A new user always gets a sensible default list.

### F4. Guidance overlay
- Dimmed screen with a pulsing highlight around the suggested tile and one short sentence ("Tap here to call Ali").
- Large text, optional read-aloud (F7), always visible **Not now** button.
- Non-judgmental wording ("Need a hand?"). Never "you seem confused".
- Inside Companion the overlay is a normal Flutter overlay. Over other apps (F10 Tier 2) it is drawn by the Android service.

**Acceptance:** overlay appears within 1 second of the struggle trigger and can be dismissed in one tap.

### F5. Authentication and consent
- **Provider: Firebase Authentication** (decided). Login by phone-number OTP or email. The Flutter app signs in with `firebase_auth`, sends the Firebase ID token as a Bearer header, and the backend verifies it and reads the stable user id (`uid`).
- **Role selection after login:** on first sign-in the user chooses **Parent** or **Caregiver** on a plain confirmation screen. The role is stored in `users.role` on the backend (never trusted from the client afterwards) and decides which home screen they see. Changing role means deleting and recreating the account.
- Setup gotchas: add the app's SHA-1/SHA-256 fingerprints in the Firebase console, and enable the phone provider. Real SMS delivery may need a billing plan, so for the demo use Firebase test phone numbers and keep email login as a fallback.
- First launch shows a plain-language **consent screen** covering: activity tracking (on by default only after they accept), caregiver sharing (off by default), whether scam-check text may be stored (off by default), and a plain note that redacted text is sent to an AI service to help check messages.
- Settings include **Delete my data**, which removes events, scam history, links and the account.

**Acceptance:** nothing is logged before consent. Deleting data leaves no rows for that user in any table.

### F6. Scam check
**Input paths:** share a message into the app (Android share sheet), paste text, or pick a screenshot (OCR on device).

**Pipeline:**
1. Rule engine flags known patterns: requests for OTP, PIN or password, urgency or threats, prize or lottery claims, requests for payment or gift cards, links whose domain does not match the claimed sender, impersonation of banks or government.
2. If the rules are inconclusive, the LLM (F8) classifies the redacted text.
3. Result is shown as **Likely scam / Be careful / Probably fine**, with one plain-language reason and a recommended action ("Do not share the code. Banks never ask for it. Call your bank using the number on your card.").

**Rules for honesty and safety:**
- Never claims certainty. Always includes "When in doubt, ask your family."
- Redacts phone numbers, account numbers and names before any LLM call.
- Stores only verdict, score and reasons by default, not the message text.
- Offers **Tell my family** to send the verdict (not the content) to the caregiver.

**Acceptance:** at least 85% recall on a labelled sample of scam messages and at most 15% false-positive rate on normal messages (target; measured on a small test set).

### F7. Voice assistant
- Push-to-talk **Speak** button on the home screen and in the overlay.
- Speech-to-text (on-device where available) maps phrases to supported tasks ("call my son", "show my photos"). Unmatched requests go to the LLM for intent parsing (F8).
- Text-to-speech reads overlay prompts and scam verdicts aloud on request.
- **Language: Urdu first** (speech recognition locale `ur-PK`, English as fallback). UI strings, overlay text, scam explanations and voice prompts are provided in Urdu with right-to-left layout.
- Urdu text-to-speech voices vary by device, so test on the demo phone (the Urdu voice pack may need installing). Text is always shown alongside audio.

**Acceptance:** at least 80% of scripted supported commands are mapped to the right task in a quiet room. Voice always has a visible text fallback.

### F8. LLM layer
- **Model: Gemini via the Gemini API** (free tier for the hackathon prototype). All LLM calls go through the backend. API keys never ship in the app.
- Uses: (a) scam classification and explanation (F6), (b) free-text or voice intent to supported task (F7), (c) rewriting explanations in simple language and the user's language.
- Output is constrained JSON (`task`, `confidence`, `explanation`) and validated server-side. Low confidence falls back to showing the task list.
- Rate limits per user, request timeouts, and a rule-based fallback when the LLM is unavailable.
- Redaction before every call. We do not store message text by default.
- **Free-tier caveat:** Google states that on the Gemini API free tier, prompts and responses may be used to improve its products, while paid-tier content is not. So during the hackathon: send only redacted text, demo with synthetic or consenting-tester messages, disclose this on the consent screen, and move to the paid tier before any real-user launch.
- The free tier is also rate-limited, so the rule-based fallback must be able to carry the demo if the quota is hit.

**Acceptance:** the app stays fully usable with the LLM disabled. Median added latency under 3 seconds.

### F9. Caregiver dashboard and alerts
- A parent links a caregiver by **emailed invite**: the parent enters the caregiver's email, the backend sends a one-time link or code over SMTP (for example a Gmail app password or a transactional email service), and the caregiver accepts after signing in with the Caregiver role. The parent approves the link, invite codes expire after 24 hours, and links can be revoked at any time.
- Caregiver sees: last active time, tasks completed per day, struggle episodes per day, scam checks count and verdicts, and which tasks cause the most friction.
- Caregiver does **not** see: message text, contact names, call logs, screenshots, or screen content.
- Alerts (push or in-app): repeated struggle on the same task, a "Likely scam" verdict the parent chose to share, no activity for a chosen number of days.
- Caregiver can send a short guide card or message ("Tap Photos, then the plus sign").
- Delivered as a caregiver mode inside the same Flutter app (role chosen after login), using the same backend.

**Acceptance:** with sharing off, the caregiver sees nothing. Revoking removes access immediately.

### F10. Navigation assistant (take the user there, and help with the taps)
The user says or taps what they want ("call Ali", "turn on Wi-Fi", "send a message to my son"). Companion takes them to the right place and, where allowed, helps with the taps.

**Tier 1: Intent navigation (Play-safe, default).** Standard Android intents and deep links jump straight to the right screen: the dialer with the saved contact's number, a WhatsApp chat via deep link, Wi-Fi, Bluetooth, sound and display settings screens, the camera, maps with a destination, and the share sheet. A short Urdu hint can be shown on arrival. Needs no special permission beyond optional contacts access.

**Tier 2: Guided and assisted taps (Accessibility Service, Kotlin).** Optional and off by default. The user enables it in Android settings after a plain-language explanation. Two modes:
- **Guide:** highlights the next button in another app and the user taps it.
- **Assist:** after the user confirms the goal ("Do it for me"), Companion performs the next tap.

Rules for Tier 2:
- Supported flows are predefined **skills** (ordered steps matched by text or id, with fallbacks), not open-ended planning. Examples: call a saved contact, open a WhatsApp chat with a saved contact (the user presses Send), turn on Wi-Fi.
- Every Assist run needs explicit confirmation, shows a "Companion is helping" indicator, and has an always-visible **Stop** button.
- Denylist: banking and payment apps, password managers, password or OTP fields, security settings, app installs and purchases. Companion takes no action on these screens.
- Never stores or transmits text from other apps. Matching happens on the device. Only outcome events (`nav_started`, `nav_completed`, `nav_aborted` with the skill id) go to the backend.
- On any unexpected screen it stops and falls back to Guide or Tier 1. Limits: at most 10 steps and 30 seconds per run.
- Optionally reuses F2 signals across apps using only counts (back presses, window changes) and package names, never screen text.

**Acceptance:** Tier 1 flows complete in 1 tap from a home tile. A Tier 2 demo skill succeeds 3 runs in a row on the demo phone, Stop aborts within 1 second, and a denylisted app triggers no actions.

**Compliance note:** Google Play prohibits Accessibility API use that lets an app autonomously initiate, plan and execute actions, and does not treat assistants or automation tools as accessibility tools. Android 17's Advanced Protection Mode can also block accessibility access for apps that are not verified accessibility tools. So Tier 2 is a sideloaded prototype and demo feature, while Tier 1 is the version that can be published.

---

## 7. Architecture

```
Flutter app (Android)
 ├─ UI: home tiles, overlay, scam check, voice, caregiver mode
 ├─ On-device: event buffer, struggle detector, OCR, speech-to-text
 ├─ ApiClient (adds Firebase ID token)
 └─ Kotlin module (F10 Tier 2): AccessibilityService, overlay, skill runner, via platform channels
        │ HTTPS
FastAPI backend
 ├─ Firebase ID token verification (token -> uid -> user + role)
 ├─ /events, /suggestions, /scam, /voice-intent, /caregiver, /consent
 ├─ Services: suggestions, scam rules, LLM gateway to Gemini (redaction, JSON validation)
 ├─ Email invites over SMTP
 └─ Neon Postgres (SQLAlchemy async + Alembic)
```

### Auth migration note
The current `users.clerk_id` column becomes a provider-neutral `auth_id` (it will hold the Firebase `uid`). Only `core/auth.py` changes: it verifies the Firebase ID token (for example with `firebase-admin`, using a service account kept in environment variables). Rename the column with an Alembic migration, add a `role` column, and keep `get_current_user` as is.

### Data model (additions)
| Table | Key fields |
|---|---|
| `users` | id, auth_id (unique), role, language, created_at |
| `consents` | user_id, type, granted, timestamp |
| `events` | existing (user_id, event_type, item_id, properties, created_at) |
| `caregiver_links` | id, parent_id, caregiver_id, status (pending/active/revoked), invite_code, permissions |
| `scam_checks` | id, user_id, verdict, score, reasons, source, created_at (no raw text by default) |
| `alerts` | id, parent_id, caregiver_id, type, payload, created_at, seen_at |

### API (draft)
| Endpoint | Purpose |
|---|---|
| `GET /api/me` | Current user |
| `POST /api/events` | Batch event upload |
| `GET /api/suggestions` | Ranked tasks for context (hour, last task) |
| `POST /api/scam/check` | Verdict for submitted text |
| `POST /api/voice/intent` | Map a transcript to a supported task |
| `POST /api/caregiver/invite`, `POST /api/caregiver/accept`, `DELETE /api/caregiver/link/{id}` | Link management |
| `GET /api/caregiver/summary` | Aggregated stats for linked parents |
| `PUT /api/consent` | Update consent choices |
| `DELETE /api/me/data` | Delete all user data |

## 8. Platform decision: Android only, Flutter plus a Kotlin module

**Decision:** Android only. Flutter for the UI and most logic, plus a **Kotlin native module** for the Accessibility Service and the overlay window over other apps, connected through platform channels (MethodChannel for commands, EventChannel for events). A full Kotlin rewrite is not needed.

| Area | Where it lives |
|---|---|
| Home screen, caregiver UI, API calls, voice, scam check, suggestions | Flutter |
| Tier 1 intent navigation (dialer, WhatsApp, settings, maps) | Flutter (`url_launcher`, `android_intent_plus`) |
| Tier 2: Accessibility Service, reading UI nodes, performing taps, overlay over other apps | Kotlin |
| Skill definitions | JSON, shipped with the app, run by the Kotlin skill runner |

iOS has no equivalent of these capabilities, so cross-platform is not a goal.

## 9. Privacy, safety and compliance

- **Data minimization:** log actions, not content. No contact names, numbers or message text in events.
- **Consent first:** nothing tracked before consent. Caregiver sharing is opt-in and revocable.
- **On-device first:** struggle scoring, OCR and Tier 2 screen matching happen on the phone.
- **Accessibility Service rules:** off by default, explained in plain language before sending the user to Android settings, a persistent notification while active, a denylist of sensitive apps and fields, no storage or transmission of text from other apps, and an always-visible Stop.
- **LLM hygiene:** redact before sending, server-side calls only, no raw text stored, timeouts and fallbacks. The Gemini free tier may use content to improve Google's products, so it is for prototype and synthetic data only; use the paid tier for real users.
- **Right to delete:** one tap deletes everything for the user.
- **Transport and storage:** HTTPS in any non-local environment, secrets in environment variables, least-privilege database access.
- **Play Store:** a published build would use Tier 1 only (no Accessibility Service, no SMS or call-log permissions) with an accurate data-safety form. Tier 2 stays in a sideloaded demo build.
- **Wording:** the app gives guidance, not guarantees, especially for scam checks.
- **Testing ethics:** only consenting participants, no real accounts or real banking information during tests.

## 10. Success metrics

| Metric | Target (prototype) |
|---|---|
| Time to complete a task, with vs without guidance | At least 30% faster |
| Taps to complete a task | At least 25% fewer |
| Suggestion acceptance rate | 50% or higher |
| Top-3 suggestion accuracy | 60% or higher |
| Scam check recall / false positives | 85% / 15% or lower |
| Caregiver "stuck" phone calls (self-reported, small pilot) | Fewer than before |
| Satisfaction (1 to 5, 5 to 8 testers) | 4 or higher |

## 11. Milestones

**Time-boxed prototype (about 5 hours)**
1. Hour 1: switch auth, home tiles, `ApiClient`, event logging.
2. Hour 2: struggle detector.
3. Hour 3: overlay and `/api/suggestions`.
4. Hour 4: consent screen, delete-my-data, feedback events, seeded demo data.
5. Hour 5: test with 2 to 3 people, record metrics.

**Next, in order:** scam check (rules first, then Gemini), Urdu voice, LLM intent parsing, caregiver invite and dashboard.

**Navigation:** build Tier 1 intent flows (call, WhatsApp chat, Wi-Fi settings) in hour 3 alongside the overlay. Build one Tier 2 skill only after the core loop works.

**Hackathon demo flow (about 3 minutes):** parent signs in and picks a role, wanders between screens, the overlay suggests "Call", the parent taps it and Companion jumps straight to the dialer with the contact ready (Tier 2: it also guides the taps in another app), the parent pastes a scam message and gets an Urdu verdict, and the linked caregiver's phone shows the struggle and scam alert.

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Suggestions feel intrusive or wrong | Offer choices, never auto-act, back off after dismissals, always show "Something else" |
| Too little data for prediction | Defaults, time-of-day counts, seeded demo data, clearly disclosed |
| Scam verdict is wrong | Three-level verdict, hedged wording, "ask family" advice, measured accuracy |
| LLM quota, latency or outage (Gemini free tier is rate-limited) | Rule-based fallback, caching, rate limits |
| Free-tier prompts may be used by Google to improve its products | Redact text, demo with synthetic or consenting-tester messages, disclose in consent, use the paid tier before a real launch |
| Caregiver feature feels like surveillance | Opt-in, minimal data, revocable, parent sees exactly what is shared |
| Auth setup friction (Firebase fingerprints, phone OTP) | Use test phone numbers and email login for the demo, only `core/auth.py` changes |
| Accessibility policy: Play bans autonomous actions, Android 17 Advanced Protection can block non-accessibility tools | Tier 1 for any published build, Tier 2 sideloaded for the demo only, predefined skills confirmed by the user |
| Banking and sensitive apps hide content or block taps | Denylist them, fall back to Tier 1 or Guide mode |
| Phone makers add extra permission screens or stop background services | Test on the demo phone, keep a setup checklist |
| Skills break when other apps change their screens | Match by several selectors, fall back to Guide, keep the skill set small |
| Scope too large for the time | Strict P0 first, P1 and P2 only after the core loop works |

## 13. Decisions and open questions

### Decided
1. Language: Urdu first (English fallback).
2. Auth: Firebase Authentication.
3. Roles: the user picks Parent or Caregiver after login. Caregiver is a mode in the same app, linked by an emailed invite sent over SMTP.
4. LLM: Gemini API, free tier for the prototype.
5. Context: hackathon, so a polished demo of the core loop matters more than breadth.
6. Platform: Android only, Flutter plus a Kotlin module.
7. Navigation: intent-based navigation first (Play-safe), with the Accessibility Service tier as a sideloaded demo feature.

### Still open
1. Which Gemini model (a Flash or Flash-Lite model is the natural free-tier choice), and does the quota hold for a live demo?
2. SMTP sender: a Gmail account with an app password, or a transactional email service?
3. Which scripted scenario is shown to the judges?
4. Will the app be published on Google Play after the hackathon? If yes, Tier 2 must be dropped or go through Google's accessibility declaration review.
