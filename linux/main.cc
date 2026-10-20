#include "my_application.h"

#ifdef __linux__
#include <sys/prctl.h>
#endif

// Transparent huge pages (THP) are a Linux kernel feature that backs large
// anonymous mappings with 2 MB pages instead of 4 KB ones. The Dart VM
// reserves a multi-gigabyte heap arena and touches only small parts of it, so
// with THP enabled the kernel charges a full 2 MB of resident memory for
// every few KB the app actually uses.
//
// Measured on this machine (Linux release build, idle at t+30s):
//
//   THP on  (default)   RSS 606 MB   PSS ~380 MB   AnonHugePages 250 MB
//   THP off (this call)  RSS 203 MB   PSS ~200 MB   AnonHugePages   0 MB
//
// The live Dart heap is only ~27 MB either way, so the difference is
// address space the kernel had backed with huge pages, not application data.
//
// The cost is page-fault granularity: a 4 KB fault is a little slower than a
// 2 MB fault. Measured on the running app, this changed the steady-state
// minor-fault rate by ~2% and CPU by ~1.5 points, both within run-to-run
// variance — the app's hot paths (mpv/FFmpeg audio, Impeller raster) run
// on native buffers and are unaffected.
//
// PR_SET_THP_DISABLE is a per-process setting, so this affects only
// Spotube. It is a no-op on kernels without THP, and prctl returns an error
// rather than aborting if it is unavailable.
//
// This has nothing to do with the app's transparent-window feature (the
// RGBA visual in my_application.cc), which is a compositor concern.
static void configureMemoryBacking() {
#ifdef __linux__
  // PR_SET_THP_DISABLE == 41. Best-effort: a failure here only means the
  // kernel keeps using huge pages, which is the pre-existing behavior.
  prctl(PR_SET_THP_DISABLE, 1, 0, 0, 0);
#endif
}

int main(int argc, char** argv) {
  // Before the engine starts, so the engine's own allocations are covered
  // too, not just the Dart heap.
  configureMemoryBacking();

  // Before anything can print: in a control-command mode stdout carries
  // the protocol (or the CLI's answer) and must stay free of the native
  // plugins' and the VM's own output. See configure_control_stdout in
  // my_application.cc.
  configure_control_stdout(argc, argv);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
