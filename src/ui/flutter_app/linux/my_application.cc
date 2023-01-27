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

#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <iostream>
#include <memory>

#include "flutter/generated_plugin_registrant.h"

#include "mill_engine.h"

struct _MyApplication
{
    GtkApplication parent_instance;
    char **dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

MillEngine *engine = nullptr;

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data)
{
    const gchar *method = fl_method_call_get_name(method_call);

    if (g_strcmp0(method, "startup") == 0) {
        FlValue* value = fl_value_new_int(engine->startup());
        fl_method_call_respond_success(method_call, value, nullptr);
    } else if (g_strcmp0(method, "send") == 0) {
        FlValue* args = fl_method_call_get_args(method_call);
        const char* str = fl_value_get_string(args);
        FlValue* value = fl_value_new_int(engine->send(str));
        fl_method_call_respond_success(method_call, value, nullptr);
    } else if (g_strcmp0(method, "read") == 0) {
        FlValue* value = fl_value_new_string(engine->read().c_str());
        fl_method_call_respond_success(method_call, value, nullptr);
    } else if (g_strcmp0(method, "shutdown") == 0) {
        FlValue* value = fl_value_new_int(engine->shutdown());
        fl_method_call_respond_success(method_call, value, nullptr);
    } else if (g_strcmp0(method, "isReady") == 0) {
        FlValue* value = fl_value_new_bool(engine->isReady());
        fl_method_call_respond_success(method_call, value, nullptr);
    } else if (g_strcmp0(method, "isThinking") == 0) {
        FlValue* value = fl_value_new_bool(engine->isThinking());
        fl_method_call_respond_success(method_call, value, nullptr);
    } else {
        g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
        g_autoptr(GError) error = nullptr;
        fl_method_call_respond(method_call, response, &error);
    }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication *application)
{
    MyApplication *self = MY_APPLICATION(application);
    GtkWindow *window = GTK_WINDOW(
        gtk_application_window_new(GTK_APPLICATION(application)));

    // Use a header bar when running in GNOME as this is the common style used
    // by applications and is the setup most users will be using (e.g. Ubuntu
    // desktop).
    // If running on X and not using GNOME then just use a traditional title bar
    // in case the window manager does more exotic layout, e.g. tiling.
    // If running on Wayland assume the header bar will work (may need changing
    // if future cases occur).
    gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
    GdkScreen *screen = gtk_window_get_screen(window);
    if (GDK_IS_X11_SCREEN(screen)) {
        const gchar *wm_name = gdk_x11_screen_get_window_manager_name(screen);
        if (g_strcmp0(wm_name, "Mill") != 0) {
            use_header_bar = FALSE;
        }
    }
#endif
    if (use_header_bar) {
        GtkHeaderBar *header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
        gtk_widget_show(GTK_WIDGET(header_bar));
        gtk_header_bar_set_title(header_bar, "Mill (N Men's Morris)");
        gtk_header_bar_set_show_close_button(header_bar, TRUE);
        gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
    } else {
        gtk_window_set_title(window, "Mill (N Men's Morris)");
    }

    gtk_window_set_default_size(window, 428, 926);
    gtk_window_set_resizable(GTK_WINDOW (window), TRUE);
    gtk_widget_show(GTK_WIDGET(window));

    g_autoptr(FlDartProject) project = fl_dart_project_new();
    fl_dart_project_set_dart_entrypoint_arguments(
        project, self->dart_entrypoint_arguments);

    FlView *view = fl_view_new(project);
    gtk_widget_show(GTK_WIDGET(view));
    gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

    fl_register_plugins(FL_PLUGIN_REGISTRY(view));

    // START OF OUR CUSTOM  BLOCK

    if (engine == nullptr) {
        engine = new MillEngine();

        // Get engine from view
        FlEngine *fl_engine = fl_view_get_engine(view);

        g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
        g_autoptr(FlBinaryMessenger) messenger = fl_engine_get_binary_messenger(fl_engine);
        g_autoptr(FlMethodChannel) channel = fl_method_channel_new(messenger,
                                        "com.calcitem.sanmill/engine",
                                        FL_METHOD_CODEC(codec));
        fl_method_channel_set_method_call_handler(channel, method_call_cb, g_object_ref(view), g_object_unref);
    }

    // END OF OUR CUSTOM BLOCK

    gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication *application,
                                                  gchar ***arguments,
                                                  int *exit_status)
{
    MyApplication *self = MY_APPLICATION(application);
    // Strip out the first argument as it is the binary name.
    self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

    g_autoptr(GError) error = nullptr;
    if (!g_application_register(application, nullptr, &error)) {
        g_warning("Failed to register: %s", error->message);
        *exit_status = 1;
        return TRUE;
    }

    g_application_activate(application);
    *exit_status = 0;

    return TRUE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject *object)
{
    if (engine != nullptr) {
        engine->shutdown();
        delete engine;
        engine = nullptr;
    }

    MyApplication *self = MY_APPLICATION(object);
    g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
    G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass *klass)
{
    G_APPLICATION_CLASS(klass)->activate = my_application_activate;
    G_APPLICATION_CLASS(klass)->local_command_line =
        my_application_local_command_line;
    G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication *self) { }

MyApplication *my_application_new()
{
    return MY_APPLICATION(g_object_new(
        my_application_get_type(), "application-id", APPLICATION_ID, "flags",
        G_APPLICATION_NON_UNIQUE, nullptr));
}
