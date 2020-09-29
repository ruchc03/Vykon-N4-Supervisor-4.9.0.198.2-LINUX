#!/bin/bash

declare -r VERSION="4.9.0.198"
declare -r JRE_VERSION="1.8.0.251.0"
declare -r BUILD_DATE="Tue Jun 16 19:44:17 Coordinated Universal Time 2020"
declare -r BUILD="Build ${VERSION}"

declare -r SERVICE_NAME="n4d"
declare -r USR_BIN_NAME="/usr/bin/niagaradctl"
declare -r LAUNCHER_NAME="n4launcher"

declare -r ETC_INITD_NAME="/etc/init.d/${SERVICE_NAME}"
declare -r ETC_RC0D_NAME="/etc/rc0.d/K05${SERVICE_NAME}"
declare -r ETC_RC1D_NAME="/etc/rc1.d/K05${SERVICE_NAME}"
declare -r ETC_RC2D_NAME="/etc/rc2.d/K05${SERVICE_NAME}"
declare -r ETC_RC3D_NAME="/etc/rc3.d/S98${SERVICE_NAME}"
declare -r ETC_RC4D_NAME="/etc/rc4.d/K05${SERVICE_NAME}"
declare -r ETC_RC5D_NAME="/etc/rc5.d/S98${SERVICE_NAME}"
declare -r ETC_RC6D_NAME="/etc/rc6.d/K05${SERVICE_NAME}"

declare -r PROPS_ERROR="Error reading install.properties."

# Generic buffer for reading from install.properties
declare _prop_value=""

declare BRAND_ID
declare MENU_FILE_PATH
declare DIRECTORY_FILE_NAME
declare DIRECTORY_FILE_PATH
declare WB_MENU_FILE_NAME
declare WBW_MENU_FILE_NAME
declare CONSOLE_MENU_FILE_NAME
declare ALARM_PORTAL_MENU_FILE_NAME

# User info
declare -r CURRENT_USER="$(id -un)"
declare -r CURRENT_UID="$(id -u)"
declare -r NIAGARA_USER="niagara"
declare -r NIAGARA_GROUP="niagara"

# Buffer to hold user's primary group
declare _primary_group=""

# OS info
declare _is_debian
declare _is_redhat
declare _is_amazon

# Command arg formats
declare _groupadd_force_arg=
declare _groupadd_gid_arg=

declare _useradd_comment_arg=
declare _useradd_create_home_arg=
declare _useradd_shell_arg=
declare _useradd_uid_arg=
declare _useradd_gid_arg=
declare _useradd_nologin_arg=

declare _usermod_append_arg=
declare _usermod_groups_arg=

# Install results
declare _installed_service=false
declare _installed_rc0=false
declare _installed_rc1=false
declare _installed_rc2=false
declare _installed_rc3=false
declare _installed_rc4=false
declare _installed_rc5=false
declare _installed_rc6=false
declare _installed_usr_bin=false

declare INSTALL_DIR
declare DEFAULT_INSTALL_DIR
declare _niagarad_generic_file

declare _symlink_target

# User response variables
declare _resp_yes=false
declare _resp_no=false
declare _resp_default=false
declare _error=0

declare -a _users
declare -i _users_count=0
declare -a _existing_users
declare -i _existing_users_count=0

declare _install_desktop_shortcuts=false
declare _install_menu_shortcuts=false

# Localized error, warning, success, and enter messages
declare WARNING_MESSAGE
declare FAILURE_MESSAGE
declare SUCCESS_MESSAGE
declare ENTER_MESSAGE

# Take advantage of terminal colors if the term type supports it
declare SETFORE_BLACK
declare SETFORE_RED
declare SETFORE_GREEN
declare SETFORE_BROWN
declare SETFORE_BLUE
declare SETFORE_MAGENTA
declare SETFORE_CYAN
declare SETFORE_WHITE
declare SETFORE_NORMAL
declare SETBACK_BLACK
declare SETBACK_RED
declare SETBACK_GREEN
declare SETBACK_BROWN
declare SETBACK_BLUE
declare SETBACK_MAGENTA
declare SETBACK_CYAN
declare SETBACK_WHITE
declare MOVE_TO_COL_65

if [ "${CONSOLETYPE}" = "serial" ]; then
  SETFORE_BLACK=
  SETFORE_RED=
  SETFORE_GREEN=
  SETFORE_BROWN=
  SETFORE_BLUE=
  SETFORE_MAGENTA=
  SETFORE_CYAN=
  SETFORE_WHITE=
  SETFORE_NORMAL=
  SETBACK_BLACK=
  SETBACK_RED=
  SETBACK_GREEN=
  SETBACK_BROWN=
  SETBACK_BLUE=
  SETBACK_MAGENTA=
  SETBACK_CYAN=
  SETBACK_WHITE=
  MOVE_TO_COL_65=
else
  SETFORE_BLACK="echo -en \\033[1;30m"
  SETFORE_RED="echo -en \\033[1;31m"
  SETFORE_GREEN="echo -en \\033[1;32m"
  SETFORE_BROWN="echo -en \\033[1;33m"
  SETFORE_BLUE="echo -en \\033[1;34m"
  SETFORE_MAGENTA="echo -en \\033[1;35m"
  SETFORE_CYAN="echo -en \\033[1;36m"
  SETFORE_WHITE="echo -en \\033[1;37m"
  SETFORE_NORMAL="echo -en \\033[0;39m"
  SETBACK_BLACK="echo -en \\033[1;40m"
  SETBACK_RED="echo -en \\033[1;41m"
  SETBACK_GREEN="echo -en \\033[1;42m"
  SETBACK_BROWN="echo -en \\033[1;43m"
  SETBACK_BLUE="echo -en \\033[1;44m"
  SETBACK_MAGENTA="echo -en \\033[1;45m"
  SETBACK_CYAN="echo -en \\033[1;46m"
  SETBACK_WHITE="echo -en \\033[1;47m"
  SETBACK_NORMAL="echo -en \\033[0;49m"
  MOVE_TO_COL_65="echo -en \\033[65G"
fi

readonly SETFORE_BLACK
readonly SETFORE_RED
readonly SETFORE_GREEN
readonly SETFORE_BROWN
readonly SETFORE_BLUE
readonly SETFORE_MAGENTA
readonly SETFORE_CYAN
readonly SETFORE_WHITE
readonly SETFORE_NORMAL
readonly SETBACK_BLACK
readonly SETBACK_RED
readonly SETBACK_GREEN
readonly SETBACK_BROWN
readonly SETBACK_BLUE
readonly SETBACK_MAGENTA
readonly SETBACK_CYAN
readonly SETBACK_WHITE
readonly MOVE_TO_COL_65

function get_localized_msgs
{
  # Grab a localized error, warning, success, and enter message
  get_install_prop_value warning.message "WARNING"
  WARNING_MESSAGE="${_prop_value}"
  readonly WARNING_MESSAGE

  get_install_prop_value failure.message "FAILED"
  FAILURE_MESSAGE="${_prop_value}"
  readonly FAILURE_MESSAGE

  get_install_prop_value success.message "SUCCESS"
  SUCCESS_MESSAGE="${_prop_value}"
  readonly SUCCESS_MESSAGE

  get_install_prop_value pressEnter.message "Press enter to continue"
  ENTER_MESSAGE="${_prop_value}"
  readonly ENTER_MESSAGE
}

# Make sure youre logfile is gone before you start appending to it
function remove_existing_log
{
  rm -f      ${LOG_FILE} > /dev/null 2>&1
  touch      ${LOG_FILE} > /dev/null 2>&1
  chmod 0666 ${LOG_FILE} > /dev/null 2>&1
}

# Close and persist log
function close_log
{
  SECONDS_SINCE_EPOCH=$(date +%s)

  # Copy log withing tmp
  cp -f ${LOG_FILE} /tmp/${LOG_FILE_NAME}_${SECONDS_SINCE_EPOCH}.log > /dev/null 2>&1

  # Copy log to install dir
  local persisted_log="${INSTALL_DIR}/logs/${LOG_FILE_NAME}_${SECONDS_SINCE_EPOCH}.log"
  mv -f ${LOG_FILE} "${persisted_log}" > /dev/null 2>&1
  chmod 0666 "${persisted_log}" > /dev/null 2>&1
}

# Echo the provided string both to the screen and the install log
#
# ${1} If -n, don't print a new line
#      If -r, read user input
#      Or, this is a string to print
# ${2} if ${1} was -n or -r, then this is the string to print
function echolog
{
  if [ "${1}" = "-n" ]; then
    # Omit the newline
    echo -n "${2}"
    echo -n "${2}"   >> "${LOG_FILE}"
  elif [ "${1}" = "-r" ]; then
    # Prompt the user and then log the prompt and response
    # Adds a space between the string and the user's input
    read -p "${2} "
    echo -n "${2} "  >> "${LOG_FILE}"
    echo "${REPLY}"  >> "${LOG_FILE}"
  else
    echo "${1}"
    echo "${1}"      >> "${LOG_FILE}"
  fi
}

function echolog_prop_value
{
  if [ "${1}" = "-n" ]; then
    # Omit the newline
    get_install_prop_value "${2}" "${3}"
    echolog -n "${_prop_value}"
  elif [ "${1}" = "-r" ]; then
    # Prompt the user and then log the prompt and response
    get_install_prop_value "${2}" "${3}"
    echolog -r "${_prop_value}"
  else
    get_install_prop_value "${1}" "${2}"
    echolog "${_prop_value}"
  fi
}

function log
{
  if [ "${1}" = "-n" ]; then
    # Omit the newline
    echo -n "${2}"  >> "${LOG_FILE}"
  else
    echo "${1}"     >> "${LOG_FILE}"
  fi
}

function get_user_response
{
  _resp_yes=false
  _resp_no=false
  _resp_default=false

  if echo ${REPLY} | grep -x "\s*" > /dev/null 2>&1; then
    _resp_default=true
  elif echo ${REPLY} | grep "^[yY]\([eE][sS]\)\?$" > /dev/null 2>&1; then
    _resp_yes=true
  elif echo ${REPLY} | grep "^[mM][aA][yY][bB][eE]$" > /dev/null 2>&1; then
    echolog "Make up your mind, homedog!!! I'll assume you'll just be default..."
    _resp_default=true
  elif echo ${REPLY} | grep "^[nN]\([oO]\)\?$" > /dev/null 2>&1; then
    _resp_no=true
  fi
}

function invalid_entry
{
  echolog
  echolog_prop_value userEntry.invalidOption "You have entered an invalid option. Please try again."
  echolog
  sleep 1
}

function invalid_path
{
  echolog
  get_install_prop_value userEntry.invalidPath "It appears that you provided an invalid directory or a relative path. Please provide another path."
  echolog "$(echo "${_prop_value}" | fold -s)" 
  echolog
  sleep 1
}

function error_handler
{
  #0 = OK
  #X = FAILURE
  #2 = WARNING
  if (( _error == 0 )); then
    ${SETFORE_WHITE} && ${SETBACK_GREEN} && ${MOVE_TO_COL_65}
    echolog -n "${SUCCESS_MESSAGE}"
    ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
  elif (( _error == 2 )); then
    ${SETFORE_WHITE} && ${SETBACK_BROWN} && ${MOVE_TO_COL_65}
    echolog -n "${WARNING_MESSAGE}"
    ${SETFORE_NORMAL} && ${SETBACK_NORMAL} 
  else
    ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
    echolog -n "${FAILURE_MESSAGE}"
    ${SETFORE_NORMAL} && ${SETBACK_NORMAL} 
  fi
  echolog
  _error=0
}

# Get properties from the install.properties file located in install_data
# arguments
# 1 - String : Key in props file you want to locate
# 2 - String : Default value for string in case you don't find the key
function get_install_prop_value
{
  if [ ! -r "${PROPS_FILE}" ]; then
    echolog "The Niagara 4 installer cannot locate ${PROPS_FILE}, closing."
    echolog
    sleep 2
    exit 1
  fi

  get_prop_value "${PROPS_FILE}" "${1}" "${2}"
}

# Get properties from the brand.properties file located in overlay/lib
# arguments
# 1 - String : Key in props file you want to locate
# 2 - String : Default value for string in case you don't find the key
function get_brand_prop_value
{
  if [ ! -r "${BRAND_PROPS_FILE}" ]; then
    _prop_value="${2}"
    return
  fi

  get_prop_value "${BRAND_PROPS_FILE}" "${1}" "${2}"
}

function get_prop_value
{
  local key="${2}"
  local default="${3}"
  _prop_value=

  # Search for the key within the properties file
  local target_tuple="$(cat "${1}" | grep -o -m 1 "^${key}=.*$")"

  if [ "${target_tuple}" ]; then
    # Item found; remove the key from the value
    _prop_value="${target_tuple#"${key}="}"
  fi

  # Substitute default if the key cannot be found
  _prop_value="${_prop_value:="${default}"}"

  # Make sure there are no unsupported characters in the replacement
  _prop_value="$(echo "${_prop_value}" | grep -o "[][A-Za-z0-9 -\\%!.,:;]*")"

  local copy
  local first
  local rest

  while echo "${_prop_value}" | grep %version% > /dev/null 2>&1; do
    copy="${_prop_value}"
    first="${_prop_value%%%version%*}"
    _prop_value="${copy}"
    rest="${_prop_value#*%version%}"
    _prop_value="${first}${VERSION}${rest}"
  done
}

# Searches the uninstall file in reverse to get the most recent value
function get_uninstall_prop_value
{
  if [ ! -r "${INSTALL_DIR}/uninstall/uninstall.conf" ]; then
    _prop_value="${2}"
    return
  fi

  local key="${1}"
  local default="${2}"
  _prop_value=

  # Search for the key within the properties file
  local target_tuple="$(tac "${INSTALL_DIR}/uninstall/uninstall.conf" | grep -o -m 1 "^${key}=.*$")"

  if [ "${target_tuple}" ]; then
    # Item found; remove the key from the value
    _prop_value="${target_tuple#"${key}="}"
  fi

  # Substitute default if the key cannot be found
  _prop_value="${_prop_value:="${default}"}"
}

function get_brand_id
{
  BRAND_ID=
  if [ -r "${BRAND_PROPS_FILE}" ]; then
    local target_tuple="$(cat "${BRAND_PROPS_FILE}" | grep -o -m 1 "^brand.id=.*$")"
    if [ "${target_tuple}" ]; then
      BRAND_ID="${target_tuple#"brand.id="}"
      # Brand ID validation is similar to path validation because the brand ID is used to
      # create paths and get the branded license file.
      BRAND_ID="$(echo "${BRAND_ID}" | grep -o "[-%~A-Za-z0-9._]*")"
      log "Found brand ID ${BRAND_ID}"
    else
      log "No brand id found in ${BRAND_PROPS_FILE}"
    fi
  else
    log "No brand.properties file at ${BRAND_PROPS_FILE}"
  fi

  readonly BRAND_ID
  
  MENU_FILE_PATH=".config/menus/applications-merged/${BRAND_ID:-Niagara}_${VERSION}.menu"
  DIRECTORY_FILE_NAME="${BRAND_ID:-Niagara}_${VERSION}.directory"
  DIRECTORY_FILE_PATH=".local/share/desktop-directories/${DIRECTORY_FILE_NAME}"
  WB_MENU_FILE_NAME="${BRAND_ID:-Niagara}_${VERSION}_wb.desktop"
  WBW_MENU_FILE_NAME="${BRAND_ID:-Niagara}_${VERSION}_wb_w.desktop"
  CONSOLE_MENU_FILE_NAME="${BRAND_ID:-Niagara}_${VERSION}_console.desktop"
  ALARM_PORTAL_MENU_FILE_NAME="${BRAND_ID:-Niagara}_${VERSION}_alarm_portal.desktop"
  
  readonly MENU_FILE_PATH
  readonly DIRECTORY_FILE_NAME
  readonly DIRECTORY_FILE_PATH
  readonly WB_MENU_FILE_NAME
  readonly WBW_MENU_FILE_NAME
  readonly CONSOLE_MENU_FILE_NAME
  readonly ALARM_PORTAL_MENU_FILE_NAME
}

function get_default_install_dir
{
  get_install_prop_value installDirectory.defaultFolder "/opt/Niagara/${BRAND_ID:-Niagara}-${VERSION}"
  DEFAULT_INSTALL_DIR="${_prop_value}"
  readonly DEFAULT_INSTALL_DIR
}

function scrub_script
{
  if [ -e "${1}" ]; then
    if (${_is_redhat} && ! dos2unix "${1}" >> ${LOG_FILE} 2>&1) ||
       (${_is_amazon} && ! dos2unix "${1}" >> ${LOG_FILE} 2>&1) ||
       (${_is_debian} && ! fromdos  "${1}" >> ${LOG_FILE} 2>&1); then
      echolog
      echolog "Failed to scrub the script ${1}."
      close
    fi
  else
    echolog
    echolog "Could not find script to be scrubbed: ${1}."
    close
  fi
}

function scrub_props_files
{
  scrub_script "${PROPS_FILE}"

  if [ -r "${BRAND_PROPS_FILE}" ]; then
    scrub_script "${BRAND_PROPS_FILE}"
  fi
}

function check_if_root
{
  if (( ${CURRENT_UID} != 0 )); then
    echolog
    echolog "The Niagara 4 installer must be run as root."
    close
  fi
}

function check_os
{
  # Check and set the operating system!
  if [ -e "/etc/redhat-release" ] &&
     (grep -q -i "release 7" /etc/redhat-release ||
      grep -q -i "release 8" /etc/redhat-release    ); then
    _is_redhat=true
    _is_debian=false
    _is_amazon=false
  elif [ -e "/etc/os-release" ] &&
       grep -q -i "NAME=\"Amazon Linux\"" /etc/os-release &&
       grep -q -i "VERSION=\"2\"" /etc/os-release; then
    _is_amazon=true              
    _is_debian=false
    _is_redhat=false
  else
    echolog
    echolog "The Niagara 4 installer has detected that you are not running a supported Linux "
    echolog "distribution (Red Hat EL 7)."
    echolog
    echolog "The installer cannot continue. Sorry!"
    close
  fi

  readonly _is_debian
  readonly _is_redhat
  readonly _is_amazon
  
  echolog "Installing on $(uname -a)"
}

function check_pwd
{
  if [ ! -e "../uninstall/uninstall.conf" -a ! -e "../install/niagarad_generic" ]; then
    echolog
    ${SETFORE_WHITE} && ${SETBACK_RED}
    echolog -n "FAILURE"
    ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
    echolog
    echolog ": this Niagara 4 action cannot be completed from the current directory."
    echolog "Please restart this script from the !/install directory under the target "
    echolog "Niagara 4 installation."
    close
  else
    # Get install dir
    cd ..
    INSTALL_DIR=$(pwd)
    readonly INSTALL_DIR
    cd install
  fi
}

function load_uninstall_conf
{
  if [ ! -e "${INSTALL_DIR}/uninstall/uninstall.conf" ]; then
    echolog
    ${SETFORE_WHITE} && ${SETBACK_BROWN}
    echolog -n "WARNING"
    ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
    echolog ": uninstall.conf could not be located."
    echolog "(${INSTALL_DIR}/uninstall/uninstall.conf)"
    echolog
    echolog "If you continue the uninstallation process without \"uninstall.conf\", this"
    echolog "script will be unable to determine which and where Niagara 4 files were "
    echolog "installed if they were installed somewhere other than the default locations."
    echolog

    while true; do
      echolog_prop_value -r uninstallStart.noConfQuery "Do you want to continue without uninstall.conf? [yes/NO]:"
      get_user_response

      if ${_resp_yes}; then
        echolog
        echolog_prop_value uninstallStart.noConfContinue "Uninstallation will continue with default values."
        load_uninstall_info
        break
      elif ${_resp_no} || ${_resp_default}; then
        close
      fi

      invalid_entry
    done
  else
    echolog
    echolog_prop_value -n uninstallStart.gatherInformation "Gathering information about your Niagara installation..."
    load_uninstall_info
    error_handler
  fi
}

function load_uninstall_info
{
  get_uninstall_prop_value "USR_BIN_INSTALLED" "true"
  _installed_usr_bin="${_prop_value}"
  get_uninstall_prop_value "SERVICE" "true"
  _installed_service="${_prop_value}"
}

function executable_not_found
{
  echolog
  echolog "The Niagara 4 installer has determined that the required executable "
  echolog "\"${1}\" "
  echolog "was not found. Please check that the application is installed."
}

# Check dependencies
function check_executables
{
  echolog
  echolog -n "Checking executable dependencies..."
  for file in ${COMMON_FILES}; do
    if [ ! -x "${file}" ]; then
      ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
      echolog -n "FAILED"
      ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
      executable_not_found "${file}"
      close
    fi
  done

  if ${_is_redhat}; then
    for file in ${REDHAT_FILES}; do
      if [ ! -x "${file}" ]; then
        ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
        echolog -n "FAILED"
        ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
        executable_not_found "${file}"
        close
      fi
    done

    # Make special check for dos2unix, which may not come standard.  Provide the
    # yum command to retrieve and install the package.
    local dos2unix_file="/usr/bin/dos2unix"
    if [ ! -x "${dos2unix_file}" ]; then
      ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
      echolog -n "FAILED"
      ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
      executable_not_found "${dos2unix_file}"
      echolog
      echolog "Execute \"sudo yum install dos2unix\" to retrieve and install it as a package."
      close
    fi

  elif ${_is_debian}; then
    for file in ${DEBIAN_FILES}; do
      if [ ! -x "${file}" ]; then
        ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
        echolog -n "FAILED"
        ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
        executable_not_found "${file}"
        close
      fi
    done
  
  elif ${_is_amazon}; then
    for file in ${AMAZON_FILES}; do
      if [ ! -x "${file}" ]; then
        ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
        echolog -n "FAILED"
        ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
        executable_not_found "${file}"
        close
      fi
    done

    # Make special check for dos2unix, which may not come standard.  Provide the
    # yum command to retrieve and install the package.
    local dos2unix_file="/usr/bin/dos2unix"
    if [ ! -x "${dos2unix_file}" ]; then
      ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
      echolog -n "FAILED"
      ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
      executable_not_found "${dos2unix_file}"
      echolog
      echolog "Execute \"sudo yum install dos2unix\" to retrieve and install it as a package."
      close
    fi  
  fi

  ${SETFORE_WHITE} && ${SETBACK_GREEN}  && ${MOVE_TO_COL_65}
  echolog -n "SUCCESS"
  ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
}

function check_cmd_arg_format
{
  # We have dependencies on some of the arguments to groupadd, useradd,
  # and usermod so let's determine what these exes expect

  # Check groupadd

  if /usr/sbin/groupadd 2>&1 | /bin/grep "\-\-force" > /dev/null 2>&1; then
    _groupadd_force_arg="--force"
  elif /usr/sbin/groupadd 2>&1 | /bin/grep "\-f" > /dev/null 2>&1; then
    _groupadd_force_arg="-f"
  else
    echolog "WARNING: /usr/sbin/groupadd does not support \"force\" as an argument."
  fi

  readonly _groupadd_force_arg

  if /usr/sbin/groupadd 2>&1 | /bin/grep "\-\-gid" > /dev/null 2>&1; then
    _groupadd_gid_arg="--gid"
  elif /usr/sbin/groupadd 2>&1 | /bin/grep "\-g" > /dev/null 2>&1; then
    _groupadd_gid_arg="-g"
  else
    echolog "WARNING: /usr/sbin/groupadd does not support \"gid\" as an argument."
  fi

  readonly _groupadd_gid_arg

  # Check useradd

  if /usr/sbin/useradd 2>&1 | /bin/grep "\-\-comment" > /dev/null 2>&1; then
    _useradd_comment_arg="--comment"
  elif /usr/sbin/useradd 2>&1 | /bin/grep "\-c" > /dev/null 2>&1; then
    _useradd_comment_arg="-c"
  else
    echolog "WARNING: /usr/sbin/useradd does not support \"comment\" as an argument."
  fi

  readonly _useradd_comment_arg

  if /usr/sbin/useradd 2>&1 | /bin/grep "\-\-create\-home" > /dev/null 2>&1; then
    _useradd_create_home_arg="--create-home"
  elif /usr/sbin/useradd 2>&1 | /bin/grep "\-m" > /dev/null 2>&1; then
    _useradd_create_home_arg="-m"
  else
    echolog "WARNING: /usr/sbin/useradd does not support \"-m\" as an argument."
  fi

  readonly _useradd_create_home_arg

  if /usr/sbin/useradd 2>&1 | /bin/grep "\-\-shell" > /dev/null 2>&1; then
    _useradd_shell_arg="--shell"
  elif /usr/sbin/useradd 2>&1 | /bin/grep "\-s" > /dev/null 2>&1; then
    _useradd_shell_arg="-s"
  else
    echolog "WARNING: /usr/sbin/useradd does not support \"shell\" as an argument."
  fi

  readonly _useradd_shell_arg

  if /usr/sbin/useradd 2>&1 | /bin/grep "\-\-uid" > /dev/null 2>&1; then
    _useradd_uid_arg="--uid"
  elif /usr/sbin/useradd 2>&1 | /bin/grep "\-u" > /dev/null 2>&1; then
    _useradd_uid_arg="-u"
  else
    echolog "WARNING: /usr/sbin/useradd does not support \"uid\" as an argument."
  fi

  readonly _useradd_uid_arg

  if /usr/sbin/useradd 2>&1 | /bin/grep "\-\-gid" > /dev/null 2>&1; then
    _useradd_gid_arg="--gid"
  elif /usr/sbin/useradd 2>&1 | /bin/grep "\-g" > /dev/null 2>&1; then
    _useradd_gid_arg="-g"
  else
    echolog "WARNING: /usr/sbin/useradd does not support \"gid\" as an argument."
  fi

  readonly _useradd_gid_arg

  if [ -x "/sbin/nologin" ]; then
    _useradd_nologin_arg="/sbin/nologin"
  elif [ -x "/bin/false" ]; then
    _useradd_nologin_arg="/bin/false"
  elif [ -x "/usr/sbin/nologin" ]; then
    _useradd_nologin_arg="/usr/sbin/nologin"
  else
    echolog "WARNING: \"nologin\" or \"false\" shell type not found."
  fi

  readonly _useradd_nologin_arg

  # Check usermod

  if /usr/sbin/usermod 2>&1 | /bin/grep "\-a" > /dev/null 2>&1; then
    _usermod_append_arg="-a"
  else
    echolog "WARNING: /usr/sbin/usermod does not support \"append\" as an argument."
  fi

  readonly _usermod_append_arg

  if /usr/sbin/usermod 2>&1 | /bin/grep "\-G" > /dev/null 2>&1; then
    _usermod_groups_arg="-G"
  else
    echolog "WARNING: /usr/sbin/usermod does not support \"groups\" as an argument."
  fi

  readonly _usermod_groups_arg

  log
  log "groupadd force: ${_groupadd_force_arg}"
  log "groupadd gid: ${_groupadd_gid_arg}"
  log "useradd comment: ${_useradd_comment_arg}"
  log "useradd create home: ${_useradd_create_home_arg}"
  log "useradd shell: ${_useradd_shell_arg}"
  log "useradd uid: ${_useradd_uid_arg}"
  log "useradd gid: ${_useradd_gid_arg}"
  log "usermod append: ${_usermod_append_arg}"
  log "usermod groups: ${_usermod_groups_arg}"
}

function create_app_launcher
{
  # sort of like ndlaucher, but doesn't make strict checks on perms, but can
  # only launch niagara apps (wb, install, uninstall)?
  # this allows us to create desktop icons and menu icons, etc...

  echolog -n "Creating Niagara application launcher..."

  # as a failsafe, create the bin dir?
  if [ ! -d "${INSTALL_DIR}/bin" ]; then
    mkdir -p "${INSTALL_DIR}/bin" >> ${LOG_FILE} 2>&1
  fi

  touch "${INSTALL_DIR}/bin/${LAUNCHER_NAME}" >> ${LOG_FILE} 2>&1
  cat > "${INSTALL_DIR}/bin/${LAUNCHER_NAME}" << _EOF_
#!/bin/bash
unset niagara_home
export niagara_home="${INSTALL_DIR}"
declare -r VALID_APPS="\${niagara_home}/bin/wb
\${niagara_home}/install/install_service.sh
\${niagara_home}/bin/station
\${niagara_home}/uninstall/uninstall_service.sh
\${niagara_home}/uninstall/uninstall.sh"

VALID=false
SAVE_IFS=${IFS}
IFS="
"
for CUR_APP in \${VALID_APPS}; do
  if [ "\${1}" = "\${CUR_APP}" ]; then
    VALID=true
    break
  fi
done
IFS=${SAVE_IFS}

if ! \${VALID}; then
  echo "ERROR: ${LAUNCHER_NAME} not configured to launch \${1}."
  unset niagara_home
  sleep 2
  exit 1
fi

if [ -f "\${niagara_home}/bin/.niagara" ]; then
  . "\${niagara_home}/bin/.niagara"
else
  echo "ERROR: \${niagara_home}/bin/.niagara not found! Can't launch \${1}."
  unset niagara_home
  sleep 2
  exit 1
fi

if [ "\${1}" = "\${niagara_home}/install/install_service.sh" ]; then
  # installer expects to launch from install dir, so switch
  cd "\${niagara_home}/install"
elif [ "\${1}" = "\${niagara_home}/uninstall/uninstall.sh" ]; then
  # uninstaller expects to launch from uninstall dir, so switch
  cd "\${niagara_home}/uninstall"
elif [ "\${1}" = "\${niagara_home}/uninstall/uninstall_service.sh" ]; then
  # uninstaller expects to launch from uninstall dir, so switch
  cd "\${niagara_home}/uninstall"
fi
"\${@}"
_EOF_

  _error=0
  error_handler
}

function get_primary_group
{
  #determine this user's primary group, should be the first group in the output of group : ${user}
  _primary_group=""
  local second_is_colon
  second_is_colon=$(groups ${user} | awk '{ print $2 }')
  if [ "${second_is_colon}" = ":" ]; then
    _primary_group=$(groups ${user} | awk '{ print $3 }')
  else
    _primary_group=$(groups ${user} | awk '{ print $1 }')
  fi
}

function prompt_desktop_shortcuts
{
  while true && (( ${_users_count} >= 1 )); do
    echolog
    echolog_prop_value -r installShortcut.desktopShortcuts "Do you want to install GNOME desktop shortcuts for the configured users? [yes/NO]:"
    get_user_response

    if ${_resp_no} || ${_resp_default}; then
      _install_desktop_shortcuts=false
      break;
    elif ${_resp_yes}; then
      _install_desktop_shortcuts=true
      break;
    fi

    invalid_entry
  done
}

function prompt_menu_shortcuts
{
  # Can the menu items be installed for users individually? I would
  # have to ask when I add the user and maintain a separate array,
  # create a tuple like desktop_users, menu_users, none_users?
  while true && (( ${_users_count} >= 1 )); do
    echolog
    echolog_prop_value -r installShortcut.menuShortcuts "Do you want to install GNOME menu shortcuts for the configured users? [YES/no]:"
    get_user_response

    if ${_resp_yes} || ${_resp_default}; then
      _install_menu_shortcuts=true
      break;
    elif ${_resp_no}; then
      _install_menu_shortcuts=false
      break;
    fi

    invalid_entry
  done
}

function get_existing_users
{
  _existing_users=($(cat /etc/group | grep --regex "^${NIAGARA_GROUP}:.*" | awk -F: '{print $4}' | tr "," " "))
  _existing_users_count=${#_existing_users[@]}
}

function print_existing_users
{
  if [[ ${_existing_users_count} != 0 ]]; then
    echolog
    echolog_prop_value adduserCurrentUsers.message "The following users belong to the group ${NIAGARA_GROUP}:"
    echolog

    local idx
    for ((idx=0; ${idx}<${_existing_users_count}; idx++)); do
      echolog -n "${_existing_users[${idx}]} "
    done
    echolog
  fi
}

function create_users_of_niagara
{
  local result
  local user
  local dir
  local idx

  # make sure we are appending
  if (( ${_users_count} > 0 )); then
    echolog "Adding configured users to the group ${NIAGARA_GROUP}..."

    for ((idx=0; ${idx}<${_users_count}; idx++)); do
      user=${_users[${idx}]}
      echolog -n "${user} "

      if ! /usr/sbin/usermod ${_usermod_append_arg} \
                             ${_usermod_groups_arg} \
                             ${NIAGARA_GROUP}       \
                             ${user} >> ${LOG_FILE} 2>&1; then
        result="${?}"
        _error=1
        error_handler
        echolog "Failed to add ${user} to the group ${NIAGARA_GROUP}: ${result}"
        close
      fi

      local niagara_dir="/home/${user}/Niagara4.9"
      local brand_dir="${niagara_dir}/${BRAND_ID:-"tridium"}"

      get_primary_group

      if ! mkdir -p "${brand_dir}" ||
         ! chown "${user}":"${_primary_group}" "${niagara_dir}" ||
         ! chown "${user}":"${_primary_group}" "${brand_dir}"; then
        _error=1
        error_handler
        echolog "Failed to create a niagara user home for user ${user}: "
        echolog "${brand_dir}"
        close
      fi

      _error=0
      error_handler
    done
  fi
}

function remove_users_of_niagara
{
  local user
  local idx

  # Assume if you find the user id in the system that the group also exists.
  if (( ${_users_count} > 0 )); then
    echolog "Removing users from the group ${NIAGARA_GROUP}..."
    for ((idx=0; ${idx}<${_users_count}; idx++)); do
      user=${_users[${idx}]}
      echolog -n "${user} "

      # Old way:
      #local user_groups
      #local -a user_groups_array
      #local -i user_groups_array_count
      #local group_delimited_string
      #local idx2
      #
      # Get current groups
      #user_groups="$(id -nG ${user})"
      #
      # Get all groups but 'niagara'
      #user_groups_array="(${user_groups%%${NIAGARA_GROUP}})"
      #user_groups_array_count=${#user_groups_array[@]}
      #
      # Now safely build comma separated list of groups (probably a more elegant
      # way to do this, but, eh)
      #group_delimited_string=
      #for ((idx2=0; ${idx2}<${user_groups_array_count}; idx2++)); do
      #  group_delimited_string="${group_delimited_string}${user_groups_array[${idx2}]},"
      #done
      #
      #remove last instance of comma
      #group_delimited_string="${group_delimited_string%%,}"
      #
      #if /usr/sbin/usermod  ${USERMOD_GROUPS_ARG} ${GROUP_DELIMITED_STRING} ${user} > /dev/null 2>&1; then
      #  _error=0
      #else
      #  #if this failed, that sucks
      #  _error=1
      #  break
      #fi

      if gpasswd --delete ${user} ${NIAGARA_GROUP} >> ${LOG_FILE} 2>&1; then
        _error=0
      else
        _error=1
      fi
      error_handler
    done
  fi
}

# Create the desktop shortcuts for any user in the users array
function install_desktop_shortcuts
{
  # copy the icon we want to use for the menu, make this more generic in the future...
  if [ -e ./install-data/workbench.png ]; then
    if [ ! -e /usr/share/icons/hicolor/48x48/apps/workbench.png ]; then
      cp ./install-data/workbench.png /usr/share/icons/hicolor/48x48/apps
      chown root:root /usr/share/icons/hicolor/48x48/apps/workbench.png
      chmod 0644 /usr/share/icons/hicolor/48x48/apps/workbench.png
    fi
  fi

  if [ -e ./install-data/alarmportal.png ]; then
    if [ ! -e /usr/share/icons/hicolor/48x48/apps/alarmportal.png ]; then
      cp ./install-data/alarmportal.png /usr/share/icons/hicolor/48x48/apps
      chown root:root /usr/share/icons/hicolor/48x48/apps/alarmportal.png
      chmod 0644 /usr/share/icons/hicolor/48x48/apps/alarmportal.png
    fi
  fi

  local idx
  local user
  for ((idx=0; ${idx}<${_users_count}; idx++)); do
    user=${_users[${idx}]}
    echolog -n "Adding GNOME desktop shortcuts for user ${user}..."

    if [ ! -d "/home/${user}/Desktop" ]; then
      #error, directory did not exist for this user
      _error=1
      error_handler
      echolog
      echolog "Could not install desktop shortcuts for user ${user}."
      echolog "The directory /home/${user}/Desktop was not found and"
      echolog "it is assumed that this user does not have a desktop environment."
      echolog
      continue;
    fi

    get_primary_group

    # user level executables
    install_desktop_shortcuts_helper "wb_w" "${user}" "${_primary_group}"
    install_desktop_shortcuts_helper "alarm_portal" "${user}" "${_primary_group}"

    _error=0
    error_handler
  done
}

function install_desktop_shortcuts_helper
{
  # ${1} is the file to install (which app)
  # ${2} is where you want to install it (which user), and who will own it
  # ${3} is the group that want to own the file, ideally ${2}'s primary group

  local target_user="${2}"
  local target_group="${3}"
  get_install_prop_value shortcut.${1}.Name "${PROPS_ERROR}"
  local shortcut_path="/home/${target_user}/Desktop/${_prop_value}.desktop"

  echo ""                                                        >  "${shortcut_path}"
  echo "[Desktop Entry]"                                         >> "${shortcut_path}"
  get_install_prop_value shortcut.${1}.Version "${PROPS_ERROR}"
  echo "Version=${_prop_value}"                                  >> "${shortcut_path}"
  echo "Type=Application"                                        >> "${shortcut_path}"
  get_install_prop_value shortcut.${1}.Terminal "${PROPS_ERROR}"
  echo "Terminal=${_prop_value}"                                 >> "${shortcut_path}"

  # make sure icon is there, if not, use default
  get_install_prop_value shortcut.${1}.LIcon "${PROPS_ERROR}"
  if [ ! -e "${_prop_value}" ]; then
    get_install_prop_value shortcut.${1}.DefaultIcon "${PROPS_ERROR}"
  fi
  echo "Icon[en_US]=${_prop_value}"                              >> "${shortcut_path}"

  get_install_prop_value shortcut.${1}.LName "${PROPS_ERROR}"
  echo "Name[en_US]=${_prop_value}"                              >> "${shortcut_path}"

  if [ "${1}" = "console" ]; then
    echo "Exec=gnome-terminal --working-directory=\"${INSTALL_DIR}\" --title=\"Niagara Command Line\" --command=\"bash --rcfile \\\"${INSTALL_DIR}/bin/.niagara\\\"\"" >> "${shortcut_path}"
  else
    get_install_prop_value shortcut.${1}.Exec "${PROPS_ERROR}"
    echo -n "Exec=\"${INSTALL_DIR}/bin/${LAUNCHER_NAME}\" \"${INSTALL_DIR}/${_prop_value}\"" >> "${shortcut_path}"
    get_install_prop_value shortcut.${1}.Args ""
    if [ "${_prop_value}" = "" ]; then
      echo >> "${shortcut_path}"
    else
      echo " ${_prop_value}" >> "${shortcut_path}"
    fi
  fi

  get_install_prop_value shortcut.${1}.LComment "${PROPS_ERROR}"
  echo "Comment[en_US]=${_prop_value}"                           >> "${shortcut_path}"
  get_install_prop_value shortcut.${1}.Name "${PROPS_ERROR}"
  echo "Name=${_prop_value}"                                     >> "${shortcut_path}"
  get_install_prop_value shortcut.${1}.Comment "${PROPS_ERROR}"
  echo "Comment=${_prop_value}"                                  >> "${shortcut_path}"

  # make sure icon is there, if not, use default
  get_install_prop_value shortcut.${1}.Icon "${PROPS_ERROR}"
  if [ ! -e "${_prop_value}" ]; then
    get_install_prop_value shortcut.${1}.DefaultIcon "${PROPS_ERROR}"
  fi
  echo "Icon=${_prop_value}"                                     >> "${shortcut_path}"

  chown "${target_user}:${target_group}" "${shortcut_path}"
  chmod 0755 "${shortcut_path}"
  
  # mark desktop files as trusted
  # NOTE: Even when running as root, or as the actual user through "runuser" or "sudo",
  #       this still appears to create the error message:
  #
  #           gio: Setting attribute metadata::trusted not supported
  #
  #       This command only appears to run successfully when run as the actual user
  #       through their own GUI terminal. It is not clear what is different about this
  #       terminal versus runuser/sudo, or why the action is not available to root
  #       under all circumstances. Print a warning to the user that they will need
  #       to run this command (or "Trust and Launch" the desktop icon) in order for the
  #       icons to appear. https://stackoverflow.com/questions/51747456/is-it-possible-to-modify-gnome-desktop-file-metadata-from-non-gui-session-using
  #
  runuser -u "${target_user}" -g "${target_group}" gio set "${shortcut_path}" "metadata::trusted" yes >> ${LOG_FILE} 2>&1
  if [ ${?} != 0 ]; then
    _error=2
    error_handler  
    BASENAME=$(basename "${shortcut_path}")
    echolog
    echolog "Could not programmatically trust desktop shortcut '${BASENAME}' for user '${user}'."
    echolog "Please run 'gio set \"${shortcut_path}\" \"metadata::trusted\" yes' or \"Trust and Launch\" this icon after installation".
    echolog      
  fi
}

# Create the menu shortcuts for any user in the users array
function install_menu_shortcuts
{
  # copy the icon we want to use for the menu, make this more generic in the future...
  if [ -e ./install-data/gnome-panel-workbench.png ]; then
    if [ ! -e /usr/share/icons/hicolor/32x32/apps/gnome-panel-workbench.png ]; then
      cp ./install-data/gnome-panel-workbench.png /usr/share/icons/hicolor/32x32/apps
      chown root:root /usr/share/icons/hicolor/32x32/apps/gnome-panel-workbench.png
      chmod 0644 /usr/share/icons/hicolor/32x32/apps/gnome-panel-workbench.png
    fi
  fi

  if [ -e ./install-data/gnome-panel-console.png ]; then
    if [ ! -e /usr/share/icons/hicolor/32x32/apps/gnome-panel-console.png ]; then
      cp ./install-data/gnome-panel-console.png /usr/share/icons/hicolor/32x32/apps
      chown root:root /usr/share/icons/hicolor/32x32/apps/gnome-panel-console.png
      chmod 0644 /usr/share/icons/hicolor/32x32/apps/gnome-panel-console.png
    fi
  fi
  
  if [ -e ./install-data/gnome-panel-alarmportal.png ]; then
    if [ ! -e /usr/share/icons/hicolor/32x32/apps/gnome-panel-alarmportal.png ]; then
      cp ./install-data/gnome-panel-alarmportal.png /usr/share/icons/hicolor/32x32/apps
      chown root:root /usr/share/icons/hicolor/32x32/apps/gnome-panel-alarmportal.png
      chmod 0644 /usr/share/icons/hicolor/32x32/apps/gnome-panel-alarmportal.png
    fi
  fi

  local idx
  local user
  for ((idx=0;${idx}<${_users_count};idx++)); do
    user=${_users[${idx}]}
    echolog -n "Adding GNOME menu shortcuts for user ${user}..."

    if [ ! -d "/home/${user}/Desktop" ]; then
      #error, directory did not exist for this user
      _error=1
      error_handler
      echolog
      echolog "Could not install menu shortcuts for user ${user}."
      echolog "The directory /home/${user}/Desktop was not found and"
      echolog "it is assumed that this user does not have a desktop environment."
      echolog
      continue;
    fi

    get_primary_group

    # Make sure necessary files are in .config dir

    #check for the users application menu
    if [ ! -e "/home/${user}/.config/menus/applications.menu" ]; then
      #make sure they have a .config dir
      if [ ! -d "/home/${user}/.config" ]; then
        mkdir /home/${user}/.config
        chown ${user}:${_primary_group} /home/${user}/.config
        chmod 0755 /home/${user}/.config
      fi

      #make sure they have a menus dir
      if [ ! -d "/home/${user}/.config/menus" ]; then
        mkdir /home/${user}/.config/menus
        chown ${user}:${_primary_group} /home/${user}/.config/menus
        chmod 0755 /home/${user}/.config/menus
      fi

      #attempt to create file?
      cat > /home/${user}/.config/menus/applications.menu << _EOF_
<!DOCTYPE Menu PUBLIC '-//freedesktop//DTD Menu 1.0//EN'
  'http://standards.freedesktop.org/menu-spec/menu-1.0.dtd'>
<Menu>
  <Name>Applications</Name>
  <MergeFile type="parent">/etc/xdg/menus/applications.menu</MergeFile>
  <DefaultLayout inline="false"/>
</Menu>
_EOF_

      chown ${user}:${_primary_group} /home/${user}/.config/menus/applications.menu
      chmod 0755 /home/${user}/.config/menus/applications.menu
    fi

    #check for the users settings menu
    if [ ! -e "/home/${user}/.config/menus/settings.menu" ]; then
      #no applications dir?
      if [ ! -d "/home/${user}/.config" ]; then
        #not even a directory?
        mkdir /home/${user}/.config
        chown ${user}:${_primary_group} /home/${user}/.config
        chmod 0755 /home/${user}/.config
      fi

      if [ ! -d "/home/${user}/.config/menus" ]; then
        #not even a directory?
        mkdir /home/${user}/.config/menus
        chown ${user}:${_primary_group} /home/${user}/.config/menus
        chmod 0755 /home/${user}/.config/menus
      fi

      #attempt to create file?
      cat > /home/${user}/.config/menus/settings.menu << _EOF_
<!DOCTYPE Menu
  PUBLIC '-//freedesktop//DTD Menu 1.0//EN'
  'http://standards.freedesktop.org/menu-spec/menu-1.0.dtd'>
<Menu>
  <Name>Desktop</Name>
  <MergeFile type="parent">/etc/xdg/menus/settings.menu</MergeFile>
</Menu>
_EOF_

      chown ${user}:${_primary_group} /home/${user}/.config/menus/settings.menu
      chmod 0755 /home/${user}/.config/menus/settings.menu
    fi

    if [ ! -d "/home/${user}/.config/menus/applications-merged" ]; then
      #no applications dir?
      if [ ! -d "/home/${user}/.config" ]; then
        #not even a directory?
        mkdir /home/${user}/.config
        chown ${user}:${_primary_group} /home/${user}/.config
        chmod 0755 /home/${user}/.config
      fi

      if [ ! -d "/home/${user}/.config/menus" ]; then
        #not even a directory?
        mkdir /home/${user}/.config/menus
        chown ${user}:${_primary_group} /home/${user}/.config/menus
        chmod 0755 /home/${user}/.config/menus
      fi

      mkdir /home/${user}/.config/menus/applications-merged
      chown ${user}:${_primary_group} /home/${user}/.config/menus/applications-merged
      chmod 0755 /home/${user}/.config/menus/applications-merged
    fi

    if [ ! -e "/home/${user}/.config/gtk-2.0/gtkfilechooser.ini" ]; then
      #no ini file?
      if [ ! -d "/home/${user}/.config" ]; then
        #not even a directory?
        mkdir /home/${user}/.config
        chown ${user}:${_primary_group} /home/${user}/.config
        chmod 0755 /home/${user}/.config
      fi

      if [ ! -d "/home/${user}/.config/gtk-2.0" ]; then
        mkdir /home/${user}/.config/gtk-2.0
        chown ${user}:${_primary_group} /home/${user}/.config/gtk-2.0
        chmod 0755 /home/${user}/.config/gtk-2.0
      fi

      #attempt to create file?
      cat > /home/${user}/.config/gtk-2.0/gtkfilechooser.ini << _EOF_
[Filechooser Settings]
LocationMode=path-bar
ShowHidden=true
ExpandFolders=true
_EOF_

      chown ${user}:${_primary_group} /home/${user}/.config/gtk-2.0/gtkfilechooser.ini
      chmod 0755 /home/${user}/.config/gtk-2.0/gtkfilechooser.ini
    fi

    #ADD THE NIAGARA ENTRY TO THE APPLICATIONS-MERGED DIR

    get_install_prop_value menu.entry.Name "${PROPS_VALUE}"

    #attempt to create file?
    cat > "/home/${user}/${MENU_FILE_PATH}" << _EOF_
<!DOCTYPE Menu PUBLIC '-//freedesktop//DTD Menu 1.0//EN'
  'http://standards.freedesktop.org/menu-spec/menu-1.0.dtd'>
<Menu>
  <Name>Applications</Name>
  <Menu>
    <Name>${_prop_value}</Name>
    <Directory>${DIRECTORY_FILE_NAME}</Directory>
    <Include>
      <Filename>${WB_MENU_FILE_NAME}</Filename>
      <Filename>${WBW_MENU_FILE_NAME}</Filename>
      <Filename>${CONSOLE_MENU_FILE_NAME}</Filename>
      <Filename>${ALARM_PORTAL_MENU_FILE_NAME}</Filename>
    </Include>
  </Menu>
</Menu>
_EOF_

    #MAKE SURE NECESSARY FILES ARE IN .LOCAL DIR

    if [ ! -d "/home/${user}/.local/share/applications" ]; then
      if [ ! -d "/home/${user}/.local" ]; then
        mkdir /home/${user}/.local
        chown ${user}:${_primary_group} /home/${user}/.local
        chmod 0755 /home/${user}/.local
      fi

      if [ ! -d "/home/${user}/.local/share" ]; then
        mkdir /home/${user}/.local/share
        chown ${user}:${_primary_group} /home/${user}/.local/share
        chmod 0755 /home/${user}/.local/share
      fi

      mkdir /home/${user}/.local/share/applications
      chown ${user}:${_primary_group} /home/${user}/.local/share/applications
      chmod 0755 /home/${user}/.local/share/applications
    fi

    if [ ! -d "/home/${user}/.local/share/desktop-directories" ]; then
      if [ ! -d "/home/${user}/.local" ]; then
        mkdir /home/${user}/.local
        chown ${user}:${_primary_group} /home/${user}/.local
        chmod 0755 /home/${user}/.local
      fi

      if [ ! -d "/home/${user}/.local/share" ]; then
        mkdir /home/${user}/.local/share
        chown ${user}:${_primary_group} /home/${user}/.local/share
        chmod 0755 /home/${user}/.local/share
      fi

      mkdir /home/${user}/.local/share/desktop-directories
      chown ${user}:${_primary_group} /home/${user}/.local/share/desktop-directories
      chmod 0755 /home/${user}/.local/share/desktop-directories
    fi


    #user level excutables
    install_menu_directory_helper "${user}" "${_primary_group}"
    install_menu_shortcuts_helper "wb" "${user}" "${_primary_group}"
    install_menu_shortcuts_helper "wb_w" "${user}" "${_primary_group}"
    install_menu_shortcuts_helper "console" "${user}" "${_primary_group}"
    install_menu_shortcuts_helper "alarm_portal" "${user}" "${_primary_group}"

    _error=0
    error_handler
  done
}

function install_menu_directory_helper
{
  # ${1} is the user you want to install a directory for
  # ${2} is the group that want to own the file, ideally ${1}'s primary group

  #need to create Niagara-%version%.directory
  #need to modify applications.menu

  local target_user="${1}"
  local target_group="${2}"
  local menu_path="/home/${target_user}/${DIRECTORY_FILE_PATH}"

  echo "[Desktop Entry]"                                          >  "${menu_path}"
  get_install_prop_value shortcut.menu.Version "${PROPS_ERROR}"
  echo "Version=${_prop_value}"                                   >> "${menu_path}"
  echo "Type=Directory"                                           >> "${menu_path}"
  get_install_prop_value shortcut.menu.LName "${PROPS_ERROR}"
  echo "Name[en_US]=${_prop_value}"                               >> "${menu_path}"
  get_install_prop_value shortcut.menu.Name "${PROPS_ERROR}"
  echo "Name=${_prop_value}"                                      >> "${menu_path}"
  get_install_prop_value shortcut.menu.LIcon "${PROPS_ERROR}"
  echo "Icon[en_US]=${_prop_value}"                               >> "${menu_path}"
  get_install_prop_value shortcut.menu.Icon "${PROPS_ERROR}"
  echo "Icon=${_prop_value}"                                      >> "${menu_path}"

  chown "${target_user}:${target_group}" "${menu_path}"
  chmod 0644 "${menu_path}"

  # now I need to modify applications.menu to include this directory
}

function install_menu_shortcuts_helper
{
  # ${1} is the app you want to install
  # ${2} is the user for which you want to install it for
  # ${3} is the group that want to own the file, ideally ${2}'s primary group

  local shortcut_name="${1}"
  local target_user="${2}"
  local target_group="${3}"
  local shortcut_path="/home/${target_user}/.local/share/applications/${BRAND_ID:-Niagara}_${VERSION}_${shortcut_name}.desktop"

  echo "[Desktop Entry]"                                                  >  "${shortcut_path}"
  get_install_prop_value shortcut.${1}.Version "${PROPS_ERROR}"
  echo "Version=${_prop_value}"                                           >> "${shortcut_path}"
  echo "Type=Application"                                                 >> "${shortcut_path}"
  get_install_prop_value shortcut.${1}.Terminal "${PROPS_ERROR}"
  echo "Terminal=${_prop_value}"                                          >> "${shortcut_path}"
  get_install_prop_value shortcut.${1}.LName "${PROPS_ERROR}"
  echo "Name[en_US]=${_prop_value}"                                       >> "${shortcut_path}"

  #make sure icon is there, if not, use default
  get_install_prop_value shortcut.${1}.LPanelIcon "${PROPS_ERROR}"
  if [ ! -e "${_prop_value}" ]; then
    get_install_prop_value shortcut.${1}.DefaultIcon "${PROPS_ERROR}"
  fi
  echo "Icon[en_US]=${_prop_value}"                                       >> "${shortcut_path}"

  if [ "${1}" = "console" ]; then
    echo "Exec=gnome-terminal --working-directory=\"${INSTALL_DIR}\" --title=\"Niagara Command Line\" --command=\"bash --rcfile \\\"${INSTALL_DIR}/bin/.niagara\\\"\"" >> "${shortcut_path}"
  else
    get_install_prop_value shortcut.${1}.Exec "${PROPS_ERROR}"
    echo -n "Exec=\"${INSTALL_DIR}/bin/${LAUNCHER_NAME}\" \"${INSTALL_DIR}/${_prop_value}\"" >> "${shortcut_path}"
    get_install_prop_value shortcut.${1}.Args ""
    if [ "${_prop_value}" = "" ]; then
      echo >> "${shortcut_path}"
    else
      echo " ${_prop_value}" >> "${shortcut_path}"
    fi
  fi

  get_install_prop_value shortcut.${1}.LComment "${PROPS_ERROR}"
  echo "Comment[en_US]=${_prop_value}"                                    >> "${shortcut_path}"
  get_install_prop_value shortcut.${1}.Name "${PROPS_ERROR}"
  echo "Name=${_prop_value}"                                              >> "${shortcut_path}"
  get_install_prop_value shortcut.${1}.Comment "${PROPS_ERROR}"
  echo "Comment=${_prop_value}"                                           >> "${shortcut_path}"

  #make sure icon is there, if not, use default
  get_install_prop_value shortcut.${1}.PanelIcon "${PROPS_ERROR}"
  if [ ! -e "${_prop_value}" ]; then
    get_install_prop_value shortcut.${1}.DefaultIcon "${PROPS_ERROR}"
  fi
  echo "Icon=${_prop_value}"                                              >> "${shortcut_path}"

  #IF WE DIDNT CREATE THE MENU ENTRY, WE CAN GET IT ADDED AUTOMAGICALLY WITH CATEGORIES?
  #
  #if ! ${CREATED_APPS_MENU}; then
  #  get_install_prop_value shortcut.${1}.Categories "${PROPS_ERROR}"
  #  echo "Categories=${_prop_value}"                                        >> "${shortcut_path}"
  #fi

  chown "${target_user}:${target_group}" "${shortcut_path}"
  chmod 0644 "${shortcut_path}"
}

function uninstall_file_quiet
{
  # If target of the link has already been removed, -e will report false.  If it
  if [ -L "${1}" -o -e "${1}" ]; then
    if ! rm -rf "${1}" >> ${LOG_FILE} 2>&1; then
      _error=1
    fi
  else
    # Not a link and file does not exist
    log "File ${1} does not exist"
  fi
}

function uninstall_file
{
  if [ -L "${1}" -o -e "${1}" ]; then
    if rm -rf "${1}" >> ${LOG_FILE} 2>&1; then
      ${SETFORE_WHITE} && ${SETBACK_GREEN}  && ${MOVE_TO_COL_65}
      echolog -n "${SUCCESS_MESSAGE}"
      ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
    else
      ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
      echolog -n "${FAILURE_MESSAGE}"
      ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
    fi
    echolog
  else
    # Not a link and file does not exist
    ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
    echolog -n "${FAILURE_MESSAGE}"
    ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
    echolog
    echolog
    echolog "Did you already delete \"${1}\"?"
    echolog
  fi
}

function uninstall_folder
{
  if [ "${1}" = -q ]; then
    # suppress output
    if [ -d "${2}" ]; then
     uninstall_file_quiet "${2}"
    fi
  else
    if [ -d "${1}" ]; then
     echolog -n "Uninstalling ${1}"
     uninstall_file "${1}"
    fi
  fi
}

function remove_shortcuts
{
  local user
  local idx

  # Remove desktop and menu shortcuts
  if (( ${_users_count} > 0 )); then
    for ((idx=0; ${idx}<${_users_count}; idx++)); do
      user=${_users[${idx}]}

      echolog -n "Removing user \"${user}\" desktop and menu items..."

      _error=0

      # Remove desktop stuff
      get_install_prop_value shortcut.wb_w.Name "${PROPS_ERROR}"
      uninstall_file_quiet "/home/${user}/Desktop/${_prop_value}.desktop"

      get_install_prop_value shortcut.alarm_portal.Name "${PROPS_ERROR}"
      uninstall_file_quiet "/home/${user}/Desktop/${_prop_value}.desktop"

      # Remove menu stuff
      # Remove the menu
      uninstall_file_quiet "/home/${user}/${MENU_FILE_PATH}"

      # Remove the directory
      uninstall_file_quiet "/home/${user}/${DIRECTORY_FILE_PATH}"

      # Remove menu entries
      uninstall_file_quiet "/home/${user}/.local/share/applications/${WB_MENU_FILE_NAME}"
      uninstall_file_quiet "/home/${user}/.local/share/applications/${WBW_MENU_FILE_NAME}"
      uninstall_file_quiet "/home/${user}/.local/share/applications/${CONSOLE_MENU_FILE_NAME}"
      uninstall_file_quiet "/home/${user}/.local/share/applications/${ALARM_PORTAL_MENU_FILE_NAME}"

      if (( _error != 0 )); then
        error_handler
        echolog "See log for details"
        echolog
      else
        error_handler
      fi
    done
  fi
}

function get_service_symlink_target
{
  _symlink_target=$(ls -l "${ETC_INITD_NAME}")
  # at this point, result should be "/etc/init.d/SERVICE_NAME -> SUSPECT_INSTALL_DIR/bin/niagaradctl"
  _symlink_target=${_symlink_target#*-> }
  # at this point, result should be "SUSPECT_INSTALL_DIR/bin/niagaradctl"
  _symlink_target=${_symlink_target%/*}
  # at this point, result should be "SUSPECT_INSTALL_DIR/bin"
  _symlink_target=${_symlink_target%/*}
  # at this point, result should be "SUSPECT_INSTALL_DIR"
}

function check_service
{
  if [ -e "${ETC_INITD_NAME}" ]; then
    # /etc/init.d/SERVICE_NAME file exists
    get_service_symlink_target

    # if INSTALL_DIR == TARGET, then we can be reasonably sure that we own this
    # service, and its already installed...
    if [[ "${INSTALL_DIR}" != "${_symlink_target}" ]]; then
      # this points to someone other than us
      echolog
      ${SETFORE_WHITE} && ${SETBACK_BROWN}
      echolog -n "${WARNING_MESSAGE}"
      ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
      echolog ": Niagara Build ${VERSION} has detected that ${SERVICE_NAME} is already "
      echolog "enabled as a service on this system. Continuing with this script will OVERWRITE "
      echolog "the existing installation (${_symlink_target})!"
      echolog
      while true; do
        echolog -r "Do you want to continue installing anyway? [YES/no]:"
        get_user_response

        if ${_resp_yes} || ${_resp_default}; then
          return 0
        elif ${_resp_no}; then
          return 1
        fi
        invalid_entry
      done
    else
      return 0
    fi
  else
    return 0
  fi
}

function get_usrbin_symlink_target
{
  _symlink_target=$(ls -l "${USR_BIN_NAME}")
  # at this point, result should be "/usr/bin/niagaradctl -> SUSPECT_INSTALL_DIR/bin/niagaradctl"
  _symlink_target=${_symlink_target#*-> }
  # at this point, result should be "SUSPECT_INSTALL_DIR/bin/niagaradctl"
  _symlink_target=${_symlink_target%/*}
  # at this point, result should be "SUSPECT_INSTALL_DIR/bin"
  _symlink_target=${_symlink_target%/*}
  # at this point, result should be "SUSPECT_INSTALL_DIR"
}

function check_usrbin
{
  if [ -e "${USR_BIN_NAME}" ]; then
    # the /usr/bin/niagaradctl file exists at this point...

    # if INSTALL_DIR == TARGET, then we can be reasonably sure that we own this
    # service, and its already installed...
    if [[ "${INSTALL_DIR}" != "${_symlink_target}" ]]; then
      # this points to someone other than us
      echolog
      ${SETFORE_WHITE} && ${SETBACK_BROWN}
      echolog -n "${WARNING_MESSAGE}"
      ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
      echolog ": Niagara Build ${VERSION} has detected that niagaradctl is already "
      echolog "installed at /usr/bin on this system. Continuing with this script will OVERWRITE "
      echolog "the existing installation (${_symlink_target})!"
      echolog
      while true; do
        echolog -r "Do you want to continue installing anyway? [YES/no]:"
        get_user_response

        if ${_resp_yes} || ${_resp_default}; then
          return 0
        elif ${_resp_no}; then
          return 1
        fi
        invalid_entry
      done
    else
      return 0
    fi
  else
    return 0
  fi
}

function install_service
{
  echolog -n "Installing service..."

  # stop any service running already?
  if [ -e "${ETC_INITD_NAME}" ]; then
    ${ETC_INITD_NAME} stop >> ${LOG_FILE} 2>&1
    sleep 2
  fi    

  if ${_is_debian}; then
    # remove any previous installations since force, doesn't seem to mean force...
    /usr/sbin/update-rc.d -f ${SERVICE_NAME} remove >> ${LOG_FILE}
  fi

  if ! mkdir -p "${INSTALL_DIR}/bin"          >> ${LOG_FILE} 2>&1 ||
     ! touch "${INSTALL_DIR}/bin/niagaradctl" >> ${LOG_FILE} 2>&1; then
    _error=1
    error_handler
    echolog "Failed to create ${INSTALL_DIR}/bin/niagaradctl"
    close
  fi

  if ${_is_redhat} || ${is_amazon}; then
    cat > "${INSTALL_DIR}/bin/niagaradctl" << _END_
#!/bin/bash
#
# Niagara ${VERSION}
# Copyright 2019, Tridium, Inc. All Rights Reserved.
#
# Author: Mike James, 2008
#
# /etc/init.d/${SERVICE_NAME}
#   and its symbolic link
# /usr/bin/niagaradctl
#
# chkconfig:   35 98 05
# {$SERVICE_NAME}:         Niagara v${VERSION}
# processname: niagarad
# description: Startup/shutdown script for the Niagara Daemon.
# pidfile:     /var/run/niagarad/niagarad.pid
#
_END_
  elif ${_is_debian}; then
    cat > "${INSTALL_DIR}/bin/niagaradctl" << _END_
#!/bin/sh
#
# Niagara ${VERSION}
# Copyright 2019, Tridium, Inc. All Rights Reserved.
#
# Author: Mike James, 2008
#
# /etc/init.d/${SERVICE_NAME}
#   and its symbolic link
# /usr/bin/niagaradctl
#
### BEGIN INIT INFO
# Provides:             niagarad
# Required-Start:
# Required-Stop:
# Default-Start:        2 3 4 5
# Default-Stop:         0 1 6
# Short-Description:    Control script for the Niagara Daemon.
### END INIT INFO
#
_END_
  fi

  echo "unset niagara_home"                     >> "${INSTALL_DIR}/bin/niagaradctl"
  echo "export niagara_home=\"${INSTALL_DIR}\"" >> "${INSTALL_DIR}/bin/niagaradctl"
  if ! cat "${_niagarad_generic_file}" >> "${INSTALL_DIR}/bin/niagaradctl"; then
    _error=1
    error_handler
    echolog "Failed to copy ${_niagarad_generic_file} to ${INSTALL_DIR}/bin/niagaradctl"
    close
  fi

  scrub_script "${INSTALL_DIR}/bin/niagaradctl"

  if ln -sf "${INSTALL_DIR}/bin/niagaradctl" "${ETC_INITD_NAME}" >> ${LOG_FILE} 2>&1; then
    _installed_service=true

    if ${_is_redhat} || ${_is_amazon}; then
      if ln -sf "${ETC_INITD_NAME}" "${ETC_RC0D_NAME}" >> ${LOG_FILE} 2>&1; then
        _installed_rc0=true
      else
        _installed_rc0=false
        log "Failed to install rc0"
        _error=1
      fi

      if ln -sf "${ETC_INITD_NAME}" "${ETC_RC1D_NAME}" >> ${LOG_FILE} 2>&1; then
        _installed_rc1=true
      else
        _installed_rc1=false
        log "Failed to install rc1"
        _error=1
      fi

      if ln -sf "${ETC_INITD_NAME}" "${ETC_RC3D_NAME}" >> ${LOG_FILE} 2>&1; then
        _installed_rc3=true
      else
        _installed_rc3=false
        log "Failed to install rc3"
        _error=1
      fi

      if ln -sf "${ETC_INITD_NAME}" "${ETC_RC5D_NAME}" >> ${LOG_FILE} 2>&1; then
        _installed_rc5=true
      else
        _installed_rc5=false
        log "Failed to install rc5"
        _error=1
      fi

      if ln -sf "${ETC_INITD_NAME}" "${ETC_RC6D_NAME}" >> ${LOG_FILE} 2>&1; then
        _installed_rc6=true
      else
        _installed_rc6=false
        log "Failed to install rc6"
        _error=1
      fi

      #register service
      if $_installed_rc0 &&
         $_installed_rc1 &&
         $_installed_rc3 &&
         $_installed_rc5 &&
         $_installed_rc6; then
        /sbin/chkconfig --add "${SERVICE_NAME}" >> ${LOG_FILE} 2>&1
      fi

    elif ${_is_debian}; then
      # debian should do all of this for us?
      if /usr/sbin/update-rc.d -f ${SERVICE_NAME} start 98 2 3 4 5 . stop 05 0 1 6 . >> ${LOG_FILE} 2>&1; then
        _installed_rc0=true
        _installed_rc1=true
        _installed_rc2=true
        _installed_rc3=true
        _installed_rc4=true
        _installed_rc5=true
        _installed_rc6=true
      else
        log "Debian update-rc.d start failed"
        _error=1
        _installed_rc0=false
        _installed_rc1=false
        _installed_rc2=false
        _installed_rc3=false
        _installed_rc4=false
        _installed_rc5=false
        _installed_rc6=false
      fi
    fi
  else
    log "Failed to create symlink from ${INSTALL_DIR}/bin/niagaradctl to ${ETC_INITD_NAME}"
    _error=1
    _installed_service=false
    _installed_rc0=false
    _installed_rc1=false
    _installed_rc2=false
    _installed_rc3=false
    _installed_rc4=false
    _installed_rc5=false
    _installed_rc6=false
  fi

  if ln -sf "${INSTALL_DIR}/bin/niagaradctl" "${USR_BIN_NAME}" >> "${LOG_FILE}" 2>&1; then
    _installed_usr_bin=true
  else
    log "Failed to create symlink between ${INSTALL_DIR}/bin/niagaradctl and ${USR_BIN_NAME}"
    _error=1
  fi

  if (( _error != 0 )); then
    error_handler
    close
  fi

  # we want to make a directory writable by us for pidfile placement
  local pid_dir="/var/run/niagarad"
  if ! mkdir -p ${pid_dir}                               >> ${LOG_FILE} 2>&1 ||
     ! chown ${NIAGARA_USER}:${NIAGARA_GROUP} ${pid_dir} >> ${LOG_FILE} 2>&1 ||
     ! chmod 0755 ${pid_dir}                             >> ${LOG_FILE} 2>&1; then
    _error=1
    error_handler
    echolog "Failed to create or setup ${pid_dir}"
    close
  fi

  error_handler
}

function verify_uninstall_service_settings
{
  if ${_installed_rc0}; then
    echolog "Disable niagarad shutdown at run level 0."
  fi

  if ${_installed_rc1}; then
    echolog "Disable niagarad startup at run level 1."
  fi

  if ${_installed_rc2}; then
    echolog "Disable niagarad startup at run level 2."
  fi

  if ${_installed_rc3}; then
    echolog "Disable niagarad startup at run level 3."
  fi

  if ${_installed_rc4}; then
    echolog "Disable niagarad startup at run level 4."
  fi

  if ${_installed_rc5}; then
    echolog "Disable niagarad startup at run level 5."
  fi

  if ${_installed_rc6}; then
    echolog "Disable niagarad shutdown at run level 6."
  fi

  if ${_installed_usr_bin}; then
    echolog "Remove the symbolic link in /usr/bin."
  fi

  if ${_installed_service}; then
    echolog "Disable niagarad as a service."
  fi
}

function uninstall_service
{
  echolog -n "Disabling niagarad as a service..."

  get_service_symlink_target

  # if INSTALL_DIR == TARGET, then we can be reasonably sure that we own this
  # service...
  if [ "${INSTALL_DIR}" == "${_symlink_target}" ]; then
    if ${_is_redhat} || ${_is_amazon}; then
      /sbin/service ${SERVICE_NAME} stop 1> /dev/null 2>&1
    elif ${_is_debian}; then
      ${ETC_INITD_NAME} stop 1> /dev/null 2>&1
    fi

    sleep 2

    uninstall_file "${ETC_INITD_NAME}"

    if ${_is_redhat} || ${_is_amazon}; then
      /sbin/chkconfig --del ${SERVICE_NAME} 1> /dev/null 2>&1
    elif ${_is_debian}; then
      /usr/sbin/update-rc.d ${SERVICE_NAME} remove 1> /dev/null 2>&1
    fi

    # the previous line should have disabled start up at RC3 and RC5, but
    # let's just do a check
    # Some of these files are created automatically by chkconfig but not deleted
    # so remove them if they still exist.
    if [ -L "${ETC_RC0D_NAME}" ]; then
      echolog -n "Disabling niagarad shutdown at run level 0..."
      uninstall_file "${ETC_RC0D_NAME}"
    fi

    if [ -L "${ETC_RC1D_NAME}" ]; then
      echolog -n "Disabling niagarad shutdown at run level 1..."
      uninstall_file "${ETC_RC1D_NAME}"
    fi

    if [ -L "${ETC_RC2D_NAME}" ]; then
      echolog -n "Disabling niagarad startup at run level 2..."
      uninstall_file "${ETC_RC2D_NAME}"
    fi

    if [ -L "${ETC_RC3D_NAME}" ]; then
      echolog -n "Disabling niagarad startup at run level 3..."
      uninstall_file "${ETC_RC3D_NAME}"
    fi

    if [ -L "${ETC_RC4D_NAME}" ]; then
      echolog -n "Disabling niagarad startup at run level 4..."
      uninstall_file "${ETC_RC4D_NAME}"
    fi

    if [ -L "${ETC_RC5D_NAME}" ]; then
      echolog -n "Disabling niagarad startup at run level 5..."
      uninstall_file "${ETC_RC5D_NAME}"
    fi

    if [ -L "${ETC_RC6D_NAME}" ]; then
      echolog -n "Disabling niagarad shutdown at run level 6..."
      uninstall_file "${ETC_RC6D_NAME}"
    fi

  else
    ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
    echolog -n "${FAILURE_MESSAGE}"
    ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
    echolog
    echolog "The symbolic link at "
    echolog "${ETC_INITD_NAME} "
    echolog "does not point to "
    echolog "${INSTALL_DIR}. "
    echolog "Cannot delete a link not owned by this installation."
    echolog
  fi
}

function uninstall_usrbin
{
  echolog -n "Uninstalling the symbolic link in /usr/bin..."

  get_usrbin_symlink_target

  if [ "${INSTALL_DIR}" == "${_symlink_target}" ]; then
    uninstall_file "${USR_BIN_NAME}"
    amend_uninstall "USR_BIN_INSTALLED" "false"
    amend_uninstall "SERVICE" "false"
  else
    ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
    echolog -n "${FAILURE_MESSAGE}"
    ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
    echolog
    echolog "The symbolic link at "
    echolog "${USR_BIN_NAME} "
    echolog "does not point to "
    echolog "${INSTALL_DIR}. "
    echolog "Cannot delete a link not owned by this installation."
  fi
}

function set_niagaradctl_permissions
{
  if ! chmod 0550 "${INSTALL_DIR}/bin/niagaradctl"                               >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chown "${NIAGARA_USER}:${NIAGARA_GROUP}" "${INSTALL_DIR}/bin/niagaradctl" >> ${LOG_FILE} 2>&1; then _error=1; fi

  if ${_installed_usr_bin}; then
    if ! chown -h "${NIAGARA_USER}:${NIAGARA_GROUP}" ${USR_BIN_NAME} >> ${LOG_FILE} 2>&1; then _error=1; fi
  fi

  if ${_installed_service}; then
    if ! chown -h "${NIAGARA_USER}:${NIAGARA_GROUP}" "${ETC_INITD_NAME}"  >> ${LOG_FILE} 2>&1; then _error=1; fi

    if [ -e "${ETC_RC0D_NAME}" ]; then
      if ! chown -h "${NIAGARA_USER}:${NIAGARA_GROUP}" "${ETC_RC0D_NAME}" >> ${LOG_FILE} 2>&1; then _error=1; fi
    fi

    if [ -e "${ETC_RC1D_NAME}" ]; then
      if ! chown -h "${NIAGARA_USER}:${NIAGARA_GROUP}" "${ETC_RC1D_NAME}" >> ${LOG_FILE} 2>&1; then _error=1; fi
    fi

    if [ -e "${ETC_RC2D_NAME}" ]; then
      if ! chown -h "${NIAGARA_USER}:${NIAGARA_GROUP}" "${ETC_RC2D_NAME}" >> ${LOG_FILE} 2>&1; then _error=1; fi
    fi

    if [ -e "${ETC_RC3D_NAME}" ]; then
      if ! chown -h "${NIAGARA_USER}:${NIAGARA_GROUP}" "${ETC_RC3D_NAME}" >> ${LOG_FILE} 2>&1; then _error=1; fi
    fi

    if [ -e "${ETC_RC4D_NAME}" ]; then
      if ! chown -h "${NIAGARA_USER}:${NIAGARA_GROUP}" "${ETC_RC4D_NAME}" >> ${LOG_FILE} 2>&1; then _error=1; fi
    fi

    if [ -e "${ETC_RC5D_NAME}" ]; then
      if ! chown -h "${NIAGARA_USER}:${NIAGARA_GROUP}" "${ETC_RC5D_NAME}" >> ${LOG_FILE} 2>&1; then _error=1; fi
    fi

    if [ -e "${ETC_RC6D_NAME}" ]; then
      if ! chown -h "${NIAGARA_USER}:${NIAGARA_GROUP}" "${ETC_RC6D_NAME}" >> ${LOG_FILE} 2>&1; then _error=1; fi
    fi
  fi
}

# modify_config
# $1 is the KEY you want in the uninstall.conf file
# $2 is the VALUE associated
function amend_uninstall
{
  sed -e s/^${1}=.*$/${1}=${2}/g "./../uninstall/uninstall.conf" > "./uninstall.conf.temp"
  mv -f "./uninstall.conf.temp" "./../uninstall/uninstall.conf"
}

function summarize_service_install
{
  if ${_installed_usr_bin}; then
    get_install_prop_value installFinished.installedSymLinkTrue "Niagara created the symbolic link:"
    echolog "${_prop_value} ${USR_BIN_NAME}"
  else
    get_install_prop_value installFinished.installedSymLinkFalse "Niagara could not create the symbolic link:"
    echolog "${_prop_value} ${USR_BIN_NAME}"
  fi

  get_install_prop_value installFinished.installedOwner "Niagara is owned by"
  echolog "${_prop_value} ${NIAGARA_USER}:${NIAGARA_GROUP}"

  if ${_installed_service}; then
    get_install_prop_value installFinished.installedServiceTrue "Niagara was installed as a service at"
    echolog "${_prop_value} ${ETC_INITD_NAME}."

    if ${_installed_rc0}; then
      echolog_prop_value installFinished.installedRunLevel0True "Niagara will automatically stop on run level 0."
    else
      echolog_prop_value installFinished.installedRunLevel0False "Niagara will not automatically stop on run level 0."
    fi

    if ${_installed_rc1}; then
      echolog_prop_value installFinished.installedRunLevel1True "Niagara will automatically start on run level 1."
    else
      echolog_prop_value installFinished.installedRunLevel1False "Niagara will not automatically start on run level 1."
    fi

    if ${_installed_rc2}; then
      echolog_prop_value installFinished.installedRunLevel2True "Niagara will automatically start on run level 2."
    else
      echolog_prop_value installFinished.installedRunLevel2False "Niagara will not automatically start on run level 2."
    fi

    if ${_installed_rc3}; then
      echolog_prop_value installFinished.installedRunLevel3True "Niagara will automatically start on run level 3."
    else
      echolog_prop_value installFinished.installedRunLevel3False "Niagara will not automatically start on run level 3."
    fi

    if ${_installed_rc4}; then
      echolog_prop_value installFinished.installedRunLevel4True "Niagara will automatically start on run level 4."
    else
      echolog_prop_value installFinished.installedRunLevel4False "Niagara will not automatically start on run level 4."
    fi

    if ${_installed_rc5}; then
      echolog_prop_value installFinished.installedRunLevel5True "Niagara will automatically start on run level 5."
    else
      echolog_prop_value installFinished.installedRunLevel5False "Niagara will not automatically start on run level 5."
    fi

    if ${_installed_rc6}; then
      echolog_prop_value installFinished.installedRunLevel6True "Niagara will automatically stop on run level 6."
    else
      echolog_prop_value installFinished.installedRunLevel6False "Niagara will not automatically stop on run level 6."
    fi

    if ${_is_redhat} || ${_is_amazon}; then
      if ! ${_installed_rc3} && ! ${_installed_rc5}; then
        echolog_prop_value installFinished.installedRunFalse "Niagara will not automatically start."
      fi
    elif ${_is_debian}; then
      if ! ${_installed_rc2} && ! ${_installed_rc3} && ! ${_installed_rc4} && ! ${_installed_rc5}; then
        echolog_prop_value installFinished.installedRunFalse "Niagara will not automatically start."
      fi
    fi

  else
    echolog_prop_value installFinished.installedServiceFalse "Niagara was installed as an application."
  fi
}

# We depend on ls and cp doing a certain thing, so alias
alias ls="ls"
alias cp="cp -i --reply=yes"

# Trap any signals that would cause you to exit; this will let you clean up if
# you need...
trap 'echo; echo; echo -n "`basename ${0}`: Ouch! Quitting early."; echolog; stty sane; exit' 1 2 3 15
