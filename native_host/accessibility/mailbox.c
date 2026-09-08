#include <windows.h>
#include <stdint.h>
#include <string.h>
#include "accesskit.h"
#pragma comment(lib, "accesskit.lib")

/* MoonBit's GC objects cannot be the cross-thread queue. Keep request ownership
   here; platform structs never enter the shared semantic model. */
static SRWLOCK lock = SRWLOCK_INIT;
static accesskit_action_request *requests[32];
static unsigned int count;
static uintptr_t generation;
static HWND target;

static int selection_request(const accesskit_action_request *request) {
  return request->action == ACCESSKIT_ACTION_SET_TEXT_SELECTION &&
      request->data.has_value &&
      request->data.value.tag == ACCESSKIT_ACTION_DATA_SET_TEXT_SELECTION;
}

static int32_t value_length(const accesskit_action_request *request) {
  if (request->action != ACCESSKIT_ACTION_SET_VALUE || !request->data.has_value ||
      request->data.value.tag != ACCESSKIT_ACTION_DATA_VALUE ||
      !request->data.value.value) return -1;
  size_t length = strnlen(request->data.value.value, 65537);
  return length <= 65536 ? (int32_t)length : -1;
}

static void receive(accesskit_action_request *request, void *userdata) {
  AcquireSRWLockExclusive(&lock);
  if (target && (uintptr_t)userdata == generation && count < 32 &&
      (request->action == ACCESSKIT_ACTION_CLICK ||
       request->action == ACCESSKIT_ACTION_FOCUS || value_length(request) >= 0 ||
       selection_request(request))) {
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
  switch (((accesskit_action_request *)request)->action) {
    case ACCESSKIT_ACTION_CLICK: return 0;
    case ACCESSKIT_ACTION_FOCUS: return 1;
    case ACCESSKIT_ACTION_SET_VALUE: return 2;
    case ACCESSKIT_ACTION_SET_TEXT_SELECTION: return 3;
    default: return -1;
  }
}

uint64_t metonic_accesskit_selection_field(uintptr_t pointer, int32_t field) {
  const accesskit_action_request *request = (accesskit_action_request *)pointer;
  if (!selection_request(request)) return UINT64_MAX;
  const accesskit_text_selection *selection = &request->data.value.set_text_selection;
  switch (field) {
    case 0: return selection->anchor.node;
    case 1: return selection->anchor.character_index;
    case 2: return selection->focus.node;
    case 3: return selection->focus.character_index;
    default: return UINT64_MAX;
  }
}

void metonic_accesskit_selection(uintptr_t node, uint64_t anchor_node,
    uint64_t anchor_index, uint64_t focus_node, uint64_t focus_index) {
  accesskit_text_selection selection = {
    {anchor_node, (size_t)anchor_index}, {focus_node, (size_t)focus_index}
  };
  accesskit_node_set_text_selection((accesskit_node *)node, selection);
  accesskit_node_add_action((accesskit_node *)node, ACCESSKIT_ACTION_SET_TEXT_SELECTION);
}

void metonic_accesskit_value_action(uintptr_t node) {
  accesskit_node_add_action((accesskit_node *)node, ACCESSKIT_ACTION_SET_VALUE);
}

int32_t metonic_accesskit_value_length(uintptr_t request) {
  return value_length((accesskit_action_request *)request);
}

int32_t metonic_accesskit_copy_value(uintptr_t request, uint8_t *output,
    int32_t capacity) {
  int32_t length = value_length((accesskit_action_request *)request);
  if (length < 0 || capacity != length) return 0;
  memcpy(output, ((accesskit_action_request *)request)->data.value.value, length);
  return 1;
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
