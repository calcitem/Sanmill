// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

#include "my_application.h"

#include <cassert>

#ifdef GDK_WINDOWING_X11
#include <X11/Xlib.h>
#endif

int main(int argc, char** argv) {
#ifdef GDK_WINDOWING_X11
    // Flutter's Linux embedder may access X11 from multiple threads.
    const int x11_threads_initialized = XInitThreads();
    assert(x11_threads_initialized != 0);
#endif
    g_autoptr(MyApplication) app = my_application_new();
    return g_application_run(G_APPLICATION(app), argc, argv);
}
