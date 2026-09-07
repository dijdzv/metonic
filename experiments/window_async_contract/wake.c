#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static DWORD metonic_ui_thread;
static volatile LONG metonic_wakes;
static volatile LONG metonic_failed_wakes;

void metonic_async_init_ui_thread(void) {
  metonic_ui_thread = GetCurrentThreadId();
}

/* The foreign callback cannot access captured MoonBit objects or refcounts. */
void metonic_async_wake(void) {
  InterlockedIncrement(&metonic_wakes);
  if (metonic_ui_thread == 0 ||
      !PostThreadMessageW(metonic_ui_thread, 0x8100, 0, 0)) {
    InterlockedIncrement(&metonic_failed_wakes);
  }
}

int metonic_async_wake_count(void) {
  return (int)InterlockedCompareExchange(&metonic_wakes, 0, 0);
}

int metonic_async_failed_wake_count(void) {
  return (int)InterlockedCompareExchange(&metonic_failed_wakes, 0, 0);
}
