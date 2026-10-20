// Native helper for the app's memory-backing policy.
//
// Transparent huge pages (THP) are a Linux kernel feature that backs large
// anonymous mappings with 2 MB pages instead of 4 KB ones. The Dart VM
// reserves a multi-gigabyte heap arena and touches only small parts of it,
// so with THP enabled the kernel charges a full 2 MB of resident memory for
// every few KB the app actually uses.
//
// prctl(PR_SET_THP_DISABLE) is a per-process setting, so only this app is
// affected. It fails harmlessly on a kernel without THP.
//
// This mirrors the same call in the Linux runner (linux/main.cc), so the two
// desktop/mobile platforms behave the same way.

#include <sys/prctl.h>

#include <jni.h>

extern "C" JNIEXPORT jint JNICALL
Java_oss_krtirtho_spotube_MemoryBacking_nativePrctl(JNIEnv* env,
                                                    jclass clazz,
                                                    jint option,
                                                    jlong arg2,
                                                    jlong arg3,
                                                    jlong arg4,
                                                    jlong arg5) {
  return prctl(static_cast<int>(option), static_cast<unsigned long>(arg2),
               static_cast<unsigned long>(arg3),
               static_cast<unsigned long>(arg4),
               static_cast<unsigned long>(arg5));
}
