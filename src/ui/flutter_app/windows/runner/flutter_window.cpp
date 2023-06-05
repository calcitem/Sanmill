// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

#include "flutter_window.h"

#include <memory>
#include <optional>
#include <sstream>
#include <string>

// TODO
#include "perfect_adaptor.h"

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(RunLoop *run_loop,
                             const flutter::DartProject &project)
    : run_loop_(run_loop)
    , project_(project)
{ }

FlutterWindow::~FlutterWindow()
{
    if (engine != nullptr) {
        engine->shutdown();
        delete engine;
        engine = nullptr;
    }
}

bool FlutterWindow::OnCreate()
{
    if (!Win32Window::OnCreate()) {
        return false;
    }

    RECT frame = GetClientArea();

    // The size here must match the window dimensions to avoid unnecessary
    // surface creation / destruction in the startup path.
    flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
        frame.right - frame.left, frame.bottom - frame.top, project_);
    // Ensure that basic setup of the controller was successful.
    if (!flutter_controller_->engine() || !flutter_controller_->view()) {
        return false;
    }
    RegisterPlugins(flutter_controller_->engine());

    if (engine == nullptr) {
        engine = new MillEngine();

        auto channel = std::make_unique<flutter::MethodChannel<>>(
            flutter_controller_->engine()->messenger(),
            "com.calcitem.sanmill/engine",
            &flutter::StandardMethodCodec::GetInstance());

        channel->SetMethodCallHandler([this](const auto &call, auto result) {
            HandleMethodCall(call, std::move(result));
        });
    }

    run_loop_->RegisterFlutterInstance(flutter_controller_->engine());
    SetChildContent(flutter_controller_->view()->GetNativeWindow());

    perfect_reset();  // TODO

    return true;
}

void FlutterWindow::HandleMethodCall(
    const flutter::MethodCall<> &method_call,
    std::unique_ptr<flutter::MethodResult<>> result)
{
    const std::string &method = method_call.method_name();

    if (method.compare("startup") == 0) {
        result->Success(engine->startup());
    } else if (method_call.method_name().compare("send") == 0) {
        const auto &args = std::get<std::string>(*method_call.arguments());
        result->Success(engine->send(args.c_str()));
    } else if (method.compare("read") == 0) {
        result->Success(engine->read());
    } else if (method.compare("shutdown") == 0) {
        result->Success(engine->shutdown());
    } else if (method.compare("isReady") == 0) {
        result->Success(engine->isReady());
    } else if (method.compare("isThinking") == 0) {
        result->Success(engine->isThinking());
    } else {
        result->NotImplemented();
    }
};

void FlutterWindow::OnDestroy()
{
    if (flutter_controller_) {
        run_loop_->UnregisterFlutterInstance(flutter_controller_->engine());
        flutter_controller_ = nullptr;
    }

    perfect_exit();  // TODO

    Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam, LPARAM const lparam) noexcept
{
    // Give Flutter, including plugin, an opportunity to handle window messages.
    if (flutter_controller_) {
        std::optional<LRESULT> result =
            flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                          lparam);
        if (result) {
            return *result;
        }
    }

    switch (message) {
    case WM_FONTCHANGE:
        flutter_controller_->engine()->ReloadSystemFonts();
        break;
    }

    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
