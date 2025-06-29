// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// main.cpp

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "run_loop.h"
#include "utils.h"
#include "perfect/perfect_api.h"
#include "perfect/perfect_errors.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
    // Attach to console when present (e.g., 'flutter run') or create a
    // new console when running with a debugger.
    if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
        CreateAndAttachConsole();
    }

    // Initialize Perfect error handling for the main UI thread
    // Note: Engine thread initialization is handled separately in engine core
    PerfectErrors::initialize_thread_local_storage();

    // Initialize COM, so that it is available for use in the library and/or
    // plugins.
    ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    RunLoop run_loop;

    flutter::DartProject project(L"data");

    std::vector<std::string> command_line_arguments = GetCommandLineArguments();

    project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

    FlutterWindow window(&run_loop, project);
    Win32Window::Point origin(10, 10);
    Win32Window::Size size(428, 926);
    if (!window.CreateAndShow(L"Mill (N Men's Morris)", origin, size)) {
        return EXIT_FAILURE;
    }
    window.SetQuitOnClose(true);

    run_loop.Run();

    ::CoUninitialize();

    // Cleanup Perfect error handling for the main UI thread
    PerfectErrors::cleanup_thread_local_storage();
    
    return EXIT_SUCCESS;
}
