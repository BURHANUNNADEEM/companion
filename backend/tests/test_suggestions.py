from collections import Counter
from datetime import datetime, timedelta, timezone

from app.services.suggestions import Completed, rank_tasks
from app.services.tasks import TASKS
from scripts.seed_demo import generate_routine
from tests.conftest import onboard


async def test_new_user_gets_sensible_defaults(client):
    h = await onboard(client, "n1", "parent", lang="ur")
    body = (await client.get("/api/suggestions?hour=9", headers=h)).json()
    assert body["is_default"] is True and body["something_else"] is True
    assert [s["task"] for s in body["suggestions"]] == ["call", "photos", "messages"]
    assert body["suggestions"][0]["text"] == "کال کریں"            # Urdu label
    assert body["prompt"]["ur"] and body["something_else_label"]["ur"] == "کچھ اور"


async def test_sequence_drives_ranking(client):
    h = await onboard(client, "n2", "parent", lang="en")
    now = datetime.now(timezone.utc)
    events = []
    for i in range(6):
        events += [{"type": "task_completed", "item_id": "camera", "ts": (now - timedelta(hours=10 - i)).isoformat(),
                    "properties": {"task": "camera", "hour": 15}},
                   {"type": "task_completed", "item_id": "maps", "ts": (now - timedelta(hours=10 - i, minutes=-5)).isoformat(),
                    "properties": {"task": "maps", "hour": 15}}]
    await client.post("/api/events", headers=h, json={"session_id": "s", "events": events})
    body = (await client.get("/api/suggestions?hour=3&last_task=camera", headers=h)).json()
    assert body["suggestions"][0]["task"] == "maps"
    assert body["suggestions"][0]["text"] == "Directions"


async def test_backs_off_after_three_dismissals_and_recovers_on_accept(client):
    h = await onboard(client, "n3", "parent")
    ev = lambda t, item="call": {"type": t, "item_id": item}  # noqa: E731
    await client.post("/api/events", headers=h, json={"session_id": "s", "events": [ev("suggestion_dismissed")] * 2})
    assert (await client.get("/api/suggestions?hour=9", headers=h)).json()["suggestions"]
    await client.post("/api/events", headers=h, json={"session_id": "s", "events": [ev("suggestion_dismissed")]})
    body = (await client.get("/api/suggestions?hour=9", headers=h)).json()
    assert body["suggestions"] == [] and body["backoff"]["active"] is True
    await client.post("/api/events", headers=h, json={"session_id": "s", "events": [ev("suggestion_accepted", "photos")]})
    assert (await client.get("/api/suggestions?hour=9", headers=h)).json()["backoff"]["active"] is False


def test_feedback_changes_ranking():
    base = rank_tasks([], 9, None)
    assert base[0] == "call"
    after = rank_tasks([], 9, None, accepted=Counter({"messages": 4}), dismissed=Counter({"call": 4}))
    assert after[0] == "messages" and "call" not in after[:1]


def test_top3_accuracy_on_seeded_demo_data():
    """PRD F3 acceptance: top-3 contains the next completed task in >= 60% of cases."""
    data = generate_routine(days=40, seed=11)
    split = int(len(data) * 0.5)
    hits = total = 0
    for i in range(split, len(data)):
        history = [Completed(t, ts) for ts, t in data[:i]]
        ts, actual = data[i]
        last = data[i - 1][1] if data[i - 1][0].date() == ts.date() else None
        top3 = rank_tasks(history, ts.hour, last)
        hits += actual in top3
        total += 1
    accuracy = hits / total
    print(f"top-3 accuracy: {accuracy:.0%} on {total} cases")
    assert accuracy >= 0.60


def test_ranking_only_returns_known_tasks():
    assert all(t in TASKS for t in rank_tasks([], 0, "nonexistent"))
