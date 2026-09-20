#include "my_application.h"
#include <flutter_linux/flutter_linux.h>
#include <gdk/gdkx.h>
#include <cstring>

struct _MyApplication {
  GtkApplication parent_instance;
  char* dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gtk_window_set_title(window, "SecuredView VPN");
  gtk_window_set_default_size(window, 420, 800);
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(fl_view_get_engine(view)));

  gtk_widget_show(GTK_WIDGET(window));
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gint my_application_command_line(GApplication* application, GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(g_applicationCommandLine_get_arguments(command_line));

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     return 1;
  }

  g_application_activate(application);
  return 0;
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_free);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
    "application-id", APPLICATION_ID,
    "flags", G_APPLICATION_HANDLES_COMMAND_LINE,
    nullptr));
}
