package oss.krtirtho.spotube

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Before the Flutter engine starts, so the engine's own allocations
        // are covered too, not just the Dart heap. See [MemoryBacking] for
        // what this does and why.
        MemoryBacking.disableTransparentHugePages()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Answers the host's device-memory questions (the per-app heap
        // limit). Registered by hand because it is app code, not a pub
        // package, so the generated registrant does not know about it.
        flutterEngine.plugins.add(DeviceMemoryChannel())
    }
}
