# Companion — Implementation Plan / عملدرآمد کا منصوبہ

Source of truth: `PRD.md` v0.3 (§7 Architecture and §8 Platform decision are used as the
architecture spec; no separate `Architecture.md` was supplied).

Bilingual requirement: **every user-facing string exists in English and Urdu** (Urdu uses
right-to-left layout). Language is chosen at onboarding, stored in `users.language`, switchable in
Settings, and sent with every AI request so explanations come back in the same language.

## 1. Repository layout

```
companion/
├── backend/                 FastAPI + SQLAlchemy async + Alembic (Neon Postgres)
│   ├── app/core/            config, db, Firebase auth, rate limiting
│   ├── app/api/             one router per PRD endpoint group
│   ├── app/services/        suggestions, scam rules, redaction, Gemini gateway,
│   │                        intent parser, navigation flow engine, caregiver, alerts, email
│   ├── app/flows/           workflows.json — the ONLY navigation actions that can ever run
│   ├── alembic/             migrations (0001 initial schema)
│   ├── scripts/seed_demo.py seeded demo data (PRD F3 / §12)
│   └── tests/               pytest: unit + full user journey + accuracy benchmarks
├── mobile/                  Flutter Android app + Kotlin native module
│   ├── lib/                 UI, l10n (en/ur), api client, struggle detector, voice, overlay
│   ├── android/…/kotlin/    AccessibilityService, skill runner, overlay window, denylist
│   ├── assets/skills/       Tier 2 skill JSON (mirrors backend workflows)
│   └── test/                unit + widget tests
└── docs/                    this plan, API.md
```

## 2. Requirement → module map

| PRD | Requirement | Backend | Flutter / Kotlin | Test |
|---|---|---|---|---|
| F1 | 4–6 large tiles, 20sp/56dp, bigger-text toggle, Ask my family | — | `screens/parent_home_screen.dart`, `widgets/big_tile.dart`, `theme.dart` | `widget_test.dart` |
| F1 | Tile opens real action, logs `task_completed`, ≤2 taps | `/api/events` | `services/navigation_service.dart` (Tier 1) | widget test |
| F2 | 13 action-only event types with session_id + ts | `api/events.py` (allow-list, content keys rejected) | `services/event_tracker.dart` (buffer, batch upload) | `test_events.py` |
| F2 | 5 struggle signals, weighted score, on-device | config served by `/api/config` | `services/struggle_detector.dart` | `struggle_detector_test.dart` (each rule scripted) |
| F2 | Threshold adjustable without code change | `STRUGGLE_*` env → `/api/config` | fetched at start, overrides defaults | `test_config.py` |
| F3 | Top 1–3, sequence + time-of-day + defaults, Something else, backoff after 3 dismissals | `services/suggestions.py`, `/api/suggestions` | overlay | `test_suggestions.py` (≥60% top-3 on seeded data) |
| F4 | Dimmed overlay, pulsing highlight, one sentence, Not now, read-aloud, kind wording | — | `widgets/guidance_overlay.dart` | widget test |
| F5 | Firebase auth, Bearer token, role chosen once, server-trusted | `core/auth.py`, `/api/me/role` | `services/auth_service.dart`, `role_screen.dart` | `test_auth.py` |
| F5 | Consent screen (tracking, caregiver sharing, scam-text storage, AI disclosure); nothing logged before consent | `api/consent.py`, events gate | `consent_screen.dart` | `test_consent.py` |
| F5 | Delete my data → zero rows | `DELETE /api/me/data` | Settings | `test_delete.py` |
| F6 | Share sheet / paste / screenshot OCR | `/api/scam/check` | `scam_check_screen.dart`, ML Kit OCR, share intent | — |
| F6 | Rules → Gemini fallback, 3-level verdict, hedged, redaction, store verdict only, Tell my family | `services/scam_rules.py`, `redaction.py`, `llm.py` | result card | `test_scam.py` (recall ≥85%, FPR ≤15%) |
| F7 | Push-to-talk, ur-PK first, en fallback, TTS, text fallback | `/api/voice/intent` | `services/voice_service.dart` (speech_to_text, flutter_tts — free, on-device) | `test_voice.py` (≥80%) |
| F8 | Gemini via backend only, JSON validated, timeouts, rate limit, rule fallback, redaction | `services/llm.py`, `core/ratelimit.py` | — | `test_llm.py` (LLM disabled path) |
| F9 | Email invite (SMTP), 24h expiry, parent approve, revoke | `api/caregiver.py`, `services/email.py` | `caregiver_*` screens | `test_caregiver.py` |
| F9 | Summary without content; nothing when sharing off | `services/caregiver.py` | `caregiver_home_screen.dart` | test |
| F9 | Alerts: repeated struggle, shared scam, inactivity; guide cards | `services/alerts.py`, `/api/caregiver/alerts`, `/guide-cards` | alert list, guide card | test |
| F10 | **AI Navigation Engine**: LLM interprets → Flow Engine validates against predefined workflows → ordered steps, targets, highlights, hints, completion | `services/intent.py`, `services/flow_engine.py`, `flows/workflows.json`, `/api/navigation/plan` | `screens/navigation_guide_screen.dart`, `widgets/nav_arrow.dart` | `test_navigation.py` |
| F10 | Tier 1 intents (dialer, WhatsApp, Wi-Fi/BT/sound/display, camera, maps, share) | workflow `tier1` action | `navigation_service.dart` | — |
| F10 | Tier 2 Guide/Assist, confirmation, Stop, denylist, ≤10 steps/30s, no text leaves device | denylist duplicated server-side | `CompanionAccessibilityService.kt`, `SkillRunner.kt`, `Denylist.kt` | Kotlin logic mirrored in Dart test |

## 3. Navigation Engine safety design (core feature)

```
utterance ──► Intent Parser ──► (rules match?) ──yes──► IntentResult
                   │ no
                   ▼
            Gemini (redacted text, JSON schema: workflow_id, slots, confidence, explanation)
                   │
                   ▼
   ┌─────────── Flow Engine (deterministic) ────────────┐
   │ 1. workflow_id ∈ workflows.json?   else → reject   │
   │ 2. slots validated (type, length, allowed values)  │
   │ 3. denylist (banking/payment/OTP/security/install) │
   │ 4. steps built ONLY from the workflow template     │
   │ 5. ≤10 steps, timeout 30s, completion conditions   │
   │ 6. LLM explanation sanitised (no URLs/numbers/…)   │
   └────────────────────────────────────────────────────┘
                   │
                   ▼
   NavigationPlan { steps[ screen, target, highlight{x,y,w,h}, arrow, hint{en,ur},
                    completion, action(tier1 intent | tier2 skill step) ] }
```

The LLM never produces an action. It can only *name* a workflow and fill typed slots; anything else
is discarded. The Kotlin skill runner only accepts skill ids bundled in the APK and re-checks the
denylist on every accessibility event.

## 4. Build order (follows PRD §11)
1. Backend core: config, db, auth, models, migration, `/api/me`, `/api/events`, `/api/consent`.
2. Suggestions + config + delete-my-data + seed data.
3. Navigation engine (workflows + flow engine + intent parser) — P0 Tier 1.
4. Scam check (rules → Gemini), voice intent, LLM gateway.
5. Caregiver invites, summary, alerts, guide cards.
6. Flutter: l10n, auth/role/consent, home tiles, event tracker, struggle detector, overlay.
7. Flutter: navigation guide UI, voice, scam check, caregiver mode, settings.
8. Kotlin Tier 2 module.
9. Tests, docs, demo script.

## 5. Free tooling choices
| Need | Choice | Cost |
|---|---|---|
| DB | Neon Postgres free tier | free |
| Auth | Firebase Auth (email + test phone numbers) | free tier |
| LLM | Gemini Flash-Lite via REST (`gemini-2.0-flash-lite`, configurable) | free tier, optional |
| STT | Android on-device recognizer via `speech_to_text` (ur-PK / en-US) | free |
| TTS | Android TTS via `flutter_tts` | free |
| OCR | Google ML Kit text recognition (on-device) | free |
| Email | SMTP (Gmail app password) or console backend in dev | free |

## 6. Deviations / additions (documented, not silent)
- Added event type `struggle_detected` (properties: score, signal names, screen — no content) so the
  caregiver summary can count struggle episodes per day (F9). It is sent only after consent.
- Added `GET /api/config`, `POST /api/navigation/plan`, `POST /api/caregiver/approve/{id}`,
  `GET /api/caregiver/links`, `GET /api/caregiver/alerts`, `POST /api/caregiver/guide-cards`,
  `GET /api/guide-cards`, `POST /api/scam/share/{id}`, `PUT /api/me/role`, `PUT /api/me/language`,
  `POST /api/alerts/inactivity/run` — all needed to satisfy PRD behaviour.
- `AUTH_MODE=dev` accepts `dev:<uid>` tokens **only when `ENV=development`**, so the stack can be
  demoed and tested without Firebase credentials. Production refuses to start in dev mode.

## 7. Status
All modules above are implemented. Backend: 79 passing tests (`cd backend && pytest -q`), including the full PRD §11
demo journey, Alembic-vs-model check, accuracy benchmarks (suggestions 95 % top-3, voice 100 %, scam recall 100 % /
FPR 0 % on the bundled samples) and the Tier 2 skills ↔ workflows mirror check. Flutter tests live in `mobile/test/`
(run with `flutter test`). Struggle defaults were tuned so a single strong signal (3 backs, repeated taps) triggers
help while idle alone does not: threshold 0.8, weights backtracking 0.8 / repeated taps 0.8 / looping 0.6 / idle 0.5 /
no completion 0.4 — all adjustable via env vars served by `/api/config`.
