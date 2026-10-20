#ifndef FLUTTER_MY_APPLICATION_H_
#define FLUTTER_MY_APPLICATION_H_

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(MyApplication, my_application, MY, APPLICATION,
                     GtkApplication)

/**
 * configure_control_stdout:
 * @argc: the process argument count
 * @argv: the process arguments
 *
 * Reserves stdout for the control protocol when a control command is among
 * the arguments (--mcp, --status, --play, ...): the real stdout is
 * duplicated onto a dedicated descriptor and fd 1 is pointed at stderr,
 * so the native plugins' and the VM's own output cannot corrupt the
 * protocol stream or bury the CLI's answer.
 *
 * A no-op in every other mode.
 */
void configure_control_stdout(int argc, char** argv);

/**
 * my_application_new:
 *
 * Creates a new Flutter-based application.
 *
 * Returns: a new #MyApplication.
 */
MyApplication* my_application_new();

#endif  // FLUTTER_MY_APPLICATION_H_
