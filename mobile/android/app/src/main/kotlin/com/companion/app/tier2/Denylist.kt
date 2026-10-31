package com.companion.app.tier2

import android.view.accessibility.AccessibilityNodeInfo

/**
 * Screens where Companion takes NO action (PRD F10 / §9): banking & payment apps, password managers,
 * password/OTP fields, security settings, app installs and purchases.
 */
object Denylist {
    private val PACKAGES = setOf(
        // Pakistani banks / wallets
        "com.hbl.android.hblmobilebanking", "com.hbl.konnect", "app.com.brd", "com.ubl.digital", "com.mcb.mcblive",
        "com.meezanbank.meezandigital", "com.abl.mobile", "com.bankalfalah.alfamobile", "com.techlogix.mobilinkcustomer",
        "pk.com.telenor.phoenix", "com.sadapay.app", "com.nayapay.app", "com.bankislami.mobile",
        "com.askari.mbank", "com.faysalbank.digital", "com.scb.breezepk",
        // Global payments
        "com.google.android.apps.walletnfcrel", "com.paypal.android.p2pmobile", "com.wise.android",
        // Password managers / authenticators
        "com.google.android.apps.authenticator2", "com.azure.authenticator", "com.lastpass.lpandroid",
        "com.x8bit.bitwarden", "com.onepassword.android", "com.agilebits.onepassword",
        // Installs / purchases
        "com.android.vending", "com.google.android.packageinstaller", "com.android.packageinstaller",
        "com.samsung.android.app.samsungapps",
    )
    private val PACKAGE_KEYWORDS = listOf("bank", "wallet", "pay", "finance", "crypto", "authenticator", "password", "vault")
    private val SENSITIVE_IDS = listOf("password", "passwd", "otp", "pin_", "pincode", "cvv", "security_code", "lock_pattern")
    private val SENSITIVE_TITLES = listOf(
        "security", "screen lock", "fingerprint", "face unlock", "device admin", "install unknown apps",
        "passwords", "biometrics", "سیکیورٹی", "پاس ورڈ", "اسکرین لاک",
    )

    fun isPackageDenied(pkg: String?): Boolean {
        if (pkg.isNullOrEmpty()) return false
        val p = pkg.lowercase()
        if (p == "com.companion.app") return false
        return p in PACKAGES || PACKAGE_KEYWORDS.any { p.contains(it) }
    }

    /** True if the current window has a password/OTP field or looks like a security screen. */
    fun isSensitiveWindow(root: AccessibilityNodeInfo?, maxNodes: Int = 400): Boolean {
        if (root == null) return false
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var seen = 0
        while (queue.isNotEmpty() && seen < maxNodes) {
            val n = queue.removeFirst()
            seen++
            if (n.isPassword) return true
            val id = n.viewIdResourceName?.lowercase() ?: ""
            if (SENSITIVE_IDS.any { id.contains(it) }) return true
            if (n.isHeading || seen < 15) { // titles are near the top of the tree
                val t = n.text?.toString()?.lowercase() ?: ""
                if (SENSITIVE_TITLES.any { t == it || t.startsWith("$it ") }) return true
            }
            for (i in 0 until n.childCount) n.getChild(i)?.let { queue.add(it) }
        }
        return false
    }
}
