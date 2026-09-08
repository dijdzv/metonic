#include <windows.h>
#include <stdint.h>
#include "accesskit.h"

static int allocations, frees, wakes;
static HANDLE admitted, resume_delivery, closing, delivery_thread, close_thread;
static int worker_failed;
static void probe_free(accesskit_action_request *request) {
  if (request->data.has_value && request->data.value.tag == ACCESSKIT_ACTION_DATA_VALUE)
    HeapFree(GetProcessHeap(), 0, (void *)request->data.value.value);
  HeapFree(GetProcessHeap(), 0, request);
  frees++;
}
static accesskit_windows_subclassing_adapter *probe_open(HWND hwnd,
    accesskit_activation_handler_callback activate, void *activation_data,
    accesskit_action_handler_callback action, void *action_data) {
  return (accesskit_windows_subclassing_adapter *)(uintptr_t)1;
}
static void probe_close(accesskit_windows_subclassing_adapter *adapter) {}
static BOOL probe_post(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  wakes++;
  if (admitted) {
    SetEvent(admitted);
    if (WaitForSingleObject(resume_delivery, 5000) != WAIT_OBJECT_0) {
      worker_failed = 1;
      return FALSE;
    }
  }
  return TRUE;
}

/* AccessKit owns real callback allocations. Substitute the allocator and adapter
   only in this executable; never pass HeapAlloc memory to Rust's deallocator. */
#define accesskit_action_request_free probe_free
#define accesskit_windows_subclassing_adapter_new probe_open
#define accesskit_windows_subclassing_adapter_free probe_close
#define PostMessageW probe_post
#include "../accessibility/mailbox.c"

uint64_t metonic_mailbox_probe_open(void) {
  if (!metonic_accesskit_open(1, NULL)) return 0;
  return (uint64_t)generation;
}
void metonic_mailbox_probe_close(void) { metonic_accesskit_close(1); }
int32_t metonic_mailbox_probe_send(uint64_t cookie, int32_t size) {
  accesskit_action_request *request = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*request));
  if (!request) return 0;
  request->target_node = 2;
  if (size >= 0) {
    char *text = HeapAlloc(GetProcessHeap(), 0, (size_t)size + 1);
    if (!text) { HeapFree(GetProcessHeap(), 0, request); return 0; }
    memset(text, 'A', size);
    text[size] = 0;
    request->action = ACCESSKIT_ACTION_SET_VALUE;
    request->data.has_value = true;
    request->data.value.tag = ACCESSKIT_ACTION_DATA_VALUE;
    request->data.value.value = text;
  } else {
    request->action = ACCESSKIT_ACTION_CLICK;
  }
  allocations++;
  receive(request, (void *)(uintptr_t)cookie);
  return 1;
}
int32_t metonic_mailbox_probe_take(void) {
  uintptr_t request = metonic_accesskit_take();
  if (!request) return -2;
  int32_t length = metonic_accesskit_value_length(request);
  probe_free((accesskit_action_request *)request);
  return length;
}
int32_t metonic_mailbox_probe_metric(int32_t field) {
  switch (field) {
    case 0: return allocations;
    case 1: return frees;
    case 2: return wakes;
    case 3: return (int32_t)count;
    case 4: return worker_failed;
    default: return -1;
  }
}

static DWORD WINAPI deliver_on_thread(void *cookie) {
  return metonic_mailbox_probe_send((uint64_t)(uintptr_t)cookie, 65536) ? 0 : 1;
}
static DWORD WINAPI close_on_thread(void *unused) {
  SetEvent(closing);
  metonic_mailbox_probe_close();
  return 0;
}
int32_t metonic_mailbox_probe_overlap(uint64_t cookie) {
  admitted = CreateEventW(NULL, TRUE, FALSE, NULL);
  resume_delivery = CreateEventW(NULL, TRUE, FALSE, NULL);
  closing = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (!admitted || !resume_delivery || !closing) return 0;
  delivery_thread = CreateThread(NULL, 0, deliver_on_thread,
      (void *)(uintptr_t)cookie, 0, NULL);
  if (!delivery_thread || WaitForSingleObject(admitted, 5000) != WAIT_OBJECT_0) return 0;
  close_thread = CreateThread(NULL, 0, close_on_thread, NULL, 0, NULL);
  if (!close_thread || WaitForSingleObject(closing, 5000) != WAIT_OBJECT_0) return 0;
  return WaitForSingleObject(close_thread, 0) == WAIT_TIMEOUT;
}
int32_t metonic_mailbox_probe_join(void) {
  SetEvent(resume_delivery);
  HANDLE threads[2] = {delivery_thread, close_thread};
  if (WaitForMultipleObjects(2, threads, TRUE, 5000) != WAIT_OBJECT_0) return 0;
  DWORD delivered, closed;
  if (!GetExitCodeThread(delivery_thread, &delivered) ||
      !GetExitCodeThread(close_thread, &closed)) return 0;
  CloseHandle(delivery_thread);
  CloseHandle(close_thread);
  CloseHandle(admitted);
  CloseHandle(resume_delivery);
  CloseHandle(closing);
  admitted = resume_delivery = closing = delivery_thread = close_thread = NULL;
  return delivered == 0 && closed == 0 && worker_failed == 0;
}
