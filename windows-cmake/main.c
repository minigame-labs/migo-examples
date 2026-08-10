/* A third-party host embedding Migo on Windows.
 *
 * The integration is the same shape as the Linux example: create an engine,
 * create a session, hand it a window you own, load content, run your own
 * message loop. Migo never creates a window and never takes over the main
 * thread -- it renders on its own thread against the surface you attach.
 *
 * Build it the way an integrator would, against an installed SDK:
 *
 *   cmake -S . -B build -DCMAKE_PREFIX_PATH=<sdk-prefix>
 *   cmake --build build --config Release
 *
 * See README.md for the full run instructions.
 */
#include <migo/migo.h>
/* Platform descriptors are opt-in headers: a host includes only the window
 * system it actually uses. */
#include <migo/platform/win32.h>

#include <windows.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int WINDOW_WIDTH = 720;
static const int WINDOW_HEIGHT = 1280;
/* Physical pixels per CSS pixel. Migo's input coordinates are CSS pixels, so a
 * host on a high-DPI display reports its real scale here and divides by it. */
static const float SCALE_FACTOR = 1.0f;

static volatile LONG g_content_ready;
static volatile LONG g_exit_requested;
static volatile LONG g_error_seen;
static volatile LONG g_resize_handling_enabled;
static volatile LONG g_window_width;
static volatile LONG g_window_height;

/* The engine never calls host code directly: it hands you a task and lets you
 * decide which thread runs it. Callbacks arrive on Migo's own threads, so a
 * real host would post the task to its UI thread. Running it inline is correct
 * here only because nothing in this example touches the window from a callback. */
static MigoResult MIGO_CALL dispatch_inline(void *dispatcher_context, MigoTaskFn task,
                                            void *task_context) {
    (void)dispatcher_context;
    task(task_context);
    return MIGO_OK;
}

static void MIGO_CALL on_ready(void *user_data, MigoSession *session) {
    (void)user_data;
    (void)session;
    InterlockedExchange(&g_content_ready, 1);
    /* Enable resize handling once content is ready. */
    InterlockedExchange(&g_resize_handling_enabled, 1);
    printf("[host] content is ready\n");
    fflush(stdout);
}

static void MIGO_CALL on_error(void *user_data, MigoSession *session,
                               const MigoError *error) {
    (void)user_data;
    (void)session;
    InterlockedExchange(&g_error_seen, 1);
    fprintf(stderr, "[host] *** ERROR ***: %s\n",
            (error && error->message_utf8) ? error->message_utf8 : "(no message)");
    fflush(stderr);
}

static void MIGO_CALL on_exit_requested(void *user_data, MigoSession *session) {
    (void)user_data;
    (void)session;
    InterlockedExchange(&g_exit_requested, 1);
    printf("[host] content asked to exit\n");
    fflush(stdout);
}

static int fail(const char *what, MigoResult result) {
    fprintf(stderr, "[host] %s failed: %d\n", what, (int)result);
    return 1;
}

/* Migo takes input in CSS pixels, so physical coordinates are divided by the
 * same scale factor reported at attach time. Getting this wrong renders
 * correctly and mis-places every click, which is why it is worth stating. */
static void send_touch(MigoSession *session, MigoTouchType type, int x, int y) {
    MigoTouchPoint point;
    memset(&point, 0, sizeof point);
    point.id = 0;
    point.x = (float)x / SCALE_FACTOR;
    point.y = (float)y / SCALE_FACTOR;
    point.pressure = 1.0f;

    MigoTouchEvent event;
    memset(&event, 0, sizeof event);
    event.struct_size = (uint32_t)sizeof event;
    event.abi_version = MIGO_ABI_VERSION_CURRENT;
    event.type = type;
    event.point_count = 1;
    event.points = &point;
    migo_session_send_touch(session, &event);
}

/* Detach, then wait for Migo to report the surface released. */
static int detach_and_await_release(MigoSurfaceAttachment *attachment) {
    MigoSurfaceRelease *release = NULL;
    MigoResult result = migo_surface_begin_detach(attachment, &release);
    if (result != MIGO_OK) return fail("migo_surface_begin_detach", result);

    for (int waited = 0; waited < 2000; waited += 10) {
        MigoSurfaceReleaseStatus status;
        memset(&status, 0, sizeof status);
        /* Output records mirror input ones: the caller declares the shape it
         * understands and the library writes no more than that. */
        status.struct_size = (uint32_t)sizeof status;
        status.abi_version = MIGO_ABI_VERSION_CURRENT;
        result = migo_surface_release_query(release, &status);
        if (result != MIGO_OK) return fail("migo_surface_release_query", result);
        if (status.state == MIGO_SURFACE_RELEASE_RELEASED) {
            return migo_surface_release_destroy(release) == MIGO_OK
                       ? 0
                       : fail("migo_surface_release_destroy", result);
        }
        Sleep(10);
    }
    /* Deliberately leaks the observer: it is the only thing that could still
     * report when the window becomes safe to destroy. */
    return fail("surface release timed out", MIGO_ERROR_INTERNAL);
}

static MigoSession *g_session;
static MigoSurfaceAttachment *g_attachment;
static LONG g_last_width;
static LONG g_last_height;

static LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
    case WM_LBUTTONDOWN:
        if (g_session) send_touch(g_session, MIGO_TOUCH_START, LOWORD(lparam), HIWORD(lparam));
        return 0;
    case WM_LBUTTONUP:
        if (g_session) send_touch(g_session, MIGO_TOUCH_END, LOWORD(lparam), HIWORD(lparam));
        return 0;
    case WM_SIZE: {
        int width = LOWORD(lparam);
        int height = HIWORD(lparam);
        InterlockedExchange(&g_window_width, width);
        InterlockedExchange(&g_window_height, height);
        return 0;
    }
    case WM_CLOSE:
        InterlockedExchange(&g_exit_requested, 1);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    default:
        return DefWindowProcA(hwnd, message, wparam, lparam);
    }
}

int main(int argc, char **argv) {
    const char *files_dir = (argc > 1) ? argv[1] : "C:\\Temp\\migo-windows-example\\files";
    const char *content_id = (argc > 2) ? argv[2] : "demo";
    const int seconds = (argc > 3) ? atoi(argv[3]) : 15;

    /* Initialize window dimensions. */
    InterlockedExchange(&g_window_width, WINDOW_WIDTH);
    InterlockedExchange(&g_window_height, WINDOW_HEIGHT);
    InterlockedExchange(&g_last_width, WINDOW_WIDTH);
    InterlockedExchange(&g_last_height, WINDOW_HEIGHT);

    /* ---- The window belongs to the host. Migo never creates one. ---- */
    HINSTANCE instance = GetModuleHandleA(NULL);
    WNDCLASSA window_class;
    memset(&window_class, 0, sizeof window_class);
    window_class.lpfnWndProc = window_proc;
    window_class.hInstance = instance;
    window_class.lpszClassName = "MigoExampleWindow";
    window_class.hCursor = LoadCursorA(NULL, IDC_ARROW);
    if (!RegisterClassA(&window_class)) {
        fprintf(stderr, "[host] RegisterClass failed: %lu\n", GetLastError());
        return 1;
    }
    HWND window = CreateWindowExA(0, window_class.lpszClassName, "migo windows example",
                                  WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                                  WINDOW_WIDTH, WINDOW_HEIGHT, NULL, NULL, instance, NULL);
    if (!window) {
        fprintf(stderr, "[host] CreateWindow failed: %lu\n", GetLastError());
        return 1;
    }
    ShowWindow(window, SW_SHOW);
    UpdateWindow(window);

    /* ---- Ask the linked library what it supports, before building on it. ----
     * The MIGO_C_ABI_* macros describe the headers this file compiled against;
     * only this call describes the library that actually got linked. */
    MigoCapabilities caps;
    memset(&caps, 0, sizeof caps);
    caps.struct_size = (uint32_t)sizeof caps;
    caps.abi_version = MIGO_ABI_VERSION_CURRENT;
    MigoResult result = migo_query_capabilities(&caps);
    if (result != MIGO_OK) return fail("migo_query_capabilities", result);
    printf("[host] migo abi %u..%u, platform kinds 0x%llx\n", caps.abi_version_min,
           caps.abi_version_max, (unsigned long long)caps.platform_kinds);
    if ((caps.platform_kinds & (UINT64_C(1) << MIGO_PLATFORM_WIN32_HWND)) == 0) {
        fprintf(stderr, "[host] this migo build cannot attach a Win32 HWND\n");
        return 1;
    }

    /* ---- Engine. The host names every storage root; Migo picks none. ---- */
    char cache_dir[512];
    char code_cache_dir[512];
    snprintf(cache_dir, sizeof cache_dir, "%s\\..\\cache", files_dir);
    snprintf(code_cache_dir, sizeof code_cache_dir, "%s\\..\\code-cache", files_dir);

    MigoEngineConfig engine_config;
    memset(&engine_config, 0, sizeof engine_config);
    engine_config.struct_size = (uint32_t)sizeof engine_config;
    engine_config.abi_version = MIGO_ABI_VERSION_CURRENT;
    /* The bundled example game carries no signing receipt. Production content
     * is signed and this flag is left off. */
    engine_config.flags = MIGO_ENGINE_FLAG_ALLOW_UNSIGNED_CONTENT;
    engine_config.files_dir_utf8 = files_dir;
    engine_config.cache_dir_utf8 = cache_dir;
    engine_config.code_cache_dir_utf8 = code_cache_dir;

    MigoEngine *engine = NULL;
    result = migo_engine_create(&engine_config, &engine);
    if (result != MIGO_OK) return fail("migo_engine_create", result);

    MigoSessionConfig session_config;
    memset(&session_config, 0, sizeof session_config);
    session_config.struct_size = (uint32_t)sizeof session_config;
    session_config.abi_version = MIGO_ABI_VERSION_CURRENT;
    session_config.flags = MIGO_SESSION_FLAG_NONE;

    MigoSession *session = NULL;
    result = migo_session_create(engine, &session_config, &session);
    if (result != MIGO_OK) return fail("migo_session_create", result);
    g_session = session;

    /* Callbacks install once, before the first attach: tasks already queued
     * would otherwise see a replaced function pointer. */
    MigoHostCallbacks callbacks;
    memset(&callbacks, 0, sizeof callbacks);
    callbacks.struct_size = (uint32_t)sizeof callbacks;
    callbacks.abi_version = MIGO_ABI_VERSION_CURRENT;
    callbacks.dispatch = dispatch_inline;
    callbacks.on_ready = on_ready;
    callbacks.on_error = on_error;
    callbacks.on_exit_requested = on_exit_requested;
    result = migo_session_set_host_callbacks(session, &callbacks);
    if (result != MIGO_OK) return fail("migo_session_set_host_callbacks", result);

    /* ---- Hand the window over as a typed platform descriptor. ----
     * Migo receives an opaque HWND and calls EGL through ANGLE; it never
     * destroys the window and never owns the message loop. */
    MigoWin32HwndDescriptor win32;
    memset(&win32, 0, sizeof win32);
    win32.struct_size = (uint32_t)sizeof win32;
    win32.abi_version = MIGO_ABI_VERSION_CURRENT;
    win32.platform_kind = MIGO_PLATFORM_WIN32_HWND;
    win32.flags = MIGO_PLATFORM_DESCRIPTOR_FLAG_NONE;
    win32.hwnd = window;

    MigoSurfaceDescriptor surface;
    memset(&surface, 0, sizeof surface);
    surface.struct_size = (uint32_t)sizeof surface;
    surface.abi_version = MIGO_ABI_VERSION_CURRENT;
    surface.generation = 1;
    surface.platform_kind = MIGO_PLATFORM_WIN32_HWND;
    surface.flags = MIGO_SURFACE_DESCRIPTOR_FLAG_NONE;
    surface.width_pixels = WINDOW_WIDTH;
    surface.height_pixels = WINDOW_HEIGHT;
    surface.scale_factor = SCALE_FACTOR;
    surface.color_space = MIGO_COLOR_SPACE_SRGB;
    surface.alpha_mode = MIGO_ALPHA_MODE_OPAQUE;
    surface.preferred_presentation_mode = MIGO_PRESENTATION_MODE_DEFAULT;
    surface.capability_flags = MIGO_SURFACE_CAPABILITY_NONE;
    surface.platform_descriptor_size = (uint32_t)sizeof win32;
    surface.platform_descriptor = &win32;

    result = migo_session_attach_surface(session, &surface, &g_attachment);
    if (result != MIGO_OK) return fail("migo_session_attach_surface", result);

    /* Sync resize tracking with actual attached dimensions to avoid spurious resize
     * detection caused by window system rounding or DPI adjustments. */
    RECT rect;
    if (GetClientRect(window, &rect)) {
        LONG actual_width = rect.right - rect.left;
        LONG actual_height = rect.bottom - rect.top;
        InterlockedExchange(&g_window_width, actual_width);
        InterlockedExchange(&g_window_height, actual_height);
        InterlockedExchange(&g_last_width, actual_width);
        InterlockedExchange(&g_last_height, actual_height);
    }

    MigoContentDescriptor content;
    memset(&content, 0, sizeof content);
    content.struct_size = (uint32_t)sizeof content;
    content.abi_version = MIGO_ABI_VERSION_CURRENT;
    content.flags = MIGO_CONTENT_FLAG_NONE;
    content.content_id_utf8 = content_id;
    content.entry_utf8 = "game.js";

    result = migo_session_load_content(session, &content);
    if (result != MIGO_OK) return fail("migo_session_load_content", result);

    printf("[host] running '%s' for %ds in HWND %p\n", content_id, seconds, (void *)window);
    fflush(stdout);

    /* ---- The host owns the message loop; Migo renders on its own thread. ---- */
    DWORD deadline = GetTickCount() + (DWORD)seconds * 1000;
    while (GetTickCount() < deadline && !InterlockedCompareExchange(&g_exit_requested, 0, 0)) {
        MSG message;
        while (PeekMessageA(&message, NULL, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) {
                InterlockedExchange(&g_exit_requested, 1);
                break;
            }
            TranslateMessage(&message);
            DispatchMessageA(&message);
        }

        /* Handle window resize by reattaching with new dimensions.
         * Only enabled after content is ready to avoid breaking initial setup. */
        if (InterlockedCompareExchange(&g_resize_handling_enabled, 0, 0)) {
            LONG current_width = InterlockedCompareExchange(&g_window_width, 0, 0);
            LONG current_height = InterlockedCompareExchange(&g_window_height, 0, 0);
            if (current_width != g_last_width || current_height != g_last_height) {
                if (current_width > 0 && current_height > 0) {
                    printf("[host] window resized to %ldx%ld\n", current_width, current_height);
                    fflush(stdout);

                    /* Detach old surface before attaching new one. */
                    if (g_attachment) {
                        if (detach_and_await_release(g_attachment) != 0) {
                            fprintf(stderr, "[host] detach after resize failed\n");
                            fflush(stderr);
                            g_attachment = NULL;
                        } else {
                            g_attachment = NULL;
                        }
                    }

                    /* Reattach with new dimensions. */
                    MigoWin32HwndDescriptor win32;
                    memset(&win32, 0, sizeof win32);
                    win32.struct_size = (uint32_t)sizeof win32;
                    win32.abi_version = MIGO_ABI_VERSION_CURRENT;
                    win32.platform_kind = MIGO_PLATFORM_WIN32_HWND;
                    win32.flags = MIGO_PLATFORM_DESCRIPTOR_FLAG_NONE;
                    win32.hwnd = window;

                    MigoSurfaceDescriptor new_surface;
                    memset(&new_surface, 0, sizeof new_surface);
                    new_surface.struct_size = (uint32_t)sizeof new_surface;
                    new_surface.abi_version = MIGO_ABI_VERSION_CURRENT;
                    new_surface.generation = 2;
                    new_surface.platform_kind = MIGO_PLATFORM_WIN32_HWND;
                    new_surface.flags = MIGO_SURFACE_DESCRIPTOR_FLAG_NONE;
                    new_surface.width_pixels = current_width;
                    new_surface.height_pixels = current_height;
                    new_surface.scale_factor = SCALE_FACTOR;
                    new_surface.color_space = MIGO_COLOR_SPACE_SRGB;
                    new_surface.alpha_mode = MIGO_ALPHA_MODE_OPAQUE;
                    new_surface.preferred_presentation_mode = MIGO_PRESENTATION_MODE_DEFAULT;
                    new_surface.capability_flags = MIGO_SURFACE_CAPABILITY_NONE;
                    new_surface.platform_descriptor_size = (uint32_t)sizeof win32;
                    new_surface.platform_descriptor = &win32;

                    result = migo_session_attach_surface(session, &new_surface, &g_attachment);
                    if (result != MIGO_OK) {
                        fprintf(stderr, "[host] reattach after resize failed: %d\n", (int)result);
                        fflush(stderr);
                    } else {
                        g_last_width = current_width;
                        g_last_height = current_height;
                    }
                }
            }
        }

        Sleep(16);
    }

    /* ---- Tear down in reverse. ----
     * Detaching is asynchronous and that is load-bearing: the render thread may
     * still be reading the window. Destroying it before the release reports
     * RELEASED is a use-after-free in the driver, not a tidiness issue. */
    int detach_failed = (g_attachment != NULL) ? detach_and_await_release(g_attachment) : 0;
    g_session = NULL;
    migo_session_destroy(session);
    migo_engine_destroy(engine);
    if (!detach_failed) DestroyWindow(window);

    /* Report what happened in the exit code. Without this a host whose content
     * failed to load still exits 0: the window opened, the engine started and
     * the loop ran its course -- every step this program controls succeeded.
     * Only the callbacks know the content never came up. */
    if (detach_failed) return 1;
    if (InterlockedCompareExchange(&g_error_seen, 0, 0)) {
        fprintf(stderr, "[host] exiting non-zero: the engine reported an error\n");
        return 1;
    }
    if (!InterlockedCompareExchange(&g_content_ready, 0, 0)) {
        fprintf(stderr, "[host] exiting non-zero: content never became ready\n");
        return 1;
    }
    printf("[host] done\n");
    return 0;
}
