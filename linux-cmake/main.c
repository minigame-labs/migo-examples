/* A third-party host embedding Migo on Linux.
 *
 * This is the whole integration: create an engine, create a session, hand it a
 * window you own, load content, and run your own event loop. Migo never creates
 * a window and never takes over the main thread -- it renders on its own thread
 * against the surface you attach.
 *
 * Build it the way an integrator would, against an installed SDK:
 *
 *   cmake -S . -B build -DCMAKE_PREFIX_PATH=<sdk-prefix>
 *   cmake --build build
 *
 * See README.md for the full run instructions.
 */
#include <X11/Xlib.h>
#include <migo/migo.h>
/* Platform descriptors are opt-in headers: a host includes only the window
 * system it actually uses. */
#include <migo/platform/x11.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const int WINDOW_WIDTH = 720;
static const int WINDOW_HEIGHT = 1280;
/* Physical pixels per CSS pixel. Migo's input coordinates are CSS pixels, so a
 * host on a HiDPI screen reports its real scale here and divides by it below. */
static const float SCALE_FACTOR = 1.0f;

static atomic_int g_content_ready;
static atomic_int g_exit_requested;
static atomic_int g_error_seen;
static atomic_int g_resize_pending;
static _Atomic(int) g_pending_width;
static _Atomic(int) g_pending_height;

/* The engine never calls host code directly: it hands you a task and lets you
 * decide which thread runs it. Callbacks arrive on Migo's own threads, so a
 * real host would post the task to its UI loop. Running it inline is correct
 * here only because nothing in this example touches X from a callback. */
static MigoResult MIGO_CALL dispatch_inline(void *dispatcher_context, MigoTaskFn task,
                                            void *task_context) {
    (void)dispatcher_context;
    task(task_context);
    return MIGO_OK;
}

static void MIGO_CALL on_ready(void *user_data, MigoSession *session) {
    (void)user_data;
    (void)session;
    atomic_store(&g_content_ready, 1);
    printf("[host] content is ready\n");
    fflush(stdout);
}

static void MIGO_CALL on_error(void *user_data, MigoSession *session,
                               const MigoError *error) {
    (void)user_data;
    (void)session;
    atomic_store(&g_error_seen, 1);
    fprintf(stderr, "[host] error: %s\n",
            (error && error->message_utf8) ? error->message_utf8 : "(no message)");
}

static void MIGO_CALL on_exit_requested(void *user_data, MigoSession *session) {
    (void)user_data;
    (void)session;
    atomic_store(&g_exit_requested, 1);
    printf("[host] content asked to exit\n");
    fflush(stdout);
}

static int fail(const char *what, MigoResult result) {
    fprintf(stderr, "[host] %s failed: %d\n", what, (int)result);
    return 1;
}

static void sleep_ms(long ms) {
    struct timespec ts = {ms / 1000, (ms % 1000) * 1000000L};
    nanosleep(&ts, NULL);
}

/* Migo takes input in CSS pixels, so physical coordinates are divided by the
 * same scale factor reported at attach time. Getting this wrong renders
 * correctly and mis-places every tap, which is why it is worth stating. */
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

/* Send a resize update to Migo with new surface metrics.
 * Resize is handled via migo_surface_update, which is non-blocking. */
static int handle_resize(MigoSurfaceAttachment *attachment, int width, int height) {
    if (!attachment || width <= 0 || height <= 0) return 0;

    MigoSurfaceMetrics metrics;
    memset(&metrics, 0, sizeof metrics);
    metrics.struct_size = (uint32_t)sizeof metrics;
    metrics.abi_version = MIGO_ABI_VERSION_CURRENT;
    metrics.generation = 1;
    metrics.width_pixels = (uint32_t)width;
    metrics.height_pixels = (uint32_t)height;
    metrics.scale_factor = SCALE_FACTOR;

    MigoResult result = migo_surface_update(attachment, &metrics);
    if (result != MIGO_OK) {
        fprintf(stderr, "[host] resize to %dx%d failed: %d\n", width, height, (int)result);
        return 1;
    }
    printf("[host] resized to %dx%d\n", width, height);
    return 0;
}

/* Detach, then wait for Migo to report the surface released. */
static int detach_and_await_release(MigoSurfaceAttachment *attachment) {
    MigoSurfaceRelease *release = NULL;
    MigoResult result = migo_surface_begin_detach(attachment, &release);
    if (result != MIGO_OK) return fail("migo_surface_begin_detach", result);

    for (long waited = 0; waited < 2000; waited += 10) {
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
        sleep_ms(10);
    }
    /* Deliberately leaks the observer: it is the only thing that could still
     * report when the window becomes safe to touch. */
    return fail("surface release timed out", MIGO_ERROR_INTERNAL);
}

int main(int argc, char **argv) {
    const char *files_dir = (argc > 1) ? argv[1] : "/tmp/migo-linux-example/files";
    const char *content_id = (argc > 2) ? argv[2] : "demo";
    const int seconds = (argc > 3) ? atoi(argv[3]) : 15;

    /* ---- The window belongs to the host. Migo never creates one. ----
     * XInitThreads is required, not optional: Migo's render thread uses this
     * same Display connection. */
    if (!XInitThreads()) {
        fprintf(stderr, "[host] XInitThreads failed\n");
        return 1;
    }
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "[host] XOpenDisplay failed (DISPLAY=%s)\n",
                getenv("DISPLAY") ? getenv("DISPLAY") : "(unset)");
        return 1;
    }
    int screen = DefaultScreen(display);
    Window window = XCreateSimpleWindow(
        display, RootWindow(display, screen), 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, 0,
        BlackPixel(display, screen), BlackPixel(display, screen));
    XStoreName(display, window, "migo linux example");
    /* Listen for structure changes (resize) and button input. */
    XSelectInput(display, window,
                 StructureNotifyMask | ButtonPressMask | ButtonReleaseMask);
    Atom wm_delete = XInternAtom(display, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(display, window, &wm_delete, 1);
    XMapWindow(display, window);
    XFlush(display);

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
    if ((caps.platform_kinds & (UINT64_C(1) << MIGO_PLATFORM_X11_WINDOW)) == 0) {
        fprintf(stderr, "[host] this migo build cannot attach an X11 window\n");
        return 1;
    }

    /* ---- Engine. The host names every storage root; Migo picks none. ---- */
    char cache_dir[512];
    char code_cache_dir[512];
    snprintf(cache_dir, sizeof cache_dir, "%s/../cache", files_dir);
    snprintf(code_cache_dir, sizeof code_cache_dir, "%s/../code-cache", files_dir);

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
     * Migo receives opaque handles and calls EGL; it links no Xlib itself. */
    MigoX11WindowDescriptor x11;
    memset(&x11, 0, sizeof x11);
    x11.struct_size = (uint32_t)sizeof x11;
    x11.abi_version = MIGO_ABI_VERSION_CURRENT;
    x11.platform_kind = MIGO_PLATFORM_X11_WINDOW;
    x11.flags = MIGO_PLATFORM_DESCRIPTOR_FLAG_NONE;
    x11.display = display;
    x11.window = (uintptr_t)window;
    x11.screen = screen;

    MigoSurfaceDescriptor surface;
    memset(&surface, 0, sizeof surface);
    surface.struct_size = (uint32_t)sizeof surface;
    surface.abi_version = MIGO_ABI_VERSION_CURRENT;
    surface.generation = 1;
    surface.platform_kind = MIGO_PLATFORM_X11_WINDOW;
    surface.flags = MIGO_SURFACE_DESCRIPTOR_FLAG_NONE;
    surface.width_pixels = WINDOW_WIDTH;
    surface.height_pixels = WINDOW_HEIGHT;
    surface.scale_factor = SCALE_FACTOR;
    surface.color_space = MIGO_COLOR_SPACE_SRGB;
    surface.alpha_mode = MIGO_ALPHA_MODE_OPAQUE;
    surface.preferred_presentation_mode = MIGO_PRESENTATION_MODE_DEFAULT;
    surface.capability_flags = MIGO_SURFACE_CAPABILITY_NONE;
    surface.platform_descriptor_size = (uint32_t)sizeof x11;
    surface.platform_descriptor = &x11;

    MigoSurfaceAttachment *attachment = NULL;
    result = migo_session_attach_surface(session, &surface, &attachment);
    if (result != MIGO_OK) return fail("migo_session_attach_surface", result);

    MigoContentDescriptor content;
    memset(&content, 0, sizeof content);
    content.struct_size = (uint32_t)sizeof content;
    content.abi_version = MIGO_ABI_VERSION_CURRENT;
    content.flags = MIGO_CONTENT_FLAG_NONE;
    content.content_id_utf8 = content_id;
    content.entry_utf8 = "game.js";

    result = migo_session_load_content(session, &content);
    if (result != MIGO_OK) return fail("migo_session_load_content", result);

    printf("[host] running '%s' for %ds in window 0x%lx\n", content_id, seconds,
           (unsigned long)window);
    fflush(stdout);

    /* ---- The host owns the event loop; Migo renders on its own thread. ---- */
    int current_width = WINDOW_WIDTH;
    int current_height = WINDOW_HEIGHT;
    atomic_store(&g_pending_width, current_width);
    atomic_store(&g_pending_height, current_height);

    for (int elapsed = 0; elapsed < seconds * 1000; elapsed += 16) {
        while (XPending(display) > 0) {
            XEvent event;
            XNextEvent(display, &event);
            if (event.type == ClientMessage &&
                (Atom)event.xclient.data.l[0] == wm_delete) {
                printf("[host] window close requested\n");
                elapsed = seconds * 1000;
                break;
            }
            if (event.type == ConfigureNotify) {
                int new_width = event.xconfigure.width;
                int new_height = event.xconfigure.height;
                atomic_store(&g_pending_width, new_width);
                atomic_store(&g_pending_height, new_height);
                atomic_store(&g_resize_pending, 1);
            }
            if (event.type == ButtonPress && event.xbutton.button == Button1) {
                send_touch(session, MIGO_TOUCH_START, event.xbutton.x, event.xbutton.y);
            } else if (event.type == ButtonRelease && event.xbutton.button == Button1) {
                send_touch(session, MIGO_TOUCH_END, event.xbutton.x, event.xbutton.y);
            }
        }

        /* Process pending resize if dimensions changed. */
        if (atomic_exchange(&g_resize_pending, 0)) {
            int new_width = atomic_load(&g_pending_width);
            int new_height = atomic_load(&g_pending_height);
            if (new_width != current_width || new_height != current_height) {
                handle_resize(attachment, new_width, new_height);
                current_width = new_width;
                current_height = new_height;
            }
        }

        if (atomic_load(&g_exit_requested)) break;
        sleep_ms(16);
    }

    /* ---- Tear down in reverse. ----
     * Detaching is asynchronous and that is load-bearing: the render thread may
     * still be reading the window. Destroying it before the release reports
     * RELEASED is a use-after-free in the driver, not a tidiness issue. */
    if (detach_and_await_release(attachment) != 0) {
        /* The window must now outlive this process rather than be torn down
         * while the driver may still read it. */
        migo_session_destroy(session);
        migo_engine_destroy(engine);
        return 1;
    }
    migo_session_destroy(session);
    migo_engine_destroy(engine);
    XDestroyWindow(display, window);
    XCloseDisplay(display);

    /* Report what happened in the exit code. Without this a host whose content
     * failed to load still exits 0: the window opened, the engine started and
     * the loop ran its course -- every step this program controls succeeded.
     * Only the callbacks know the content never came up, so they have to be
     * what decides the status. A supervisor, a CI job or a script running this
     * has nothing else to go on. */
    if (atomic_load(&g_error_seen)) {
        fprintf(stderr, "[host] exiting non-zero: the engine reported an error\n");
        return 1;
    }
    if (!atomic_load(&g_content_ready)) {
        fprintf(stderr, "[host] exiting non-zero: content never became ready\n");
        return 1;
    }
    printf("[host] done\n");
    return 0;
}
