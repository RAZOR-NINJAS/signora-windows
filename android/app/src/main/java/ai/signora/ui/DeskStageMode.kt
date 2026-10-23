package ai.signora.ui

import android.content.Context
import android.content.SharedPreferences

/**
 * Persisted state for DeskStage, the hidden landscape workspace used when the
 * phone screen is mirrored to a laptop. SharedPreferences matches the rest of
 * the app; no DataStore dependency is introduced.
 */
object DeskStageMode {
    private const val PREFS = "signora_desk_stage"
    private const val KEY_ENABLED = "desk_stage_enabled"
    private const val KEY_UNLOCKED = "desk_stage_unlocked"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun isUnlocked(context: Context): Boolean =
        prefs(context).getBoolean(KEY_UNLOCKED, false)

    fun unlock(context: Context) {
        prefs(context).edit().putBoolean(KEY_UNLOCKED, true).apply()
    }
}
