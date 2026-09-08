#include <windows.h>
#include <stdint.h>
#include "accesskit.h"
#include "../accessibility_probe/navigate.c"

static HANDLE entered, resume_callback, caller;
static accesskit_action_handler_callback receiver;
static LONG delivered, freed, callback_timeout;
static LONG clicks;
static int gated;
static HRESULT invoked;
static void counted_free(accesskit_action_request *request) {
  accesskit_action_request_free(request);
  InterlockedIncrement(&freed);
}
static void held_callback(accesskit_action_request *request, void *cookie) {
  InterlockedIncrement(&delivered);
  if (request->action == ACCESSKIT_ACTION_CLICK) InterlockedIncrement(&clicks);
  if (gated && request->action == ACCESSKIT_ACTION_CLICK) {
    SetEvent(entered);
    if (WaitForSingleObject(resume_callback, 5000) != WAIT_OBJECT_0)
      InterlockedIncrement(&callback_timeout);
  }
  receiver(request, cookie);
}
static accesskit_windows_subclassing_adapter *observed_open(HWND hwnd,
    accesskit_activation_handler_callback activate, void *activate_data,
    accesskit_action_handler_callback action, void *cookie) {
  receiver = action;
  return accesskit_windows_subclassing_adapter_new(hwnd, activate, activate_data,
      held_callback, cookie);
}
/* Only interpose callback scheduling and free observation in this executable.
   Requests, providers and adapter destruction still belong to the real SDK. */
#define accesskit_action_request_free counted_free
#define accesskit_windows_subclassing_adapter_new observed_open
#include "../accessibility/mailbox.c"

uintptr_t metonic_sdk_window(void) {
  return (uintptr_t)CreateWindowExW(0, L"STATIC", L"Metonic SDK lifetime probe",
      WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 320, 200,
      NULL, NULL, GetModuleHandleW(NULL), NULL);
}
void metonic_sdk_show(uintptr_t hwnd) { ShowWindow((HWND)hwnd, SW_SHOWNOACTIVATE); }
void metonic_sdk_destroy(uintptr_t hwnd) { DestroyWindow((HWND)hwnd); }
void metonic_sdk_label(uintptr_t node) {
  accesskit_node_set_label((accesskit_node *)node, "SDK action");
}
static DWORD WINAPI invoke_worker(void *window) {
  HRESULT initialized = CoInitializeEx(NULL, COINIT_MULTITHREADED);
  if (FAILED(initialized)) { invoked = initialized; return 1; }
  HUIANODE root = NULL, button = NULL;
  HUIAPATTERNOBJECT pattern = NULL;
  invoked = UiaNodeFromHandle((HWND)window, &root);
  if (SUCCEEDED(invoked)) {
    int matched = 0;
    button = (HUIANODE)metonic_uia_navigate((uintptr_t)root, NavigateDirection_FirstChild);
    for (int i = 0; button && i < 32; i++) {
      VARIANT label;
      VariantInit(&label);
      HRESULT result = UiaGetPropertyValue(button, 30005, &label);
      int match = SUCCEEDED(result) && V_VT(&label) == VT_BSTR && V_BSTR(&label) &&
          wcscmp(V_BSTR(&label), L"SDK action") == 0;
      VariantClear(&label);
      if (match) { matched = 1; break; }
      HUIANODE next = (HUIANODE)metonic_uia_navigate((uintptr_t)button, NavigateDirection_NextSibling);
      UiaNodeRelease(button);
      button = next;
    }
    invoked = matched ? UiaGetPatternProvider(button, 10000, &pattern) : E_FAIL;
    if (SUCCEEDED(invoked)) invoked = InvokePattern_Invoke(pattern);
  }
  if (pattern) UiaPatternRelease(pattern);
  if (button) UiaNodeRelease(button);
  if (root) UiaNodeRelease(root);
  CoUninitialize();
  return 0;
}
int32_t metonic_sdk_start(uintptr_t hwnd, int32_t pause) {
  gated = pause;
  entered = CreateEventW(NULL, TRUE, FALSE, NULL);
  resume_callback = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (!entered || !resume_callback) return 0;
  caller = CreateThread(NULL, 0, invoke_worker, (void *)hwnd, 0, NULL);
  return caller != NULL;
}
static int pump_until(HANDLE event) {
  ULONGLONG deadline = GetTickCount64() + 4000;
  while (GetTickCount64() < deadline) {
    if (WaitForSingleObject(event, 0) == WAIT_OBJECT_0) return 1;
    MSG message;
    while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    MsgWaitForMultipleObjects(1, &event, FALSE, 10, QS_ALLINPUT);
  }
  return 0;
}
int32_t metonic_sdk_wait_entered(void) { return pump_until(entered); }
int32_t metonic_sdk_finish(void) {
  SetEvent(resume_callback);
  if (!pump_until(caller)) return 0;
  CloseHandle(caller);
  CloseHandle(entered);
  CloseHandle(resume_callback);
  caller = entered = resume_callback = NULL;
  return !callback_timeout;
}
int32_t metonic_sdk_metric(int32_t field) {
  return field == 0 ? delivered : field == 1 ? freed : field == 3 ? (int32_t)invoked : field == 4 ? clicks : (int32_t)count;
}
void metonic_sdk_free(uintptr_t request) { counted_free((accesskit_action_request *)request); }
