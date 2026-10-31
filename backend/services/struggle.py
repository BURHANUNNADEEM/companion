"""Server-side struggle scoring.

The phone keeps raw taps on-device and sends only counters for the current
window. The server scores them with configurable thresholds so the rules can
be tuned via env vars without shipping a new app.
"""

from core.config import Settings

WEIGHTS = {
    "backtracking": 1.0,
    "idle": 1.0,
    "repeated_taps": 1.0,
    "wrong_taps": 1.0,
    "looping": 0.7,
    "no_completion": 0.6,
}


def idle_threshold_s(s: Settings, median_step_ms: int | None, task_active: bool) -> float:
    """Idle is judged against the user's OWN pace, clamped. Longer when just browsing."""
    if not task_active:
        return float(s.struggle_idle_max_s)
    if not median_step_ms:
        return float(s.struggle_idle_min_s)
    t = median_step_ms / 1000 * s.struggle_idle_pace_multiplier
    return max(float(s.struggle_idle_min_s), min(float(s.struggle_idle_max_s), t))


def evaluate(s: Settings, *, back_count: int, idle_seconds: float, max_same_target_taps: int,
             wrong_taps: int, max_screen_visits: int, distinct_screens: int,
             seconds_without_completion: float, median_step_ms: int | None, task_active: bool) -> dict:
    idle_t = idle_threshold_s(s, median_step_ms, task_active)
    sig: list[str] = []
    if back_count >= s.struggle_backtrack_count:
        sig.append("backtracking")
    if idle_seconds >= idle_t:
        sig.append("idle")
    if max_same_target_taps >= s.struggle_repeated_tap_count:
        sig.append("repeated_taps")
    if task_active and wrong_taps >= s.struggle_wrong_tap_count:
        sig.append("wrong_taps")
    if distinct_screens >= 2 and max_screen_visits >= s.struggle_loop_visits:
        sig.append("looping")
    if seconds_without_completion >= s.struggle_no_completion_s:
        sig.append("no_completion")
    score = round(sum(WEIGHTS[x] for x in sig), 2)
    return {
        "score": score,
        "signals": sig,
        "triggered": score >= s.struggle_trigger_threshold,
        "idle_threshold_seconds": round(idle_t, 1),
        "threshold": s.struggle_trigger_threshold,
    }


def public_config(s: Settings) -> dict:
    return {
        "backtrack_count": s.struggle_backtrack_count,
        "backtrack_window_seconds": s.struggle_backtrack_window_s,
        "idle_min_seconds": s.struggle_idle_min_s,
        "idle_max_seconds": s.struggle_idle_max_s,
        "idle_pace_multiplier": s.struggle_idle_pace_multiplier,
        "repeated_tap_count": s.struggle_repeated_tap_count,
        "loop_visits": s.struggle_loop_visits,
        "no_completion_seconds": s.struggle_no_completion_s,
        "wrong_tap_count": s.struggle_wrong_tap_count,
        "trigger_threshold": s.struggle_trigger_threshold,
        "weights": WEIGHTS,
        "ladder": {
            "clean_for_highlight": s.ladder_clean_for_highlight,
            "clean_for_none": s.ladder_clean_for_none,
            "clean_for_mastery": s.ladder_clean_for_mastery,
        },
    }
