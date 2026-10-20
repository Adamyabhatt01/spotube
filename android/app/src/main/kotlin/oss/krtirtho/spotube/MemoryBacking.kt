package oss.krtirtho.spotube

import android.os.Build

/**
 * Memory backing policy for the app process.
 *
 * Transparent huge pages (THP) are a Linux kernel feature that backs large
 * anonymous mappings with 2 MB pages instead of 4 KB ones. The Dart VM
 * reserves a multi-gigabyte heap arena and touches only small parts of it, so
 * with THP enabled the kernel charges a full 2 MB of resident memory for
 * every few KB the app actually uses.
 *
 * On a phone that matters far more than on a desktop: the same phantom pages
 * come straight out of the app's memory budget, and Android kills
 * low-memory apps that exceed it.
 *
 * Measured on Linux (release build, idle at t+30s): RSS 606 MB with THP on,
 * 203 MB with it off, with the live Dart heap unchanged at 27.5 MB either
 * way. The smoothness cost is inside run-to-run variance.
 *
 * PR_SET_THP_DISABLE is a per-process setting, so only this app is
 * affected. It fails harmlessly on a kernel without THP.
 *
 * Called from [MainActivity.onCreate] before the Flutter engine starts, so
 * the engine's own allocations are covered too.
 */
object MemoryBacking {
    /** PR_SET_THP_DISABLE, stable across every Linux kernel. */
    private const val PR_SET_THP_DISABLE = 41

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            // The native helper is what performs the prctl call; there is
            // no public Android API for it.
            System.loadLibrary("spotube")
        }
    }

    /**
     * Calls prctl(PR_SET_THP_DISABLE, 1) for this process.
     *
     * Implemented natively so the call happens before the Flutter engine
     * starts allocating, which is the same ordering the Linux runner uses.
     */
    fun disableTransparentHugePages() {
        try {
            nativePrctl(PR_SET_THP_DISABLE, 1L, 0L, 0L, 0L)
        } catch (_: UnsatisfiedLinkError) {
            // The native library is missing: the app still works, it just
            // keeps the pre-existing huge-page behavior.
        } catch (_: Throwable) {
            // Best-effort. Any failure means the kernel keeps using huge
            // pages, which is the pre-existing behavior.
        }
    }

    /**
     * The raw prctl call.
     *
     * `@JvmStatic` so the JVM exports a **static** bridge on
     * [MemoryBacking] itself: the JNI symbol is then
     * `Java_oss_krtirtho_spotube_MemoryBacking_nativePrctl` with a `jclass`
     * second parameter, which is what the native side declares. Without
     * `@JvmStatic` the method would only exist as an instance method and
     * the lookup would fail at runtime with an UnsatisfiedLinkError.
     */
    @JvmStatic
    external fun nativePrctl(
        option: Int,
        arg2: Long,
        arg3: Long,
        arg4: Long,
        arg5: Long,
    ): Int
}
