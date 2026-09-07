#ifdef _WIN32

#include <windows.h>
#include <moonbit.h>

MOONBIT_FFI_EXPORT
int metonic_process_handle_count(void) {
  DWORD count = 0;
  if (!GetProcessHandleCount(GetCurrentProcess(), &count)) {
    return -1;
  }
  return (int)count;
}

static void metonic_noop(void) {}

void (*metonic_noop_callback(void))(void) { return metonic_noop; }

#endif
