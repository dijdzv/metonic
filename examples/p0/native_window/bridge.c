#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "moonbit.h"
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")

typedef struct { int32_t type, x, y; } Event;
static Event ring[64];
static volatile LONG ring_head, ring_tail;
static volatile LONG ring_failed;
static HWND window_handle;
static HINSTANCE instance_handle;
static int test_mode_enabled;
static int client_width = 640, client_height = 360;

static void fatal(const char *message) { fputs(message, stderr); fputc('\n', stderr); }
static int enqueue(int32_t type, int32_t x, int32_t y) {
  LONG head = ring_head, next = (head + 1) & 63;
  if (next == ring_tail) { ring_failed = 1; fatal("metonic window event ring overflow"); return 0; }
  ring[head] = (Event){type, x, y};
  InterlockedExchange(&ring_head, next);
  return 1;
}

static LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_PAINT: {
      PAINTSTRUCT paint; BeginPaint(hwnd, &paint); EndPaint(hwnd, &paint); enqueue(1, 0, 0); return 0;
    }
    case WM_SIZE:
      if (LOWORD(lparam) && HIWORD(lparam)) { client_width = LOWORD(lparam); client_height = HIWORD(lparam); enqueue(2, client_width, client_height); } return 0;
    case WM_KEYDOWN: enqueue(3, (int32_t)wparam, 0); return 0;
    case WM_LBUTTONDOWN: if (!test_mode_enabled) SetFocus(hwnd); enqueue(4, (int16_t)LOWORD(lparam), (int16_t)HIWORD(lparam)); return 0;
    case WM_CLOSE: enqueue(5, 0, 0); return 0;
    case WM_DESTROY: PostQuitMessage(0); return 0;
    default: return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}

__declspec(dllexport) int32_t metonic_window_create(void) {
  if (window_handle) return 0;
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  instance_handle = GetModuleHandleW(NULL);
  WNDCLASSW klass = {0}; klass.hInstance = instance_handle; klass.lpfnWndProc = window_proc; klass.lpszClassName = L"MetonicNativeProbe"; klass.hCursor = LoadCursorW(NULL, MAKEINTRESOURCEW(32512));
  if (!RegisterClassW(&klass) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return -1;
  RECT rect = {0, 0, 640, 360}; if (!AdjustWindowRectEx(&rect, WS_OVERLAPPEDWINDOW, FALSE, 0)) return -1;
  window_handle = CreateWindowExW(0, klass.lpszClassName, L"metonic native probe", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, rect.right - rect.left, rect.bottom - rect.top, NULL, NULL, instance_handle, NULL);
  if (!window_handle) return -1;
  wchar_t test_value[8]; DWORD test_length = GetEnvironmentVariableW(L"METONIC_WINDOW_TEST", test_value, 8);
  test_mode_enabled = test_length == 1 && test_value[0] == L'1';
  if (!test_mode_enabled) ShowWindow(window_handle, SW_SHOWNOACTIVATE);
  RECT client; if (!GetClientRect(window_handle, &client)) { DestroyWindow(window_handle); window_handle = NULL; return -1; }
  client_width = client.right; client_height = client.bottom; enqueue(2, client_width, client_height); enqueue(1, 0, 0); InvalidateRect(window_handle, NULL, FALSE);
  return 0;
}

__declspec(dllexport) int32_t metonic_window_next_event(void) {
  if (ring_failed) return -1;
  for (;;) {
    LONG tail = ring_tail;
    if (tail != ring_head) { ring_tail = (tail + 1) & 63; return ring[tail].type; }
    MSG message; int result = GetMessageW(&message, NULL, 0, 0); if (result <= 0) return result == 0 ? 5 : -1;
    TranslateMessage(&message); DispatchMessageW(&message);
    if (ring_failed) return -1;
  }
}
__declspec(dllexport) int32_t metonic_window_poll_event(void) {
  if (ring_failed) return -1;
  LONG tail = ring_tail;
  if (tail != ring_head) { ring_tail = (tail + 1) & 63; return ring[tail].type; }
  for (int i = 0; i < 64; ++i) {
    MSG message;
    if (!PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) break;
    if (message.message == WM_QUIT) return 5;
    TranslateMessage(&message);
    DispatchMessageW(&message);
    if (ring_failed) return -1;
    tail = ring_tail;
    if (tail != ring_head) { ring_tail = (tail + 1) & 63; return ring[tail].type; }
  }
  return 0;
}
__declspec(dllexport) void *metonic_window_hwnd(void) { return window_handle; }
__declspec(dllexport) void *metonic_window_hinstance(void) { return instance_handle; }
__declspec(dllexport) int32_t metonic_window_event_x(void) { LONG tail = (ring_tail - 1) & 63; return ring[tail].x; }
__declspec(dllexport) int32_t metonic_window_event_y(void) { LONG tail = (ring_tail - 1) & 63; return ring[tail].y; }

__declspec(dllexport) void metonic_window_destroy(void) {
  if (window_handle) DestroyWindow(window_handle); window_handle = NULL;
}
__declspec(dllexport) int32_t metonic_window_test_mode(void) { return test_mode_enabled; }
__declspec(dllexport) int32_t metonic_window_test_step(int32_t step, int32_t x, int32_t y) {
  if (!test_mode_enabled || !window_handle) return -1;
  if (step == 0) { if (!PostMessageW(window_handle, WM_KEYDOWN, VK_RIGHT, 0)) return -1; }
  else if (step == 1) { RECT rect = {0, 0, 317, 193}; if (!AdjustWindowRectEx(&rect, WS_OVERLAPPEDWINDOW, FALSE, 0)) return -1; if (!SetWindowPos(window_handle, NULL, 0, 0, rect.right - rect.left, rect.bottom - rect.top, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)) return -1; if (!InvalidateRect(window_handle, NULL, FALSE)) return -1; }
  else if (step == 2) { if (!PostMessageW(window_handle, WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(x, y))) return -1; }
  else if (step == 3) { if (!PostMessageW(window_handle, WM_CLOSE, 0, 0)) return -1; }
  else return -1;
  return 0;
}
