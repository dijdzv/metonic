#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "moonbit.h"

#ifndef MOONBIT_FFI_EXPORT
#define MOONBIT_FFI_EXPORT __declspec(dllexport)
#endif

static int32_t read_status;
static HMODULE gpu_library;
static void *gpu_context;
typedef void *(__cdecl *gpu_create_fn)(int32_t);
typedef int32_t (__cdecl *gpu_render_fn)(void *, int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, int32_t, uint8_t *, size_t);
typedef int32_t (__cdecl *gpu_info_fn)(void *, char *, size_t);
typedef void (__cdecl *gpu_destroy_fn)(void *);
static gpu_create_fn gpu_create;
static gpu_render_fn gpu_render;
static gpu_info_fn gpu_info;
static gpu_destroy_fn gpu_destroy;

static int absolute_path(const wchar_t *path) {
    return path && ((((path[0] >= L'A' && path[0] <= L'Z') || (path[0] >= L'a' && path[0] <= L'z')) && path[1] == L':' && (path[2] == L'\\' || path[2] == L'/')) || (path[0] == L'\\' && path[1] == L'\\'));
}

MOONBIT_FFI_EXPORT int32_t metonic_read_status(void) { return read_status; }

MOONBIT_FFI_EXPORT moonbit_string_t metonic_read_line(void) {
    char buffer[4096];
    size_t length = 0;
    int oversized = 0;
    int c;
    read_status = 0;
    while ((c = fgetc(stdin)) != EOF && c != '\n') {
        if (length < sizeof(buffer) - 1) buffer[length++] = (char)c;
        else oversized = 1;
    }
    if (c == EOF && length == 0) { read_status = 1; return moonbit_make_string(0, 0); }
    if (oversized) { read_status = 2; return moonbit_make_string(0, 0); }
    if (length && buffer[length - 1] == '\r') --length;
    if (length == 0) { read_status = 0; return moonbit_make_string(0, 0); }
    buffer[length] = 0;
    int wide_len = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, buffer, (int)length, NULL, 0);
    if (wide_len <= 0) { read_status = 3; return moonbit_make_string(0, 0); }
    wchar_t *wide = (wchar_t *)malloc((size_t)wide_len * sizeof(wchar_t));
    if (!wide) { read_status = 3; return moonbit_make_string(0, 0); }
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, buffer, (int)length, wide, wide_len);
    moonbit_string_t result = moonbit_make_string_raw((size_t)wide_len);
    memcpy(result, wide, (size_t)wide_len * sizeof(wchar_t));
    free(wide);
    read_status = (read_status == 2) ? 2 : 0;
    return result;
}

MOONBIT_FFI_EXPORT int32_t metonic_write_line(moonbit_string_t text) {
    size_t length = Moonbit_array_length(text);
    int bytes = WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)text, (int)length, NULL, 0, NULL, NULL);
    if (length && bytes <= 0) return -1;
    char *utf8 = (char *)malloc((size_t)bytes + 1);
    if (!utf8) return -1;
    if (bytes && WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)text, (int)length, utf8, bytes, NULL, NULL) <= 0) { free(utf8); return -1; }
    utf8[bytes] = '\n';
    int32_t result = (fwrite(utf8, 1, (size_t)bytes + 1, stdout) == (size_t)bytes + 1 && fflush(stdout) == 0) ? 0 : -1;
    free(utf8);
    return result;
}

static int load_gpu(void) {
    if (gpu_library) return gpu_context != NULL;
    wchar_t path[32768];
    DWORD n = GetEnvironmentVariableW(L"METONIC_GPU_BRIDGE", path, 32768);
    if (!n || n >= 32768 || !absolute_path(path)) return 0;
    gpu_library = LoadLibraryExW(path, NULL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!gpu_library) return 0;
    gpu_create = (gpu_create_fn)GetProcAddress(gpu_library, "metonic_gpu_create");
    gpu_render = (gpu_render_fn)GetProcAddress(gpu_library, "metonic_gpu_render");
    gpu_info = (gpu_info_fn)GetProcAddress(gpu_library, "metonic_gpu_info");
    gpu_destroy = (gpu_destroy_fn)GetProcAddress(gpu_library, "metonic_gpu_destroy");
    if (!gpu_create || !gpu_render || !gpu_info || !gpu_destroy) return 0;
    int fallback = 0; wchar_t value[8];
    n = GetEnvironmentVariableW(L"METONIC_GPU_FALLBACK", value, 8);
    if (n == 1 && value[0] == L'1') fallback = 1;
    gpu_context = gpu_create(fallback);
    if (gpu_context) { char info[256] = {0}; gpu_info(gpu_context, info, sizeof(info)); fprintf(stderr, "%s\n", info); }
    return gpu_context != NULL;
}

MOONBIT_FFI_EXPORT int32_t metonic_capture(int32_t width, int32_t height, int32_t x, int32_t y, int32_t w, int32_t h, int32_t active) {
    if (width < 1 || width > 2048 || height < 1 || height > 2048 || x < 0 || y < 0 || w < 1 || h < 1 || x > width || y > height || w > width - x || h > height - y) return -1;
    wchar_t path[32768];
    DWORD n = GetEnvironmentVariableW(L"METONIC_CAPTURE_PATH", path, 32768);
    if (!n || n >= 32768 || !absolute_path(path)) return -1;
    if (!load_gpu()) return -1;
    size_t bytes = (size_t)width * (size_t)height * 4;
    uint8_t *pixels = (uint8_t *)malloc(bytes);
    if (!pixels) return -1;
    int32_t result = gpu_render(gpu_context, width, height, x, y, w, h, active, pixels, bytes);
    if (result == 0) {
        FILE *file = _wfopen(path, L"wb");
        if (file) {
            int write_ok = fwrite(pixels, 1, bytes, file) == bytes;
            int close_ok = fclose(file) == 0;
            result = (write_ok && close_ok) ? 0 : -1;
        } else result = -1;
    }
    free(pixels);
    if (result) fprintf(stderr, "native capture failed\n");
    return result;
}

MOONBIT_FFI_EXPORT void metonic_finish(void) {
    if (gpu_context && gpu_destroy) gpu_destroy(gpu_context);
    gpu_context = NULL; gpu_create = NULL; gpu_render = NULL; gpu_info = NULL; gpu_destroy = NULL;
    if (gpu_library) FreeLibrary(gpu_library);
    gpu_library = NULL;
}
