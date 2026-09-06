#include "../../examples/p0/native_window/bridge.c"

__declspec(dllexport) void *metonic_binding_hwnd(void) {
  return (void *)window_handle;
}

__declspec(dllexport) void *metonic_binding_hinstance(void) {
  return (void *)instance_handle;
}
