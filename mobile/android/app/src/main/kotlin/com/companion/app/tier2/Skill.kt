package com.companion.app.tier2

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** A predefined, ordered flow (F10 Tier 2). Never generated at runtime and never by the LLM. */
data class SkillStep(
    val id: String,
    val action: String,            // click | guide_only | wait_for
    val ids: List<String>,
    val texts: List<String>,
    val descs: List<String>,
    val onlyIfUnchecked: Boolean,
    val hintEn: String,
    val hintUr: String,
) {
    fun hint(lang: String) = if (lang == "ur") hintUr else hintEn
}

data class Skill(val id: String, val packages: Set<String>, val steps: List<SkillStep>)

class SkillSet(val skills: List<Skill>, val maxSteps: Int, val timeoutSeconds: Int) {
    fun find(id: String): Skill? = skills.firstOrNull { it.id == id }
}

object SkillRepository {
    private val ALLOWED_ACTIONS = setOf("click", "guide_only", "wait_for")
    private const val HARD_MAX_STEPS = 10
    private const val HARD_TIMEOUT_S = 30
    @Volatile private var cached: SkillSet? = null

    /** Loads the skills bundled with the Flutter assets and rejects anything outside the allow-list. */
    fun load(context: Context): SkillSet {
        cached?.let { return it }
        val raw = context.assets.open("flutter_assets/assets/skills/skills.json").bufferedReader(Charsets.UTF_8).use { it.readText() }
        val root = JSONObject(raw)
        val limits = root.optJSONObject("limits") ?: JSONObject()
        val maxSteps = minOf(limits.optInt("max_steps", HARD_MAX_STEPS), HARD_MAX_STEPS)
        val timeout = minOf(limits.optInt("timeout_seconds", HARD_TIMEOUT_S), HARD_TIMEOUT_S)
        val skills = mutableListOf<Skill>()
        val arr = root.getJSONArray("skills")
        for (i in 0 until arr.length()) {
            val s = arr.getJSONObject(i)
            val steps = mutableListOf<SkillStep>()
            val sa = s.getJSONArray("steps")
            for (j in 0 until sa.length()) {
                val st = sa.getJSONObject(j)
                val action = st.getString("action")
                require(action in ALLOWED_ACTIONS) { "action not allowed: $action" }
                val m = st.getJSONObject("match")
                val hint = st.getJSONObject("hint")
                steps += SkillStep(
                    id = st.getString("id"),
                    action = action,
                    ids = m.optJSONArray("ids").toList(),
                    texts = m.optJSONArray("texts").toList(),
                    descs = m.optJSONArray("descs").toList(),
                    onlyIfUnchecked = st.optBoolean("only_if_unchecked", false),
                    hintEn = hint.optString("en"),
                    hintUr = hint.optString("ur"),
                )
            }
            require(steps.size in 1..maxSteps) { "too many steps in ${s.getString("id")}" }
            skills += Skill(s.getString("id"), s.getJSONArray("packages").toList().toSet(), steps)
        }
        return SkillSet(skills, maxSteps, timeout).also { cached = it }
    }

    private fun JSONArray?.toList(): List<String> =
        if (this == null) emptyList() else (0 until length()).map { getString(it) }
}
