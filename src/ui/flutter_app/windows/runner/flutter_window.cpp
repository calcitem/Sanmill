// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// flutter_window.cpp

#include "flutter_window.h"

#include <memory>
#include <optional>
#include <sstream>
#include <string>

// TODO
#include "perfect_adaptor.h"

#include "flutter/generated_plugin_registrant.h"

static std::wstring Utf8ToUtf16(const std::string &utf8Str)
{
    if (utf8Str.empty()) {
        return std::wstring();
    }

    int count = MultiByteToWideChar(CP_UTF8, 0, utf8Str.c_str(), -1, nullptr,
                                    0);
    std::wstring utf16Str(count - 1, 0);
    MultiByteToWideChar(CP_UTF8, 0, utf8Str.c_str(), -1, &utf16Str[0], count);

    return utf16Str;
}

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

    InitializeMethodChannels();

    run_loop_->RegisterFlutterInstance(flutter_controller_->engine());
    SetChildContent(flutter_controller_->view()->GetNativeWindow());

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

void FlutterWindow::InitializeMethodChannels()
{
    // Set up a method channel for the engine.
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

    // Set up a method channel for the UI.
    auto binary_messenger = flutter_controller_->engine()->messenger();

    auto ui_channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            binary_messenger, "com.calcitem.sanmill/ui",
            &flutter::StandardMethodCodec::GetInstance());

    ui_channel->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue> &call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                   result) {
            if (call.method_name() == "setWindowTitle") {
                const auto *arguments = std::get_if<flutter::EncodableMap>(
                    call.arguments());
                if (arguments) {
                    auto title_it = arguments->find(
                        flutter::EncodableValue("title"));
                    if (title_it != arguments->end()) {
                        const auto *title_ptr = std::get_if<std::string>(
                            &title_it->second);
                        if (title_ptr) {
                            std::wstring titleUtf16 = Utf8ToUtf16(*title_ptr);
                            Win32Window::SetTitle(titleUtf16);
                            result->Success();
                            return;
                        }
                    }
                }
                result->Error("Invalid arguments", "Expected string value for "
                                                   "'title'.");
            } else {
                result->NotImplemented();
            }
        });
}
