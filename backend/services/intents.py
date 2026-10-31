"""Voice intent: keywords first, Gemini (allowlist-constrained) as fallback."""

import re

from services import gemini, workflows

MIN_CONFIDENCE = 0.6


def _norm(t: str) -> str:
    return re.sub(r"\s+", " ", t.lower()).strip()


def match_keywords(transcript: str) -> tuple[str | None, float]:
    t = _norm(transcript)
    best, best_score = None, 0
    for wf in workflows.WORKFLOWS.values():
        score = 0
        for kw in wf.keywords:
            strong = kw.startswith("!")
            k = kw.lstrip("!").lower()
            w = 3 if strong else 1  # specific words ("video") beat generic ones ("talk")
            if re.search(r"[a-z]", k):
                if re.search(rf"\b{re.escape(k)}\b", t):
                    score += w * len(k.split())
            elif k in t:
                score += w
        if score > best_score:
            best, best_score = wf.id, score
    if best is None:
        return None, 0.0
    return best, min(0.95, 0.6 + 0.1 * best_score)


async def parse(transcript: str, use_ai: bool) -> dict:
    task, conf = match_keywords(transcript)
    source = "keywords"
    explanation = None
    if task is None and use_ai:
        allowed = {k: f"{w.title_en} / {w.title_ur}" for k, w in workflows.WORKFLOWS.items()}
        res = await gemini.classify_intent(transcript, allowed)
        if res is not None:
            source = "gemini"
            task, conf, explanation = res.task_id, res.confidence, res.explanation_ur or None
    if task is not None and conf < MIN_CONFIDENCE:
        task = None
    wf = workflows.WORKFLOWS.get(task) if task else None
    return {
        "task_id": task,
        "confidence": round(conf, 2),
        "source": source if task else ("gemini" if source == "gemini" else "none"),
        "title_ur": wf.title_ur if wf else None,
        "title_en": wf.title_en if wf else None,
        "explanation_ur": explanation or (f"آپ {wf.title_ur} چاہتی ہیں؟" if wf else "معاف کریں، سمجھ نہیں آیا۔ نیچے سے چنیں۔"),
        "requires_confirmation": True,  # the app must ask "Is this what you want?" — never auto-run
        "fallback_options": None if wf else [
            {"task_id": k, "title_ur": w.title_ur, "title_en": w.title_en} for k, w in workflows.WORKFLOWS.items()
        ],
    }
