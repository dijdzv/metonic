#include "../../tools/native_surface_probe/window.c"

__declspec(dllexport) void *metonic_binding_hwnd(void) {
  return (void *)window_handle;
}

__declspec(dllexport) void *metonic_binding_hinstance(void) {
  return (void *)instance_handle;
}
