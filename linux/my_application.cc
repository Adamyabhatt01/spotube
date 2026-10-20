#include "my_application.h"

#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// The descriptor the control protocol's stdout is parked on, and the
// environment variable that tells Dart where to find it.
//
// `spotube --mcp` speaks JSON-RPC over stdout, and `spotube --status`
// prints its answer there. stdout cannot be shared for either: the
// native media_kit plugin prints "package:media_kit_libs_linux registered."
// when it loads, and the Hetu VM prints its module timings. Either would
// corrupt the stream (and the CLI's answer would be buried under them),
// and the native print happens before the Dart entrypoint even starts.
//
// So the real stdout is duplicated onto a dedicated descriptor and fd 1 is
// pointed at stderr. Everything that used to print to stdout now lands on
// stderr, and the control protocol writes to the saved descriptor. This
// has to happen here, in the runner, because the offending native print
// precedes Dart.
static const char kControlStdoutEnv[] = "SPOTUBE_CONTROL_STDOUT_FD";

// Points fd 1 at stderr and saves the original stdout for the control
// protocol. A no-op unless the arguments ask for a control command.
void configure_control_stdout(int argc, char** argv) {
  // The arguments that mean "this process is a control client, not the
  // app". They mirror the CLI's own flags (lib/services/cli/cli.dart).
  // "--version" and "--help" are included: they print to stdout too, and
  // the native plugins' registration message would otherwise land in
  // front of the answer.
  static const char* kControlFlags[] = {
      "--mcp",     "--status", "--play",  "--search",   "--pause",
      "--resume",  "--next",   "--previous", "--volume", "--version",
      "--help",    nullptr};

  bool is_control = false;
  for (int i = 1; i < argc && !is_control; i++) {
    for (int f = 0; kControlFlags[f] != nullptr; f++) {
      // A flag may be "--play=x"; the name is what matters.
      if (g_str_has_prefix(argv[i], kControlFlags[f])) {
        is_control = true;
        break;
      }
    }
  }
  if (!is_control) return;

  // F_DUPFD (not F_DUPFD_CLOEXEC): the descriptor must survive into the
  // Dart side, which reopens it through /proc/self/fd.
  //
  // The descriptor number is chosen by the kernel (F_DUPFD with the
  // lowest free one), NOT a fixed value: by the time this runs the GPU
  // driver has already claimed the low descriptors, and a fixed one would
  // either be taken (the duplicate fails, and the redirect silently does
  // not happen) or clobber something else.
  int saved = fcntl(STDOUT_FILENO, F_DUPFD, 3);
  if (saved < 0) return;

  // fd 1 now points at stderr. Everything printed to stdout from here on
  // (native plugins, the VM, the app) goes to stderr instead.
  if (dup2(STDERR_FILENO, STDOUT_FILENO) < 0) {
    close(saved);
    return;
  }

  char fd_text[16];
  g_snprintf(fd_text, sizeof(fd_text), "%d", saved);
  g_setenv(kControlStdoutEnv, fd_text, TRUE);
}

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Real window transparency needs an RGBA visual: without it the compositor
  // is offered no alpha channel, so any transparent Flutter painting would
  // read as opaque and the app would have to fake glass by painting its own
  // wallpaper. Must precede realization (show). Harmless while the app
  // paints opaque (the default) — it only *allows* alpha to reach a
  // composited session; elsewhere the visual request is skipped.
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  {
    GdkScreen* rgba_screen = gtk_widget_get_screen(GTK_WIDGET(window));
    GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(rgba_screen);
    if (rgba_visual != nullptr && gdk_screen_is_composited(rgba_screen)) {
      gtk_widget_set_visual(GTK_WIDGET(window), rgba_visual);
    }
  }

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "spotube");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "spotube");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  // Real window transparency needs a transparent clear color as well as
  // the RGBA visual above: the view clears with opaque black unless told
  // otherwise, which would composite over the alpha the visual offers and
  // hand the compositor an opaque frame (every "transparent" pixel read as
  // black). Harmless while the app paints opaque (the default) — content
  // covers the clear color exactly as before; it only shows where Flutter
  // paints nothing, which is precisely the transparent-window case.
  {
    GdkRGBA view_background;
    gdk_rgba_parse(&view_background, "#00000000");
    fl_view_set_background_color(view, &view_background);
  }
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
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

  // TRUE means "the command line was handled": g_application_run must not
  // fall through to its own activation path, and the process must stay
  // alive for the Dart entrypoint, which this application owns.
  //
  // This runner used to return FALSE, which told GLib the command line was
  // NOT handled. Combined with the G_APPLICATION_HANDLES_COMMAND_LINE flag
  // (now removed — see my_application_new), GLib then refused to run the
  // default handler and exited with status 1. The Dart side never ran, so
  // every command-line flag (`--version`, `--help`, and the control
  // commands) was dead. The Flutter template returns TRUE for this reason.
  return TRUE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

bool is_flatpak(void) {
  if (getenv("container") || getenv("FLATPAK_ID") || getenv("FLATPAK")) {
    /* flatpak */
    return true;
  }
  return false; /* No container detected */
}

MyApplication* my_application_new() {
  // gchar based alternate MY_APPLICATION_ID
  const char* my_application_id = APPLICATION_ID;

  if (is_flatpak()) {
    my_application_id = "com.github.KRTirtho.Spotube";
  }

  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file.
  g_set_prgname(my_application_id);

  // The flags deliberately do NOT include G_APPLICATION_HANDLES_COMMAND_LINE.
  //
  // That flag makes GLib treat the command line as the application's own
  // responsibility: it requires a g_application_command_line() handler, and
  // when g_application_run() finds none it warns ("Your application claims
  // to support custom command line handling but does not implement
  // g_application_command_line()") and exits. The command line is handled
  // by the Dart entrypoint instead (lib/services/cli/cli.dart), which
  // receives the same arguments through fl_dart_project_set_dart_entrypoint_
  // arguments() below.
  //
  // G_APPLICATION_NON_UNIQUE is what the Flutter template uses: it lets a
  // second launch reach the Dart entrypoint (so `spotube --play ...` can
  // forward to the running instance) instead of GTK activating the existing
  // window and discarding the arguments.
  return MY_APPLICATION(g_object_new(
      my_application_get_type(), "application-id", my_application_id, "flags",
      G_APPLICATION_NON_UNIQUE | G_APPLICATION_HANDLES_OPEN, nullptr));
}