// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
