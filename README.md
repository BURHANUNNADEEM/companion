# Companion / کمپینین

A calm, learning home screen for older parents (Urdu first, English fallback). It notices when the user is
stuck, offers one clear next step, takes them to the right screen with game-like arrows and highlights, checks
suspicious messages, and keeps family in the loop, only with the parent's consent.

**Built from `PRD.md` v0.3.** No separate `Architecture.md` was supplied, so PRD §7–§8 is the architecture spec.
Full requirement-by-requirement mapping: [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).
API reference: [`docs/API.md`](docs/API.md) (and live Swagger at `/docs`).

```
companion/
├── backend/            FastAPI + SQLAlchemy async + Alembic (Neon Postgres / SQLite)
│   ├── app/api/        routers: me, consent, events, config, suggestions, voice, navigation, scam, caregiver
│   ├── app/services/   flow_engine, intent, llm (Gemini), redaction, scam_rules, suggestions, caregiver, email, i18n
│   ├── app/flows/workflows.json   ← the ONLY navigation workflows that can ever run
│   ├── alembic/        migrations 0001 (schema) + 0002 (clerk_id → auth_id)
│   ├── scripts/seed_demo.py
│   └── tests/          79 tests incl. accuracy benchmarks and the full demo journey
├── mobile/             Flutter Android app + Kotlin Accessibility module
│   ├── lib/            screens, widgets (overlay, arrows, stars), services, l10n (en/ur)
│   ├── android/…/tier2/  CompanionAccessibilityService, SkillRunner, Denylist, OverlayController
│   ├── assets/skills/skills.json  ← Tier 2 skills (mirrors backend workflows; test-enforced)
│   └── test/           struggle rules, strings, plan validation, Tier 1 intents, widgets
└── docs/               IMPLEMENTATION_PLAN.md, API.md, openapi.json
```

## How the AI Navigation Engine stays safe

```
"بیٹے کو فون کرو" ─► rules (en / Roman Urdu / Urdu) ──no match──► Gemini (redacted text → JSON: workflow_id, slots, confidence)
                               │                                         │
                               └──────────────► Flow Engine ◄────────────┘
                     known workflow? typed slots? denylist (bank/pay/OTP/password/install)?
                     steps ONLY from workflows.json · ≤10 steps · allowed intents · sanitised text
                                        │
                     NavPlan: ordered steps · target · highlight{x,y,w,h} · arrow · hint{en,ur} · completion
                                        │
       Flutter re-validates (client allow-list) → game-like guide (stars, bouncing arrow, pulsing highlight)
       Tier 1: Android intents (dialer, WhatsApp, settings, maps…)   Tier 2 (demo build): Kotlin SkillRunner
```
The LLM never produces an action. It can only *name* one predefined workflow; the Kotlin runner additionally
re-checks the skill id, the denylist and password/OTP fields on every screen, never presses WhatsApp **Send**,
stops on any unexpected screen, and has an always-visible **Stop**.

---

## 1. Run the backend (5 minutes, no accounts needed)

Prerequisites: Python 3.11+.

```bash
cd backend
python -m venv .venv
source .venv/bin/activate            # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                 # defaults: SQLite, AUTH_MODE=dev, LLM off, console e-mail
alembic upgrade head                 # creates the tables
python -m scripts.seed_demo          # demo parent + linked caregiver + 30 days of routine
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```
Open http://localhost:8000/docs. Try it with the demo tokens:
```bash
curl -s localhost:8000/api/suggestions?hour=9 -H "Authorization: Bearer dev:demo-parent"
curl -s -X POST localhost:8000/api/navigation/plan -H "Authorization: Bearer dev:demo-parent" \
     -H "Content-Type: application/json" -d '{"utterance":"بیٹے کو فون کرو"}'
curl -s -X POST localhost:8000/api/scam/check -H "Authorization: Bearer dev:demo-parent" \
     -H "Content-Type: application/json" -d '{"text":"Your HBL account will be blocked. Share the OTP now."}'
curl -s localhost:8000/api/caregiver/summary -H "Authorization: Bearer dev:demo-caregiver"
```

### Backend tests
```bash
cd backend && source .venv/bin/activate
pytest -q          # 79 passed
pytest -q -s tests/test_scam.py tests/test_voice.py tests/test_suggestions.py   # prints accuracy numbers
```
Current results: suggestion top‑3 accuracy **95 %** on seeded data (target ≥ 60 %), scripted voice commands **100 %**
(target ≥ 80 %), scam recall **100 %** / false positives **0 %** (targets ≥ 85 % / ≤ 15 %). The scam and voice sets
are small, hand-written samples (28 scams, 24 normal messages, 34 commands), so treat these as smoke tests and
re-measure on real tester data.

## 2. Free cloud services (for a real deployment)

| Service | Steps |
|---|---|
| **Neon Postgres** (free) | Create a project at neon.tech → copy the connection string into `DATABASE_URL` (keep `?sslmode=require`; it is converted for asyncpg automatically) → `alembic upgrade head` |
| **Firebase Auth** (free) | console.firebase.google.com → add Android app `com.companion.app.demo` (and `com.companion.app` for the Play flavour) → add SHA‑1/SHA‑256 (`cd mobile/android && ./gradlew signingReport`) → enable **Phone** and **Email/Password** providers → add **test phone numbers** (no SMS billing needed) → download `google-services.json` into `mobile/android/app/` → Project settings › Service accounts › *Generate new private key* → put the path/JSON in `FIREBASE_CREDENTIALS`, set `FIREBASE_PROJECT_ID`, `AUTH_MODE=firebase` |
| **Gemini** (free tier, optional) | Key from https://aistudio.google.com/apikey → `LLM_ENABLED=true`, `GEMINI_API_KEY=…`. Free-tier prompts may be used by Google: only redacted, synthetic or consenting-tester data (disclosed on the consent screen) |
| **Gmail SMTP** (free) | Turn on 2‑step verification → create an App Password → `EMAIL_BACKEND=smtp`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM` |
| **Inactivity alerts** | Call daily: `curl -X POST https://YOUR_API/api/alerts/inactivity/run -H "X-Admin-Token: $ADMIN_TOKEN"` (cron or a scheduled GitHub Action) |

For production set `ENV=production` (the app refuses to start with `AUTH_MODE=dev` or the default `ADMIN_TOKEN`)
and serve over HTTPS (e.g. Render/Fly.io/Railway free tiers: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`).

## 3. Run the Android app

Prerequisites: Flutter **3.29+** (`flutter doctor` green for Android), an Android phone or emulator (API 23+).

```bash
cd mobile
./tool/setup_android.sh              # generates Gradle wrapper/icons/styles without touching our files, then pub get
flutter test                         # unit + widget tests
```

**Demo build without Firebase** (backend running with `AUTH_MODE=dev`):
```bash
# emulator (10.0.2.2 = your computer):
flutter run --flavor demo --dart-define=AUTH_MODE=dev --dart-define=API_BASE_URL=http://10.0.2.2:8000
# real phone on the same Wi-Fi:
flutter run --flavor demo --dart-define=AUTH_MODE=dev --dart-define=API_BASE_URL=http://<your-PC-LAN-IP>:8000
```
Sign in with user id `demo-parent` (or a new id such as `ammi`), and on a second device `demo-caregiver`.

**Real login** (Firebase configured, backend `AUTH_MODE=firebase`):
```bash
flutter run --flavor demo --dart-define=API_BASE_URL=https://your-api.example.com
```

**Builds**
```bash
flutter build apk --flavor demo --release --dart-define=API_BASE_URL=https://your-api.example.com   # sideload, includes Tier 2
flutter build appbundle --flavor play --release --dart-define=API_BASE_URL=https://your-api.example.com  # Play Store, Tier 1 only
```

**Phone setup checklist (demo)**
- Urdu voice: Settings › System › Languages › Text-to-speech › Google › install **Urdu (Pakistan)**; speech
  recognition offline pack for Urdu if available. Text is always shown, so the app works without them.
- Tier 2 tap help: in Companion › Settings › *Open Android settings* → Accessibility → **Companion tap helper** → On.
  Some phone makers (Xiaomi, Oppo, Samsung) also need "allow restricted settings" or battery-optimisation off.

## 4. Three-minute demo script (PRD §11)

1. Parent signs in, picks **"I want help using my phone"**, chooses اردو, accepts the consent screen.
2. Wander: open Settings → back → Family → back → back. Within a second the overlay dims the screen, pulses
   around **کال کریں** and says *"کیا مدد چاہیے؟"*.
3. Tap **کال کریں** → the guide shows ⭐ progress, a bouncing arrow and *"سبز 'کال کریں' بٹن دبائیں۔"* → **چلیں**
   opens the dialer with the saved son's number. (Demo build + Tier 2 on: **"میرے لیے کر دیں"** taps the call
   button after confirmation, with a red **روکیں** bar on top.)
4. Press **بولیں** and say *"وائی فائی چلاؤ"* → Wi‑Fi guide. Say *"بینک ایپ کھولو"* → politely refused.
5. **پیغام چیک کریں** → paste *"آپ کا بینک اکاؤنٹ بند کر دیا جائے گا۔ فوری طور پر اپنا کوڈ بھیجیں۔"* →
   **غالباً دھوکہ** with reason + action, read aloud → **گھر والوں کو بتائیں**.
6. Caregiver phone (`demo-caregiver`): alerts show the shared scam verdict and repeated struggle; summary shows
   counts only; send a guide card that appears on the parent's home screen.

## 5. Requirements coverage (summary)

| PRD | Where |
|---|---|
| F1 home tiles, 20sp/64dp, bigger text, Ask my family, ≤2 taps | `parent_home_screen.dart`, `big_tile.dart`, `theme.dart` |
| F2 13 action events + 5 struggle rules on device, remote threshold | `event_tracker.dart`, `struggle_detector.dart`, `/api/events`, `/api/config` |
| F3 ranked top‑3, Something else, feedback, back-off | `services/suggestions.py`, `/api/suggestions` |
| F4 overlay < 1 s, Not now, read aloud, kind wording | `guidance_overlay.dart` (cached suggestions → instant) |
| F5 Firebase auth, server-side role, consent, delete my data | `core/auth.py`, `api/me.py`, `api/consent.py`, `consent_screen.dart` |
| F6 share/paste/OCR, rules → Gemini, redaction, 3 levels, Tell my family | `scam_rules.py`, `redaction.py`, `llm.py`, `scam_check_screen.dart` |
| F7 push-to-talk ur‑PK → en, TTS, text fallback | `voice_service.dart`, `voice_sheet.dart`, `intent.py` |
| F8 Gemini via backend only, JSON-validated, rate limit, timeout, fallback | `services/llm.py` |
| F9 e-mail invites (24 h), approve, revoke, summary, alerts, guide cards | `api/caregiver.py`, `services/caregiver.py`, `caregiver_home_screen.dart` |
| F10 Tier 1 intents + Tier 2 Guide/Assist, denylist, ≤10 steps/30 s, Stop | `flow_engine.py`, `workflows.json`, `navigation_guide_screen.dart`, `navigation_service.dart`, `android/…/tier2/*` |

## 6. Decisions and known limitations (nothing skipped silently)

- **Flutter/Kotlin code was not compiled in the build environment** (Flutter SDK and pub.dev were unreachable
  there). The backend was fully run and tested; the Dart/Kotlin sources were structurally checked (brackets,
  imports, every UI string present in both languages). Run `./tool/setup_android.sh && flutter test` first; if a
  plugin version fails to resolve, run `flutter pub upgrade --major-versions`.
- "Pay a bill" (a PRD *example* tile) conflicts with the PRD non-goals (no payments/banking), so the sixth tile is
  **WhatsApp video call**.
- Caregiver alerts are **in-app** (polled every 60 s), which the PRD allows ("push or in-app"); FCM push can be
  added later without backend changes to the alert model.
- On-device OCR (ML Kit) reads Latin script only, so Urdu-script screenshots should be pasted or shared as text; the
  screen says so.
- Tier 2 skill selectors differ between phone makers: test the three skills on the demo phone (PRD §12) and add
  ids to `assets/skills/skills.json` if needed (the backend test keeps it in sync with `workflows.json`).
- Contacts never leave the phone: family numbers are entered in **Family** and resolved on the device.
- Added (documented) endpoints/event: `struggle_detected` event, `/config`, `/navigation/*`, `/caregiver/approve`,
  `/caregiver/links`, `/caregiver/alerts`, guide cards, `/scam/share`, `/me/sharing-preview`, `/me/language|profile`.

---

## اردو خلاصہ

**کمپینین** بزرگ والدین کے لیے ایک پرسکون ہوم اسکرین ہے: بڑے بٹن، اردو آواز سے مدد، اور جب صارف الجھن میں ہو تو
ایک واضح اگلا قدم۔ ایپ تیر، چمکتی روشنی اور ستاروں کے ساتھ قدم بہ قدم صحیح اسکرین تک لے جاتی ہے، مشکوک پیغامات
چیک کرتی ہے (غالباً دھوکہ / احتیاط کریں / شاید ٹھیک ہے)، اور صرف والدین کی اجازت سے گھر والوں کو خلاصہ اور اطلاعات
بھیجتی ہے۔

- **بیک اینڈ چلانے کے لیے:** اوپر حصہ 1 کی کمانڈز چلائیں (`pip install` → `alembic upgrade head` → `uvicorn`)۔
- **ایپ چلانے کے لیے:** `mobile/tool/setup_android.sh` پھر `flutter run --flavor demo --dart-define=AUTH_MODE=dev`۔
- **حفاظت:** AI صرف پہلے سے طے شدہ کاموں میں سے ایک کا نام لے سکتا ہے؛ بینک، ادائیگی، پاس ورڈ اور OTP والی
  اسکرینوں پر کوئی عمل نہیں ہوتا، اور "روکیں" بٹن ہمیشہ نظر آتا ہے۔
- **رازداری:** پیغامات کا متن، رابطے اور اسکرین کا مواد سرور پر محفوظ نہیں ہوتا؛ "میرا ڈیٹا ختم کریں" ایک ٹچ میں سب کچھ مٹا دیتا ہے۔
