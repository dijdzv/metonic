#include <windows.h>
#include <stdint.h>
#include "accesskit.h"
#pragma comment(lib, "accesskit.lib")

/* MoonBit's GC objects cannot be the cross-thread queue. Keep request ownership
   here; platform structs never enter the shared semantic model. */
static SRWLOCK lock = SRWLOCK_INIT;
static accesskit_action_request *requests[32];
static unsigned int count;
static uintptr_t generation;
static HWND target;

static void receive(accesskit_action_request *request, void *userdata) {
  AcquireSRWLockExclusive(&lock);
  if (target && (uintptr_t)userdata == generation && count < 32 &&
      (request->action == ACCESSKIT_ACTION_CLICK ||
       request->action == ACCESSKIT_ACTION_FOCUS)) {
    requests[count++] = request;
    PostMessageW(target, WM_APP + 77, 0, 0);
  } else {
    accesskit_action_request_free(request);
  }
  ReleaseSRWLockExclusive(&lock);
}

uintptr_t metonic_accesskit_open(uintptr_t hwnd,
    accesskit_activation_handler_callback activate) {
  AcquireSRWLockExclusive(&lock);
  if (target || count || generation == UINTPTR_MAX) {
    ReleaseSRWLockExclusive(&lock);
    return 0;
  }
  generation++;
  target = (HWND)hwnd;
  uintptr_t cookie = generation;
  ReleaseSRWLockExclusive(&lock);
  return (uintptr_t)accesskit_windows_subclassing_adapter_new(
      (HWND)hwnd, activate, NULL, receive, (void *)cookie);
}

uintptr_t metonic_accesskit_take(void) {
  AcquireSRWLockExclusive(&lock);
  accesskit_action_request *request = NULL;
  if (count) {
    request = requests[0];
    for (unsigned int i = 1; i < count; i++) requests[i - 1] = requests[i];
    requests[--count] = NULL;
  }
  ReleaseSRWLockExclusive(&lock);
  return (uintptr_t)request;
}

int32_t metonic_accesskit_action(uintptr_t request) {
  return ((accesskit_action_request *)request)->action;
}

uint64_t metonic_accesskit_node(uintptr_t request) {
  return ((accesskit_action_request *)request)->target_node;
}

void metonic_accesskit_close(uintptr_t adapter) {
  AcquireSRWLockExclusive(&lock);
  target = NULL;
  while (count) accesskit_action_request_free(requests[--count]);
  ReleaseSRWLockExclusive(&lock);
  accesskit_windows_subclassing_adapter_free(
      (accesskit_windows_subclassing_adapter *)adapter);
}

void metonic_accesskit_bounds(uintptr_t node, double x, double y,
    double width, double height) {
  accesskit_rect rect = {x, y, x + width, y + height};
  accesskit_node_set_bounds((accesskit_node *)node, rect);
}
