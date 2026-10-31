# Companion Backend API

Base URL (local): `http://<your-PC-LAN-IP>:8000`. Interactive docs: **`/docs`** (Swagger).

## Authentication
Every `/api/*` route needs:
```
Authorization: Bearer <Firebase ID token>
```
The user row is created automatically on first call (single user type, no roles).
**Local testing only:** with `DEV_AUTH_ENABLED=true`, `Authorization: Bearer dev-alice` works without Firebase. Never enable this in production.

`/health` and `/health/db` need no auth.

## Errors (all endpoints)
```json
{"error": {"code": "consent_required", "message": "Activity tracking consent has not been given", "details": {...}}}
```
| HTTP | code | When |
|---|---|---|
| 401 | `unauthorized` | Missing, invalid or expired token |
| 403 | `consent_required` | Tracking endpoints called before `PUT /api/consent {"tracking": true}` |
| 404 | `unknown_workflow`, `attempt_not_found`, `not_found` | Not in the allowlist, or not yours |
| 409 | `attempt_closed` | Completing an attempt twice |
| 422 | `validation_error`, `invalid_phone`, `phone_required` | Bad input |
| 503 | `database_error` | DB unreachable (Neon waking up): retry |

Workflow / task ids (allowlist): `call_family`, `whatsapp_video` (practice), `scam_check`, `wifi_settings`, `open_camera`.
Help levels: `none` → `nudge` → `highlight` → `full`.

---

## 1. Profile
### `GET /api/me`
```json
{"id": 1, "firebase_uid": "abc", "display_name": "Ammi", "language": "ur", "created_at": "2026-10-31T08:30:00+00:00", "consent_given": true}
```
### `PATCH /api/me`
Request `{"display_name": "Ammi", "language": "ur"}` (`language`: `ur` | `en`). Response: the profile, without `consent_given`.

### `DELETE /api/me/data`
Request `{"confirm": "DELETE"}`. Deletes events, scam checks, task attempts, progress, consent and the user row.
```json
{"deleted": true, "rows_deleted": {"events": 12, "scam_checks": 1, "task_attempts": 3, "task_progress": 1, "consents": 1, "users": 1}}
```

## 2. Consent
### `GET /api/consent`  ·  `PUT /api/consent`
PUT accepts any subset: `{"tracking": true, "ai_processing": false, "store_scam_text": false}`
```json
{"tracking": true, "ai_processing": false, "store_scam_text": false, "updated_at": "...", "notes_en": {"tracking": "...", "ai_processing": "...", "store_scam_text": "..."}}
```
- `tracking`: required for events, struggle evaluation and suggestion feedback.
- `ai_processing`: allows **redacted** text to go to Gemini (scam fallback, voice fallback).
- `store_scam_text`: keeps a redacted copy of checked messages. Off by default.

## 3. Activity events
### `POST /api/events` → 201  (unchanged path from before; now requires tracking consent)
```json
{"event_type": "tap", "item_id": "tile_call", "properties": {"screen": "home"}, "occurred_at": "2026-10-31T09:00:00Z"}
```
### `POST /api/events/batch` → 201 (1–500 events)
```json
{"session_id": "s-123", "events": [{"event_type": "screen_view", "item_id": "home"}, {"event_type": "back"}]}
```
Response `{"ok": true, "accepted": 2}`. Property keys that could hold personal content (`text`, `message`, `name`, `phone`, `transcript`, `otp`, …) are **dropped on the server**.

## 4. Struggle detection and suggestions
### `GET /api/struggle/config`
Thresholds for on-device detection (tunable via env vars, no code change).
```json
{"backtrack_count": 3, "idle_min_seconds": 8, "idle_max_seconds": 20, "idle_pace_multiplier": 2.5, "trigger_threshold": 1.0, "weights": {"idle": 1.0, "looping": 0.7, "...": 0}, "ladder": {"clean_for_highlight": 1, "clean_for_none": 3, "clean_for_mastery": 3}}
```
### `POST /api/struggle/evaluate`
Send counters for the current window only (no content):
```json
{"task_id": "call_family", "attempt_id": 7, "step_index": 1, "current_help_level": "none",
 "back_count": 0, "idle_seconds": 4, "max_same_target_taps": 1, "wrong_taps": 2,
 "max_screen_visits": 1, "distinct_screens": 1, "seconds_without_completion": 12, "median_step_ms": 3000}
```
In a task, the response raises help by one level:
```json
{"score": 1.0, "signals": ["wrong_taps"], "triggered": true, "idle_threshold_seconds": 8.0, "threshold": 1.0,
 "action": "raise_help", "new_help_level": "nudge", "suggestions": null, "message_ur": "کیا میں مدد کروں؟", "message_en": "Need a hand?"}
```
With no `task_id` (lost on the home screen), the response is `"action": "show_suggestions"` and `suggestions` holds the object from `GET /api/suggestions`. Idle is judged against the user's own pace (`median_step_ms` × 2.5, clamped to 8–20 s; 20 s when no task is active).

### `GET /api/suggestions?hour=14&last_task=scam_check`
```json
{"suggestions": [{"task_id": "whatsapp_video", "score": 2.4, "title_ur": "واٹس ایپ ویڈیو کال", "title_en": "WhatsApp video call"}],
 "backoff": false, "always_offer_something_else": true, "prompt_ur": "کیا میں مدد کروں؟", "prompt_en": "Need a hand?"}
```
Based on what the user usually does next, at this time of day, and overall. After 3 dismissals in a row it returns `"backoff": true` with an empty list for 10 minutes.

### `POST /api/suggestions/feedback` → 201
`{"task_id": "call_family", "outcome": "accepted" | "dismissed" | "something_else"}`

## 5. Scam check
### `POST /api/scam/check`
`{"text": "Mubarak ho! ... bisp-gov.xyz/claim", "source": "paste" | "share" | "ocr" | "voice"}`
```json
{"check_id": 5, "verdict": "likely_scam", "label_ur": "یہ دھوکہ لگتا ہے", "label_en": "Likely scam", "score": 8,
 "reasons": [{"rule_id": "asks_money", "weight": 3, "reason_ur": "...", "reason_en": "It asks you to pay money or a fee."},
             {"rule_id": "link_mismatch", "weight": 3, "reason_ur": "...", "reason_en": "..."}],
 "action_ur": "...", "action_en": "Do not send money. Real aid or prizes never need a fee.",
 "lesson_ur": "...", "lesson_en": "If you must pay to receive money, it is a scam.",
 "ask_family_ur": "شک ہو تو اپنے گھر والوں سے پوچھ لیں۔", "ask_family_en": "When in doubt, ask your family.",
 "spoken_ur": "... (one string for text-to-speech)", "source": "rules", "ai_used": false, "text_stored": false}
```
Pipeline: rules first (English, Roman Urdu, Urdu). Gemini is called **only** if the rules are inconclusive **and** `ai_processing` consent is on, with **redacted** text. Gemini can raise the warning level but never lower it. `verdict`: `likely_scam` | `be_careful` | `probably_fine`.

### `GET /api/scam/history?limit=20`
```json
{"counts": {"likely_scam": 3, "be_careful": 1, "probably_fine": 2}, "items": [{"id": 5, "verdict": "likely_scam", "score": 8, "reasons": [{"rule_id": "asks_money", "weight": 3}], "source": "rules", "created_at": "..."}]}
```

## 6. Voice intent
### `POST /api/voice/intent`
`{"transcript": "Ali ko call karo", "language": "auto"}`
```json
{"task_id": "call_family", "confidence": 0.9, "source": "keywords", "title_ur": "فون کرنا", "title_en": "Make a call",
 "explanation_ur": "آپ فون کرنا چاہتی ہیں؟", "requires_confirmation": true, "fallback_options": null}
```
No match: `"task_id": null` and `fallback_options` lists all tasks. Keyword matching runs first. Gemini, only with AI consent, can pick **only** from the allowlist. `requires_confirmation` is always true: the app must ask the user before starting anything. The transcript is never stored.

## 7. Navigation workflows (predefined, allowlisted)
### `GET /api/workflows`
```json
{"workflows": [{"id": "call_family", "title_ur": "فون کرنا", "title_en": "Make a call", "launch_kind": "dial", "needs_phone": true, "is_practice": false, "step_count": 3}]}
```
### `GET /api/workflows/{id}?contact_id=son`
The workflow plus `steps` (`index`, `screen_id`, `target_id`, `text_ur/en`, `why_ur/en`, `hint_ur/en`) and `starting_help_level` for this user.

### `POST /api/workflows/{id}/resolve`
`{"contact_phone": "0300-1234567", "contact_id": "son"}`
```json
{"workflow_id": "call_family",
 "launch": {"kind": "dial", "uri": "tel:+923001234567", "android_action": null, "user_must_tap": true, "practice_first": false},
 "steps": [...]}
```
Launch targets come only from a fixed template list (`tel:`, `https://wa.me/`, `sms:`, `android.settings.WIFI_SETTINGS`, `android.media.action.STILL_IMAGE_CAMERA`). Phone numbers are validated (10–15 digits; `03xx…` becomes `923xx…`) and never logged. **The backend never performs device actions**: the app opens the target only after the user taps the last step.

## 8. Progress and task completion (help that fades)
### `POST /api/tasks/{task_id}/start` → 201
Optional body `{"at_least": "highlight"}` (use when the task was started from a suggestion).
```json
{"attempt_id": 7, "task_id": "call_family", "start_help_level": "full", "progress": {"...": "see below"}}
```
### `POST /api/tasks/attempts/{attempt_id}/struggle`
`{"step_index": 1, "current_help_level": "highlight"}` → `{"attempt_id": 7, "new_help_level": "full", "struggle_count": 1}`

### `POST /api/tasks/attempts/{attempt_id}/complete`
`{"duration_ms": 9000, "abandoned": false}`
```json
{"attempt_id": 7, "status": "completed", "clean": true, "progress": {"...": "..."},
 "celebration": {"just_mastered": true, "stage": "confident", "emoji": "🌳", "message_ur": "شاباش! ...", "message_en": "Well done! You can now do \"Make a call\" on your own. 🌳"}}
```
A run is "clean" if no struggle was recorded. Starting help: 0 clean runs → `full`, 1–2 → `highlight`, 3+ → `none`, and the task is mastered at 3.

### `GET /api/progress`
```json
{"tasks": [{"task_id": "call_family", "title_ur": "فون کرنا", "title_en": "Make a call", "stage": "getting_there", "stage_emoji": "🌿",
            "stage_label_ur": "تقریباً آ گیا", "stage_label_en": "Getting there", "starting_help_level": "highlight",
            "attempts": 2, "completions": 2, "clean_completions": 1, "independent_completions": 0, "mastered": false,
            "last_done_at": "...", "most_struggled_step": {"step_index": 1, "text_ur": "نام پر دبائیں", "text_en": "Tap the person's name"}}],
 "summary": {"confident": [], "learning": ["call_family"], "not_tried": ["whatsapp_video", "scam_check", "wifi_settings", "open_camera"], "total_independent_completions": 0}}
```
### `GET /api/progress/{task_id}`
One item, in the same shape as an entry in `tasks`.

### Demo helpers
- `POST /api/progress/reset`: clears progress and attempts.
- `POST /api/progress/{task_id}/seed` with `{"clean_completions": 2}`: jumps to "attempt 3".

---

## Run locally
```bash
cd backend
python -m venv .venv && .venv\Scripts\activate          # Windows
pip install -r requirements.txt
copy .env.example .env                                  # fill DATABASE_URL, FIREBASE_PROJECT_ID, optional GEMINI_API_KEY
alembic upgrade head
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```
Tests (they create test users `dev-…` in the database configured in `.env`, so use a Neon dev branch or a local DB):
```bash
set DEV_AUTH_ENABLED=true && python -m pytest -q tests
```
