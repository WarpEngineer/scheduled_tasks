#!/usr/bin/env bash
# Based on a template by BASH3 Boilerplate v2.0.0
# Copyright (c) 2013 Kevin van Zonneveld and contributors
# http://bash3boilerplate.sh/#authors
# https://github.com/WarpEngineer/bash3boilerplate

#####################################
#
#	A script to launch and manage system crons.
#	usage: LOG_LEVEL={int} ./launcher.sh {options}
#
#####################################

# TODO: maybe as an option send mail if failed/succeeded/whatever

# TODO: need to redirect to log file??
###
#		# Close STDOUT file descriptor
#		exec 1<&-
#		# Close STDERR FD
#		exec 2<&-
#
#		# Open STDOUT as $LOG_FILE file for read and write.
#		exec 1<>$LOG_FILE
#
#		# Redirect STDERR to STDOUT
#		exec 2>&1
#
#		echo "This line will appear in $LOG_FILE, not 'on screen'"
###

# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset

# exit if anything returns an error
#set -o errexit

# Exit on error inside any functions or subshells.
set -o errtrace

# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail

# Turn on traces, useful while debugging but commented out by default
# set -o xtrace

# Set script version 
__version="2017.01"

# Set magic variables for current file, directory, os, etc.
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file} .sh)"

# Define the environment variables (and their defaults) that this script depends on
LOG_LEVEL="${LOG_LEVEL:-0}" # 7 = debug -> 0 = emergency
NO_COLOR="${NO_COLOR:-}"    # true = disable color. otherwise autodetected

# grab defaults from environment if available, otherwise set them
# TODO: set defaults here as desired
[ -z "${DEFAULT_CONFIG_FILE_LOCATION:-}" ] && DEFAULT_CONFIG_FILE_LOCATION="."
[ -z "${DEFAULT_BIN_DIRECTORY:-}" ] && DEFAULT_BIN_DIRECTORY="."
[ -z "${DEFAULT_RUN_DIRECTORY:-}" ] && DEFAULT_RUN_DIRECTORY="."

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
  if [ "${NO_COLOR}" = "true" ] || [[ "${TERM:-}" != "xterm"* ]] || [ -t 1 ]; then
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
  -c --configfile  [arg] Configuration file to read.
  -v               Enable verbose mode, print script as it is executed
  -d --debug       Enables debug mode
  -h --help        This page
  -n --no-color    Disable color output
  -V --version     Show version and exit
EOF
read -r -d '' __helptext <<-'EOF' || true # exits non-zero when EOF encountered
 A script that is launched by cron that manages other tasks. It is given a configuration file that
 describes the task to manage.  It will start the task with an option to only start one instance and keep
 track of the PID and running state.  This is to keep from having management code in each separate program.
 The default location will be searched for config files if only a name is given.  If the config file passed
 begins with a slash (/) or dot (.) character, then it is assumed to be an absolute path and no search is made.
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

# version mode
if [ "${arg_V}" = "1" ]; then
 # Version print exists with code 1
 echo "Version: ${__version}" 2>&1
 exit 1
fi

# help mode
if [ "${arg_h}" = "1" ]; then
  # Help exists with code 1
  help "Help using ${0}"
fi


### Validation. Error out if the things required for your script are not present
################################################################################

[ -z "${arg_c:-}" ] && emergency "can not continue without a config file. "

[ -z "${LOG_LEVEL:-}" ] && emergency "can not continue without LOG_LEVEL. "

# read configuration file and verify
# check if arg_c begins with a / and treat as absolute path if so. Otherwise, look under default location.
if [[ ! "${arg_c}" == /* ]]
then
	if [[ ! "${arg_c}" == .* ]]
	then
		# relative path
		arg_c="${DEFAULT_CONFIG_FILE_LOCATION}/${arg_c}"
	fi
fi

# set task defaults
Parameters=""
Active="true"
Allow_Multiple="false"
Comment=""

[ ! -r ${arg_c} ] && emergency "can not read configuration file ${arg_c}"
. ${arg_c}

[ -z "${Task_Name:-}" ] && emergency "can not continue without Task_Name. "
[ -z "${Application_Name:-}" ] && emergency "can not continue without Application_Name. "

# make sure working direcotry is something
[ -z "${Working_Directory:-}" ] && Working_Directory="${PWD}"

# check if applcation is an absolute path. if not, use default location
if [[ ! "${Application_Name}" == /* ]]
then
	# relative path
	Application_Name="${DEFAULT_BIN_DIRECTORY}/${Application_Name}"
fi

[ ! -x "${Application_Name:-}" ] && emergency "can not continue because ${Application_Name} is not found or not executable. "
[ ! -d "${Working_Directory:-}" ] && emergency "can not continue because ${Working_Directory} does not exist. "

### Runtime
##############################################################################

info "__file: ${__file}"
info "__dir: ${__dir}"
info "__base: ${__base}"
info "OSTYPE: ${OSTYPE}"

info "arg_c: ${arg_c}"
info "arg_d: ${arg_d}"
info "arg_v: ${arg_v}"
info "arg_h: ${arg_h}"
info "arg_n: ${arg_n}"

info "Task_Name="${Task_Name}
info "Application_Name="${Application_Name}
info "Parameters="${Parameters}
info "Working_Directory="${Working_Directory}
info "Active="${Active}
info "Allow_Multiple="${Allow_Multiple}
info "Comment="${Comment}

# if the task is not active, do nothing and just exit cleanly
if [ ! "${Active}" = "true" ]
then
	info "Task is not active. Exiting..."
	exit 0
fi

function run_task () {
	CWD=$PWD
	cd "${Working_Directory}"
	debug "Running ${Application_Name} ${Parameters} in directory ${Working_Directory}"
	"${Application_Name}" ${Parameters} &
	PID=$!
	debug "Started task with pid ${PID}"
	echo "${PID}" > "${PID_FILE}"
	debug "Wating for task to finish..."
	wait "${PID}"
	RESULT=$?
	info "Task completed with exit code ${RESULT}"
	rm "${PID_FILE}"
	cd "${CWD}"
}

# create an ID for this instance
INSTANCE_ID="$( echo "${Task_Name}_${Application_Name}_${Parameters}" | (sha512sum || sha256sum || sha1sum || shasum) | cut -f1 -d' ' )"
debug "INSTANCE_ID"=${INSTANCE_ID}

# run directory for this instance
RUN_DIRECTORY="${DEFAULT_RUN_DIRECTORY}/${INSTANCE_ID}"
mkdir -p "${RUN_DIRECTORY}"
[ ! -d "${RUN_DIRECTORY:-}" ] && emergency "can not continue because ${RUN_DIRECTORY} could not be created. "
debug "RUN_DIRECTORY"=${RUN_DIRECTORY}

# check run directory for a PID file. if it exists, check to see if it's still running.  if still running and Allow_Multiple is false
# then this instance must exit.  if Allow_Multiple is true, then keep going.
if [ "${Allow_Multiple}" = "false" ]
then
	PID_FILE="${RUN_DIRECTORY}/pid"
	debug "PID_FILE="${PID_FILE}
	if [ -f "${PID_FILE}" ]
	then
		PID="$( cat ${PID_FILE} )"
		RUNNING_PIDS="$( pgrep -f $( basename ${Application_Name} ) || echo -1 )"
		#if [ "${PID}" -eq "${RUNNING_PID}" ]
		if [[ ${RUNNING_PIDS} =~ (^|[[:space:]])${PID}($|[[:space:]]) ]]
		then
			# still running so just exit
			info "Task is already running and Allow_Multiple is false. Exiting..."
			exit 0
		else
			# maybe it crashed, so just take over
			run_task
		fi
	else
		run_task
	fi
else
	PID_FILE="${RUN_DIRECTORY}/pid$$"
	debug "PID_FILE="${PID_FILE}
	run_task
fi

