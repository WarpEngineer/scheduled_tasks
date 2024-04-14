# scheduled_tasks
## System Cron Launcher Script

A script to launch and manage system crons.

This script manages the launching and supervision of system crons. It is designed to be launched by cron itself and is provided a configuration file describing the task to manage. The script can ensure that only one instance of a task is running at any given time, keeping track of its PID and running state. This allows for centralized management without requiring similar code in each separate program.

## Usage

Using the launcher.sh Script

### Prerequisites:

- The launcher.sh script must be executable. Use chmod +x launcher.sh to make it executable.
- Basic understanding of cron jobs is helpful.
- Configuration File
  - Prepare a configuration file that defines the task details. The script expects this file as a command-line argument.

#### Example configuration:

```cfg
Task_Name="my_task"
Application_Name="/path/to/your/application"
Parameters="-arg1 value1 -arg2 value2"
Working_Directory="/home/user/app_dir"
Trigger_Script="/test_env.sh" # Optional. Returns zero to run the task
Active="true"  # Set to "false" to disable the task
Allow_Multiple="false" # Set to "true" to allow multiple instances
Log_File="/var/log/my_task.log"  # Optional log file for the application
```

### Run the script

```bash
LOG_LEVEL={int} ./launcher.sh {options}
```

### Options:

- `-c --configfile [arg]`: Specifies the configuration file to read. (Required)
- `-v`: Enable verbose mode, printing script execution steps.
- `-d --debug`: Enables debug mode for extensive logging.
- `-h --help`: Displays the help page.
- `-n --no-color`: Disables color output.
- `-V --version`: Shows the script version and exits.

### Explanation of Configuration File Options:

- `Task_Name`: A unique name to identify the task.
- `Application_Name`: The absolute path to the application executable.
- `Parameters`: Optional arguments passed to the application during execution.
- `Working_Directory`: The directory where the application will be executed.
- `Trigger_Script`: (Optional) A script to run before starting the task. If the script is successful (returns zero) then the task is run. This can be used for conditionally running the task based on environmental factors.
- `Active`: Set to "true" to enable the task, or "false" to disable it.
- `Allow_Multiple`: Set to "true" to allow concurrent instances of the task, or "false"(default) to restrict to one instance.
- `Comment`: Additional comments or notes.
- `Log_File`: (Optional) Path to a file where the application's output will be logged.

### Behavior

- If the task is not active, the script exits cleanly.
- If `Allow_Multiple` is set to "false", the script checks for an existing instance of the task. If one is found, it exits. Otherwise, it starts the task.
- If `Allow_Multiple` is "true", the script always starts the task, even if an instance is already running.
