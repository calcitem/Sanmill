// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// flutter_window.h

#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "run_loop.h"
#include "win32_window.h"

#include "mill_engine.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window
{
public:
    // Creates a new FlutterWindow driven by the |run_loop|, hosting a
    // Flutter view running |project|.
    explicit FlutterWindow(RunLoop *run_loop,
                           const flutter::DartProject &project);
    virtual ~FlutterWindow();

protected:
    // Win32Window:
    bool OnCreate() override;
    void OnDestroy() override;
    LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                           LPARAM const lparam) noexcept override;

private:
    // The run loop driving events for this window.
    RunLoop *run_loop_;

    // The project to run.
    flutter::DartProject project_;

    // The Flutter instance hosted by this window.
    std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

    // Mill Engine
    MillEngine *engine {nullptr};

    // Called when a method is called on plugin channel;
    void HandleMethodCall(const flutter::MethodCall<> &method_call,
                          std::unique_ptr<flutter::MethodResult<>> result);

    // Initializes the method channels for this window.
    void InitializeMethodChannels();
};

#endif // RUNNER_FLUTTER_WINDOW_H_
