# Companion API / کمپینین API

Base URL: `http://localhost:8000` (emulator: `http://10.0.2.2:8000`). All endpoints are under `/api`.
Interactive docs: **`/docs`** (Swagger UI) and `/redoc`. Machine-readable spec: [`openapi.json`](openapi.json).

**Auth:** `Authorization: Bearer <Firebase ID token>`. With `AUTH_MODE=dev` (local only): `Bearer dev:<uid>` or
`Bearer dev:<uid>:<email>`.

**Bilingual responses:** every user-facing sentence is returned as `{"en": "...", "ur": "..."}`, plus a `text`
field in the user's language (`users.language`, default `ur`).

**Errors:** `{"detail": "<code>"}`, e.g. `401 missing_token`, `403 consent_required`, `403 parent_role_required`,
`409 role_already_set`, `410 code_expired`.

## Profile, consent, privacy (F5)

| Method | Path | Body | Notes |
|---|---|---|---|
| GET | `/me` | – | Creates the user on first call. Returns `role`, `language`, `consent` |
| PUT | `/me/role` | `{"role": "parent" \| "caregiver"}` | Once only; changing → `409` |
| PUT | `/me/language` | `{"language": "ur" \| "en"}` | |
| PUT | `/me/profile` | `{"display_name": "امی"}` | Shown to linked family |
| GET | `/me/sharing-preview` | – | Parent sees exactly what caregivers see |
| DELETE | `/me/data` | – | Deletes events, consents, scam checks, links, alerts, guide cards and the user |
| GET | `/consent` | – | Current choices + plain-language text (en/ur) |
| PUT | `/consent` | `{"activity_tracking": true, "caregiver_sharing": false, "scam_text_storage": false, "ai_disclosure": true}` | Append-only history |

## Events and config (F2)

`POST /events` — requires `activity_tracking` consent (otherwise `403 consent_required`, nothing stored).

```json
{"session_id": "a1b2c3", "events": [
  {"type": "tap", "item_id": "tile_call", "ts": "2026-10-31T09:00:00Z", "properties": {"screen": "home", "target": "tile_call"}},
  {"type": "struggle_detected", "item_id": "call", "properties": {"task": "call", "score": 1.4, "signals": ["backtracking", "looping"]}}
]}
```
Allowed types: `screen_view tap back idle task_started task_completed suggestion_shown suggestion_accepted
suggestion_dismissed something_else_tapped nav_started nav_completed nav_aborted struggle_detected`.
Properties are allow-listed (`screen, target, task, workflow_id, skill_id, score, signals, duration_ms, reason, rank, hour,
tier, mode, step, steps_total, source, lang, package`) and values must be short identifiers — free text is dropped.
→ `{"accepted": 2, "rejected": 0}`

`GET /config` (no auth) — struggle thresholds/weights (from env vars), home tiles, `llm_enabled`.

## Suggestions (F3)

`GET /suggestions?hour=9&last_task=photos` →
```json
{"suggestions": [{"task": "call", "workflow_id": "call_contact", "label": {"en": "Call", "ur": "کال کریں"}, "text": "کال کریں", "rank": 1}],
 "something_else": true, "something_else_label": {"en": "Something else", "ur": "کچھ اور"},
 "prompt": {"en": "Need a hand? Maybe one of these:", "ur": "کیا مدد چاہیے؟ شاید ان میں سے کوئی:"},
 "backoff": {"active": false, "until": null}, "is_default": false}
```
After 3 consecutive dismissals: `suggestions: []`, `backoff.active: true` for 30 minutes (or until an accept).

## Voice intent (F7/F8)

`POST /voice/intent` `{"transcript": "بیٹے کو فون کرو", "locale": "ur-PK"}` →
`{"task": "call", "workflow_id": "call_contact", "slots": {"contact": "son", "relation": "son"}, "confidence": 0.9, "source": "rules", "explanation": {...}, "text": "..."}`.
Unmatched (and LLM off / low confidence): `task: null` + `fallback_tasks` (the 6 home tiles).

## AI Navigation Engine (F10, core)

`POST /navigation/plan` with ONE of `{"utterance": "..."}`, `{"task": "call"}`, `{"workflow_id": "wifi_on"}`, plus optional `slots`.

Pipeline: rules / Gemini understand → **Flow Engine** validates (known workflow, typed slots, denylist, ≤10 steps,
allowed intents only, sanitised explanation) → steps come only from `app/flows/workflows.json`.

```json
{"status": "ok", "workflow_id": "call_contact", "task": "call",
 "title": {"en": "Call someone", "ur": "کسی کو کال کریں"},
 "intro": {"en": "Let's call your son. I'll show you each step.", "ur": "آئیں اپنے بیٹے کو کال کرتے ہیں۔ میں ہر قدم دکھاؤں گا۔"},
 "slots": {"contact": "son", "relation": "son"},
 "steps": [{"index": 0, "id": "tap_tile", "screen": "companion_home",
            "target": {"id": "tile_call", "label": {"en": "Call", "ur": "کال کریں"}},
            "highlight": {"x": 0.04, "y": 0.2, "w": 0.44, "h": 0.2}, "arrow": "down",
            "hint": {"en": "Tap the green Call button.", "ur": "سبز 'کال کریں' بٹن دبائیں۔"},
            "action": {"kind": "open_intent", "intent": "dial", "params": {"contact": "son"}},
            "completion": {"type": "intent_launched"}}, "..."],
 "total_steps": 2, "tier2_skill": "call_contact", "limits": {"max_steps": 10, "timeout_seconds": 30},
 "done": {"en": "Well done! You did it.", "ur": "شاباش! آپ نے کر لیا۔"}, "source": "rules"}
```
- `highlight` = fractions of the screen (0–1); `arrow` ∈ up/down/left/right.
- `action.kind` ∈ `open_intent | external_hint | in_app_route | in_app_hint`; intents ∈ `dial sms gallery camera whatsapp_chat whatsapp_open settings_wifi settings_bluetooth settings_sound settings_display maps_search`.
- `completion.type` ∈ `intent_launched | returned_to_app | user_confirm | screen_reached | tap_target`.
- Refusals: `{"status": "refused", "reason": "sensitive" | "unknown", "message": {...}, "fallback_tasks": [...]}` — e.g. banking, payments, OTP, passwords, installs.

`GET /navigation/workflows` — the predefined workflow catalogue.

## Scam check (F6)

`POST /scam/check` `{"text": "...", "source": "paste" | "share" | "screenshot"}` →
```json
{"id": "…", "verdict": "likely_scam", "score": 1.0, "reasons": ["otp_request", "urgency_threat", "impersonation"], "engine": "rules",
 "explanation": {"label": {"en": "Likely scam", "ur": "غالباً دھوکہ"},
                 "reason": {"en": "It asks for a secret code, PIN or password.", "ur": "…"},
                 "action": {"en": "Do not share the code. Banks never ask for it. Call your bank using the number on your card.", "ur": "…"},
                 "ask_family": {"en": "When in doubt, ask your family.", "ur": "شک ہو تو اپنے گھر والوں سے پوچھیں۔"},
                 "text": "…"}}
```
Only verdict/score/reasons are stored (redacted text only with `scam_text_storage` consent).
`POST /scam/share/{id}` — "Tell my family" (verdict only) → `{"caregivers_notified": 1}`. `GET /scam/history`.

## Caregiver (F9)

| Method | Path | Role | Notes |
|---|---|---|---|
| POST | `/caregiver/invite` `{"email": "kid@example.com"}` | parent | E-mails a one-time 8-char code (24 h). Dev console mode also returns `dev_invite_code` |
| POST | `/caregiver/accept` `{"code": "ABCD2345"}` | caregiver | Signed-in e-mail must match the invite |
| POST | `/caregiver/approve/{link_id}` | parent | Link becomes `active` |
| DELETE | `/caregiver/link/{link_id}` | either | Revoked immediately |
| GET | `/caregiver/links` | either | |
| GET | `/caregiver/summary` | caregiver | Per parent (only if parent's `caregiver_sharing` is on): `last_active`, `tasks_completed_per_day`, `struggle_episodes_per_day`, `friction_tasks`, `scam_checks` |
| GET | `/caregiver/alerts` · POST `/caregiver/alerts/{id}/seen` | caregiver | `repeated_struggle`, `scam_shared`, `inactivity` |
| POST | `/caregiver/guide-cards` `{"parent_id", "text", "workflow_id"?}` | caregiver | |
| GET | `/guide-cards` · POST `/guide-cards/{id}/seen` | parent | |
| POST | `/alerts/inactivity/run` (header `X-Admin-Token`) | scheduler | Run daily |
