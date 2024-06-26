#!/usr/bin/env bash

#####################################
#
#	A script that runs tests on launcher.sh
#
#####################################

# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset

# exit if anything returns an error
#set -o errexit

# Exit on error inside any functions or subshells.
#set -o errtrace

# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail

# Turn on traces, useful while debugging but commented out by default
# set -o xtrace

# Set magic variables for current file, directory, os, etc.
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file} .sh)"

# Define the environment variables (and their defaults) that this script depends on
LOG_LEVEL="${LOG_LEVEL:-0}" # 7 = debug -> 0 = emergency
NO_COLOR="${NO_COLOR:-}"    # true = disable color. otherwise autodetected

### Functions
##############################################################################

function _fmt ()      {
  local color_output="\x1b[36m"
  local color_debug="\x1b[35m"
  local color_info="\x1b[32m"
  local color_notice="\x1b[34m"
  local color_warning="\x1b[33m"
  local color_error="\x1b[31m"
  local color_critical="\x1b[1;31m"
  local color_alert="\x1b[1;33;41m"
  local color_emergency="\x1b[1;4;5;33;41m"
  local colorvar=color_$1

  local color="${!colorvar:-$color_error}"
  local color_reset="\x1b[0m"
  if [[ "${NO_COLOR:-}" = "true" ]] || ( [[ "${TERM:-}" != "xterm"* ]] && [[ "${TERM:-}" != "screen"* ]] ) || [[ ! -t 2 ]]; then
    # Don't use colors on pipes or non-recognized terminals
    color=""; color_reset=""
  fi
  echo -e "$(date -u +"%Y-%m-%d %H:%M:%S UTC") ${color}$(printf "[%9s]" ${1})${color_reset}";
}
function emergency () {                             echo "$(_fmt emergency) ${@}" 1>&2 || true; exit 1; }
function alert ()     { [ "${LOG_LEVEL}" -ge 1 ] && echo "$(_fmt alert) ${@}" 1>&2 || true; }
function critical ()  { [ "${LOG_LEVEL}" -ge 2 ] && echo "$(_fmt critical) ${@}" 1>&2 || true; }
function error ()     { [ "${LOG_LEVEL}" -ge 3 ] && echo "$(_fmt error) ${@}" 1>&2 || true; }
function warning ()   { [ "${LOG_LEVEL}" -ge 4 ] && echo "$(_fmt warning) ${@}" 1>&2 || true; }
function notice ()    { [ "${LOG_LEVEL}" -ge 5 ] && echo "$(_fmt notice) ${@}" 1>&2 || true; }
function info ()      { [ "${LOG_LEVEL}" -ge 6 ] && echo "$(_fmt info) ${@}" 1>&2 || true; }
function debug ()     { [ "${LOG_LEVEL}" -ge 7 ] && echo "$(_fmt debug) ${@}" 1>&2 || true; }
function output ()    {                             echo "$(_fmt output) ${@}" || true; }

function _color_out () {
  local color_blue="\x1b[34m"
  local color_red="\x1b[31m"
  local colorvar=color_$1
  local color="${!colorvar:-$color_error}"
  local color_reset="\x1b[0m"
  if [ "${NO_COLOR}" = "true" ] || [[ "${TERM:-}" != "xterm"* ]] || [ -t 1 ]; then
    # Don't use colors on pipes or non-recognized terminals
    color=""; color_reset=""
  fi
  shift
  echo -e "${color}${@}${color_reset}";
}
function red () { echo "$(_color_out red ${@})" || true; }
function blue () { echo "$(_color_out blue ${@})" || true; }

function help () {
  echo "" 1>&2
  echo " ${@}" 1>&2
  echo "" 1>&2
  echo "  ${__usage:-No usage available}" 1>&2
  echo "" 1>&2
  echo " ${__helptext:-}" 1>&2
  echo "" 1>&2
  exit 1
}

function cleanup_before_exit () {
  [ -f _task_test.cfg  ] && rm _task_test.cfg
  [ -f _test_script.sh ] && rm _test_script.sh
  [ -f _test_trigger_script.sh ] && rm _test_trigger_script.sh
  [ -d _run            ] && rm -rf _run
  info "Cleaning up. Done"
}
trap cleanup_before_exit EXIT


### Parse commandline options
##############################################################################

# Commandline options. This defines the usage page, and is used to parse cli
# opts & defaults from. The parsing is unforgiving so be precise in your syntax
# - A short option must be preset for every long option; but every short option
#   need not have a long option
# - `--` is respected as the separator between options and arguments
# - We do not bash-expand defaults, so setting '~/app' as a default will not resolve to ${HOME}.
#   you can use bash variables to work around this (so use ${HOME} instead)
read -r -d '' __usage <<-'EOF' || true # exits non-zero when EOF encountered
  -v               Enable verbose mode, print script as it is executed
  -d --debug       Enables debug mode
  -h --help        This page
  -n --no-color    Disable color output
EOF
read -r -d '' __helptext <<-'EOF' || true # exits non-zero when EOF encountered
 A script that runs tests on launcher.sh
EOF

# Translate usage string -> getopts arguments, and set $arg_<flag> defaults
while read line; do
  # fetch single character version of option string
  opt="$(echo "${line}" |awk '{print $1}' |sed -e 's#^-##')"

  # fetch long version if present
  long_opt="$(echo "${line}" |awk '/\-\-/ {print $2}' |sed -e 's#^--##')"
  long_opt_mangled="$(sed 's#-#_#g' <<< $long_opt)"

  # map long name back to short name
  varname="short_opt_${long_opt_mangled}"
  eval "${varname}=\"${opt}\""

  # check if option takes an argument
  varname="has_arg_${opt}"
  if ! echo "${line}" |egrep '\[.*\]' >/dev/null 2>&1; then
    init="0" # it's a flag. init with 0
    eval "${varname}=0"
  else
    opt="${opt}:" # add : if opt has arg
    init=""  # it has an arg. init with ""
    eval "${varname}=1"
  fi
  opts="${opts:-}${opt}"

  varname="arg_${opt:0:1}"
  if ! echo "${line}" |egrep '\. Default=' >/dev/null 2>&1; then
    eval "${varname}=\"${init}\""
  else
    match="$(echo "${line}" |sed 's#^.*Default=\(\)#\1#g')"
    eval "${varname}=\"${match}\""
  fi
done <<< "${__usage}"

# Allow long options like --this
opts="${opts}-:"

# Reset in case getopts has been used previously in the shell.
OPTIND=1

# start parsing command line
set +o nounset # unexpected arguments will cause unbound variables
               # to be dereferenced
# Overwrite $arg_<flag> defaults with the actual CLI options
while getopts "${opts}" opt; do
  [ "${opt}" = "?" ] && help "Invalid use of script: ${@} "

  if [ "${opt}" = "-" ]; then
    # OPTARG is long-option-name or long-option=value
    if [[ "${OPTARG}" =~ .*=.* ]]; then
      # --key=value format
      long=${OPTARG/=*/}
      long_mangled="$(sed 's#-#_#g' <<< $long)"
      # Set opt to the short option corresponding to the long option
      eval "opt=\"\${short_opt_${long_mangled}}\""
      OPTARG=${OPTARG#*=}
    else
      # --key value format
      # Map long name to short version of option
      long_mangled="$(sed 's#-#_#g' <<< $OPTARG)"
      eval "opt=\"\${short_opt_${long_mangled}}\""
      # Only assign OPTARG if option takes an argument
      eval "OPTARG=\"\${@:OPTIND:\${has_arg_${opt}}}\""
      # shift over the argument if argument is expected
      ((OPTIND+=has_arg_${opt}))
    fi
    # we have set opt/OPTARG to the short value and the argument as OPTARG if it exists
  fi
  varname="arg_${opt:0:1}"
  default="${!varname}"

  value="${OPTARG}"
  if [ -z "${OPTARG}" ] && [ "${default}" = "0" ]; then
    value="1"
  fi

  eval "${varname}=\"${value}\""
  debug "cli arg ${varname} = ($default) -> ${!varname}"
done
set -o nounset # no more unbound variable references expected

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift


### Command-line argument switches (like -d for debugmode, -h for showing helppage)
##############################################################################

# debug mode
if [ "${arg_d}" = "1" ]; then
  set -o xtrace
  LOG_LEVEL="7"
fi

# verbose mode
if [ "${arg_v}" = "1" ]; then
  set -o verbose
fi

# no color mode
if [ "${arg_n}" = "1" ]; then
  NO_COLOR="true"
fi

# help mode
if [ "${arg_h}" = "1" ]; then
  # Help exists with code 1
  help "Help using ${0}"
fi

### Runtime
##############################################################################

LOG_LEVEL=7
PASSED=0
FAILED=0

function assert () {
if [[ ${RESULT} == *${EXPECTED}* ]]
then
	blue "==================================> TEST PASSED"
	PASSED="$(( ${PASSED} + 1 ))"
else
	red "==================================> TEST FAILED"
	red "Got RESULT -> ${RESULT}"
	red "Expected -> ${EXPECTED}"
	FAILED="$(( ${FAILED} + 1 ))"
fi
}

# create temporary 'run' directory
[ ! -d _run ] && mkdir _run

# test no config file given
output "Running 'no config file' test"
RESULT=$(LOG_LEVEL=7 ./launcher.sh 2>&1)
EXPECTED="can not continue without a config file"
assert
echo

# test unreadable config file
output "Running 'unreadable config file' test"
RESULT=$(LOG_LEVEL=7 ./launcher.sh -c bad_file 2>&1)
EXPECTED="can not read configuration file"
assert
echo

# test exiting on non-active task
output "Running 'non-active task' test"
# create config file for task
cat <<-'EOF' > _task_test.cfg
Task_Name="scheduler test task"
EOF
echo "Application_Name=\"${PWD}/launcher.sh\"" >> _task_test.cfg
cat <<-'EOF' >> _task_test.cfg
Parameters=""
Working_Directory=""
Active="false"
Allow_Multiple="false"
Comment=""
EOF
RESULT=$(LOG_LEVEL=7 ./launcher.sh -c ./_task_test.cfg 2>&1)
EXPECTED="Task is not active. Exiting..."
assert
echo

# create an unsuccessful test trigger script
cat <<-'EOF' > _test_trigger_script.sh
#!/bin/bash
exit 1
EOF
chmod +x _test_trigger_script.sh

# test exiting on unsuccessful trigger script
output "Running 'unsuccessful trigger' test"
# create config file for task
cat <<-'EOF' > _task_test.cfg
Task_Name="scheduler test task"
EOF
echo "Application_Name=\"${PWD}/launcher.sh\"" >> _task_test.cfg
cat <<-'EOF' >> _task_test.cfg
Parameters=""
Working_Directory=""
Trigger_Script="./_test_trigger_script.sh"
Active="true"
Allow_Multiple="false"
Comment=""
EOF
RESULT=$(LOG_LEVEL=7 ./launcher.sh -c ./_task_test.cfg 2>&1)
EXPECTED="Trigger script returned unsuccessful so run condition not met. Exiting..."
assert
echo

# create a test script
cat <<-'EOF' > _test_script.sh
#!/bin/bash
sleep 3
EOF
chmod +x _test_script.sh

# create a successful test trigger script
cat <<-'EOF' > _test_trigger_script.sh
#!/bin/bash
exit 0
EOF
chmod +x _test_trigger_script.sh

# test successful trigger script
output "Running 'successful trigger' test"
# create config file for task
cat <<-'EOF' > _task_test.cfg
Task_Name="scheduler test task"
EOF
echo "Application_Name=\"${PWD}/_test_script.sh\"" >> _task_test.cfg
cat <<-'EOF' >> _task_test.cfg
Parameters=""
Working_Directory=""
Trigger_Script="./_test_trigger_script.sh"
Active="true"
Allow_Multiple="false"
Comment=""
EOF
RESULT=$(LOG_LEVEL=7 DEFAULT_RUN_DIRECTORY="./_run" ./launcher.sh -c ./_task_test.cfg 2>&1)
EXPECTED="Started task with pid"
assert
# make sure to wait for both scripts to finish before proceeding
output "Waiting for test scripts"
sleep 3
echo

# test multiple instances allowed
output "Running 'multiple instances allowed' test"
# create config file for task
cat <<-'EOF' > _task_test.cfg
Task_Name="scheduler test task"
EOF
echo "Application_Name=\"${PWD}/_test_script.sh\"" >> _task_test.cfg
cat <<-'EOF' >> _task_test.cfg
Parameters=""
Working_Directory=""
Active="true"
Allow_Multiple="true"
Comment=""
EOF
# start one instance then test that launcher can start another
LOG_LEVEL=0 DEFAULT_RUN_DIRECTORY="./_run" ./launcher.sh -c ./_task_test.cfg &
RESULT=$(LOG_LEVEL=7 DEFAULT_RUN_DIRECTORY="./_run" ./launcher.sh -c ./_task_test.cfg 2>&1)
EXPECTED="Started task with pid"
assert
# make sure to wait for both scripts to finish before proceeding
output "Waiting for test scripts"
sleep 3
echo

# test multiple instances not allowed - one instance already running
output "Running 'multiple instances not allowed - one instance already running' test"
# create config file for task
cat <<-'EOF' > _task_test.cfg
Task_Name="scheduler test task"
EOF
echo "Application_Name=\"${PWD}/_test_script.sh\"" >> _task_test.cfg
cat <<-'EOF' >> _task_test.cfg
Parameters=""
Working_Directory=""
Active="true"
Allow_Multiple="false"
Comment=""
EOF
# start one instance then test that launcher can not start another
LOG_LEVEL=0 DEFAULT_RUN_DIRECTORY="./_run" ./launcher.sh -c ./_task_test.cfg &
RESULT=$(LOG_LEVEL=7 DEFAULT_RUN_DIRECTORY="./_run" ./launcher.sh -c ./_task_test.cfg 2>&1)
EXPECTED="Task is already running"
assert
# make sure to wait for script to finish before proceeding
output "Waiting for test script"
sleep 3
echo

output "Total Passed: ${PASSED}"
warning "Total Failed: ${FAILED}"
echo

