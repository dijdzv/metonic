#ifndef METONIC_ASYNC_WORKERS_H
#define METONIC_ASYNC_WORKERS_H

#include <process.h>

typedef struct {
  HANDLE thread;
  HANDLE cancel;
  HWND target;
  int32_t id;
  int32_t delay;
  int32_t value;
  int32_t fail;
  int used;
} AsyncSlot;

static AsyncSlot async_slots[16];
static volatile LONG async_closing;
static int32_t async_shutdown_duration;

static unsigned __stdcall async_worker(void *argument) {
  int index = (int)(intptr_t)argument;
  AsyncSlot *slot = &async_slots[index];
  DWORD result = WaitForSingleObject(slot->cancel, (DWORD)slot->delay);
  if (result == WAIT_TIMEOUT) {
    if (!PostMessageW(slot->target, WM_APP + 1, (WPARAM)index, 0)) InterlockedExchange(&ring_failed, 1);
  } else if (result != WAIT_OBJECT_0) {
    InterlockedExchange(&ring_failed, 1);
  }
  return 0;
}

static void async_deliver(int32_t index) {
  if (index < 0 || index >= 16 || !async_slots[index].used) {
    InterlockedExchange(&ring_failed, 1);
    return;
  }
  AsyncSlot *slot = &async_slots[index];
  if (WaitForSingleObject(slot->thread, INFINITE) != WAIT_OBJECT_0) {
    InterlockedExchange(&ring_failed, 1);
    return;
  }
  CloseHandle(slot->thread);
  CloseHandle(slot->cancel);
  if (!slot->fail) enqueue(6, slot->id, slot->value);
  else enqueue(7, slot->id, slot->value);
  slot->thread = NULL;
  slot->cancel = NULL;
  slot->used = 0;
}

__declspec(dllexport) int32_t metonic_async_start(int32_t id, int32_t delay, int32_t value, int32_t fail) {
  if (!window_handle || async_closing || id <= 0 || delay < 1 || delay > 5000 || fail < 0 || fail > 1) return -1;
  int index = -1;
  for (int i = 0; i < 16; i++) if (!async_slots[i].used) { index = i; break; }
  if (index < 0) return -1;
  AsyncSlot *slot = &async_slots[index];
  slot->target = window_handle;
  slot->id = id;
  slot->delay = delay;
  slot->value = value;
  slot->fail = fail;
  slot->used = 1;
  slot->cancel = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (!slot->cancel) { slot->used = 0; return -1; }
  slot->thread = (HANDLE)_beginthreadex(NULL, 0, async_worker, (void *)(intptr_t)index, 0, NULL);
  if (!slot->thread) { CloseHandle(slot->cancel); slot->cancel = NULL; slot->used = 0; return -1; }
  return 0;
}

__declspec(dllexport) int32_t metonic_async_pending(void) {
  int count = 0;
  for (int i = 0; i < 16; i++) if (async_slots[i].used) count++;
  return count;
}

__declspec(dllexport) void metonic_async_shutdown(void) {
  if (InterlockedExchange(&async_closing, 1)) return;
  ULONGLONG started = GetTickCount64();
  for (int i = 0; i < 16; i++) if (async_slots[i].used) SetEvent(async_slots[i].cancel);
  for (int i = 0; i < 16; i++) if (async_slots[i].used) {
    if (WaitForSingleObject(async_slots[i].thread, INFINITE) != WAIT_OBJECT_0) {
      InterlockedExchange(&ring_failed, 1);
      continue;
    }
    CloseHandle(async_slots[i].thread);
    CloseHandle(async_slots[i].cancel);
    async_slots[i].thread = NULL;
    async_slots[i].cancel = NULL;
    async_slots[i].used = 0;
  }
  async_shutdown_duration = (int32_t)(GetTickCount64() - started);
}

__declspec(dllexport) int32_t metonic_async_shutdown_elapsed(void) { return async_shutdown_duration; }

#endif
