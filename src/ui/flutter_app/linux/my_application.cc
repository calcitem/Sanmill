#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <iostream>

#include "flutter/generated_plugin_registrant.h"

#include "mill_engine.h"

struct _MyApplication
{
    GtkApplication parent_instance;
    char **dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

#if 1
static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data)
{
    const gchar *method = fl_method_call_get_name(method_call);
    printf("fl_method = %s\n", method);

    if (g_strcmp0 (method, "startup") == 0) {
        engine->startup();
    } else if (g_strcmp0 (method, "send") == 0) {
        // TODO
        auto *args = fl_method_call_get_args(method_call);
        FlValue* value = fl_value_lookup_string(args, "str");
        char* str = (char*)fl_value_get_string(value);
        engine->send(str);
    } else if (g_strcmp0 (method, "read") == 0) {
        engine->read();
    } else if (g_strcmp0 (method, "shutdown") == 0) {
        engine->shutdown();
    } else if (g_strcmp0 (method, "isReady") == 0) {
        engine->isReady();
    } else if (g_strcmp0 (method, "isThinking") == 0) {
        engine->isThinking();
    } else {
        // result->NotImplemented();
        //  Get Dart arguments
        FlValue *args = fl_method_call_get_args(method_call);
        // Fetch string value named "name"
        FlValue *text_value = fl_value_lookup_string(args, "name");

        // Check if returned value is either null or string
        if (text_value == nullptr ||
            fl_value_get_type(text_value) != FL_VALUE_TYPE_STRING) {
            // Return error
            g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
                fl_method_not_implemented_response_new());

            // Create error, in this case null
            g_autoptr(GError) error = nullptr;

            // Send response back to dart
            fl_method_call_respond(method_call, response, &error);
        }
    }
}
#endif

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
    gtk_widget_show(GTK_WIDGET(window));

    g_autoptr(FlDartProject) project = fl_dart_project_new();
    fl_dart_project_set_dart_entrypoint_arguments(
        project, self->dart_entrypoint_arguments);

    FlView *view = fl_view_new(project);
    gtk_widget_show(GTK_WIDGET(view));
    gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

    fl_register_plugins(FL_PLUGIN_REGISTRY(view));

    // START OF OUR CUSTOM  BLOCK
#if 1
    if (engine == nullptr) {
        engine = new MillEngine();
    }

    // Get engine from view
    FlEngine *fl_engine = fl_view_get_engine(view);

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    g_autoptr(FlBinaryMessenger) messenger = fl_engine_get_binary_messenger(fl_engine);
    g_autoptr(FlMethodChannel) channel = fl_method_channel_new(messenger,
                                        "com.calcitem.sanmill/engine",
                                        FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(channel, method_call_cb, g_object_ref(view), g_object_unref);
#endif
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
