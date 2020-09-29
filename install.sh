#!/bin/bash

if [ ! -e "./install_common.sh" ]; then
  echo "FAILURE: Can not run from the current directory, please run from the same directory as install_common.sh"
  exit
fi

source "./install_common.sh"

declare -r LOG_FILE_NAME="niagaraInstall"
declare -r LOG_FILE="/tmp/${LOG_FILE_NAME}.log"

declare -r PROPS_FILE="${PWD}/install-data/install.properties"
declare -r BRAND_PROPS_FILE="${PWD}/overlay/etc/brand.properties"

declare -r NIAGARA_ETC_DIR="/etc/niagara"
declare -r NIAGARA_SP_FILE=".sp"
declare -r NIAGARA_KM_FILE=".km"
declare _system_pwd=
declare _has_system_pwd=false
declare _prompt_for_dist=false
declare _libcrypto_found=false
declare _libxss_found=false

declare NRE_CONFIG_DIST_DIR="${PWD}/dist/${VERSION}"
declare NRE_CORE_DIST_DIR="${PWD}/dist/${VERSION}"
declare JRE_DIST_DIR="${PWD}/dist/${JRE_VERSION}"

declare -r CONFIG_DIST_X86_64="nre-config-linux-x64.dist"
declare -r CORE_DIST_X86_64="nre-core-linux-x64.dist"
declare -r JRE_DIST_X86_64="oracle-jre-linux-x64-es.dist"

declare -r OVERLAY_LIB="${PWD}/overlay/lib"
declare -r LICENSE_AGREEMENT="lib/licenseAgreement.txt"

declare -r OVERLAY_BLACKLIST=("lib/licenseAgreement.txt"
"lib/readmeLicenses.txt")

# Dependencies

declare -r COMMON_FILES="/bin/cat
/bin/basename
/bin/chmod
/bin/chown
/bin/cp
/bin/df
/bin/dirname
/bin/egrep
/bin/find
/bin/gio
/bin/grep
/bin/head
/bin/ln
/bin/mkdir
/bin/mv
/bin/rm
/bin/rsync
/bin/sed
/bin/touch
/bin/unzip
/usr/bin/awk
/usr/bin/chcon
/usr/bin/fold
/usr/bin/sg
/usr/bin/stty
/usr/sbin/selinuxenabled
/usr/sbin/useradd
/usr/sbin/usermod
/usr/sbin/groupadd
/usr/sbin/runuser"

declare -r REDHAT_FILES="/sbin/chkconfig"

declare -r DEBIAN_FILES="/usr/sbin/update-rc.d
/usr/bin/fromdos"

declare -r AMAZON_FILES="/sbin/chkconfig"

# Size variables
declare -i _generic_size=0
declare -i _doc_size=0
declare -i _dist_size=0
declare -i _space_required=0
declare -i _space_available=0

# Install directory
declare _selected_dir

declare _install_doc=false
declare _install_dist=false
declare _add_etc_sudoers=false

# Create a function for closing the installer from anywhere
function close
{
  echolog
  echolog_prop_value installClose.message "The Niagara 4 installer is now closing."
  echolog

  # Leave a timestamped transient copy of the log
  local SECONDS_SINCE_EPOCH=$(date +%s)
  mv -f ${LOG_FILE} "/tmp/${LOG_FILE_NAME}_${SECONDS_SINCE_EPOCH}.log" > /dev/null 2>&1

  sleep 2
  exit 1
}

# Following steps only necessary if default folder is in windows format
#
# START
#
# TEMP="${DEFAULT_FOLDER}"
# DEFAULT_FOLDER="/opt/$(echo ${TEMP#C:\\})"
#
# TURN \ into /
# while echo "${DEFAULT_FOLDER}" | grep "[\]" > /dev/null 2>&1; do
#   COPY="${DEFAULT_FOLDER}"
#   FIRST="$(echo "${DEFAULT_FOLDER%%\\*}")"
#   DEFAULT_FOLDER=${COPY}
#   REST="$(echo "${DEFAULT_FOLDER#*\\}")"
#   DEFAULT_FOLDER="${FIRST}/${REST}"
# done
#
# END

# Get the size of a directory
function get_size
{
   _generic_size=0
   get_size_helper "${1}"
}

# Recursive helper for getting the size of a directory specified in ${1}
function get_size_helper
{
  for file in ${1}/*; do
    # ${file} - A file/directory under ${1} specified with the full path
    local full_path="${file}"
    if [ -d "${full_path}" ]; then
      let "_generic_size=${_generic_size}+$(stat -c%s "${full_path}")"
      cd "${full_path}"
      get_size_helper "${PWD}"
      cd ..
    else
      let "_generic_size=${_generic_size}+$(stat -c%s "${full_path}")"
    fi
  done
}

function size_error_undetermined
{
  ${SETFORE_WHITE} && ${SETBACK_BROWN} && ${MOVE_TO_COL_65}
  echolog -n "${WARNING_MESSAGE}"
  ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
  echolog ": The Niagara 4 installer was unable to determine the disk "
  echolog "space required to install Niagara ${1}. This will not prevent you"
  echolog "from installing Niagara ${1}, but exercise caution."
  echolog
}

function size_error_not_enough
{
  ${SETFORE_WHITE} && ${SETBACK_RED} && ${MOVE_TO_COL_65}
  echolog -n "${FAILURE_MESSAGE}"
  ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
  echolog ": Niagara ${1} requires $(printf "%'d" ${2})K but only $(printf "%'d" ${_space_required})K is available."
  echolog "Niagara ${1} cannot be installed at this time."
  echolog
}

# Find the exact location of distribution directories if they are not default location

function get_nre_config_distribution_dir
{
  if [ ! -e "${NRE_CONFIG_DIST_DIR}/${CONFIG_DIST_X86_64}" ]; then
    # Configuration distribution did not exist at default location, find it
    DIST_FILE=$(find ${PWD}/dist -name "${CONFIG_DIST_X86_64}" | head -n 1)

    # Found the file at an alternative location
    if [ ! -z "${DIST_FILE}" ]; then
      NRE_CONFIG_DIST_DIR=$(dirname "${DIST_FILE}")
    fi
  fi
}

function get_nre_core_distribution_dir
{
  if [ ! -e "${NRE_CORE_DIST_DIR}/${CORE_DIST_X86_64}" ]; then
    # Core distribution did not exist at default location, find it  
    DIST_FILE=$(find ${PWD}/dist -name "${CORE_DIST_X86_64}" | head -n 1)

    # Found the file at an alternative location
    if [ ! -z "${DIST_FILE}" ]; then
      NRE_CORE_DIST_DIR=$(dirname "${DIST_FILE}")
    fi
  fi
}

function get_jre_distribution_dir
{
  if [ ! -e "${JRE_DIST_DIR}/${JRE_DIST_X86_64}" ]; then
    # JRE distribution did not exist at default location, find it    
    DIST_FILE=$(find ${PWD}/dist -name "${JRE_DIST_X86_64}" | head -n 1)

    # Found the file at an alternative location
    if [ ! -z "${DIST_FILE}" ]; then
      JRE_DIST_DIR=$(dirname "${DIST_FILE}")
    fi
  fi
}

function install_dists
{
  local success=true

  echolog -n "Copying dist files..."
  if cp "${NRE_CORE_DIST_DIR}/${CORE_DIST_X86_64}"   "${INSTALL_DIR}" >> ${LOG_FILE} 2>&1 &&
     cp "${JRE_DIST_DIR}/${JRE_DIST_X86_64}"    "${INSTALL_DIR}" >> ${LOG_FILE} 2>&1 &&
     cp "${NRE_CONFIG_DIST_DIR}/${CONFIG_DIST_X86_64}" "${INSTALL_DIR}" >> ${LOG_FILE} 2>&1 &&
     cd "${INSTALL_DIR}"; then

    error_handler

    echolog -n "Expanding core dist..."
    if ! unzip -o "${INSTALL_DIR}/${CORE_DIST_X86_64}" -d "${INSTALL_DIR}/bin" >> ${LOG_FILE} 2>&1; then
      _error=1
      success=false
    # Remove dist.xml
    elif ! rm -f "${INSTALL_DIR}/bin/META-INF/dist.xml"                            >> ${LOG_FILE} 2>&1; then
      _error=1
      success=false
    fi
    error_handler

    echolog -n "Expanding jre dist..."
    if ! unzip -o "${INSTALL_DIR}/${JRE_DIST_X86_64}" -d "${INSTALL_DIR}/jre" >> ${LOG_FILE} 2>&1; then
      _error=1
      success=false
    # Remove dist.xml
    elif ! rm -f "${INSTALL_DIR}/jre/META-INF/dist.xml"                           >> ${LOG_FILE} 2>&1; then
      _error=1
      success=false
    fi
    error_handler

    echolog -n "Expanding config dist..."
    if ! unzip -o "${INSTALL_DIR}/${CONFIG_DIST_X86_64}" >> ${LOG_FILE} 2>&1; then
      _error=1
      success=false

    # Remove the META-INF directory which is used to list package dependencies
    # and is not necessary for install.
    elif ! rm -fr "${INSTALL_DIR}/META-INF"              >> ${LOG_FILE} 2>&1; then
      _error=1
      success=false
    fi
    error_handler
  else
    _error=1
    success=false
    error_handler
  fi

  if ${success}; then
    cd "${OLDPWD}"
    install_overlay
  else
    close
  fi
}

function install_folder
{
  echolog -n "Installing folder: ${1}..."
  if ! cp -R "${PWD}/${1}" "${INSTALL_DIR}" >> ${LOG_FILE} 2>&1; then
    _error=1
    error_handler
    close
  fi

  error_handler
}

function install_overlay
{
  if [ -d "${PWD}/overlay" ]; then
    echolog -n "Applying overlay..."
    OLDPWD="${PWD}"
    cd "${PWD}/overlay"
    if ! rsync -r "${OVERLAY_BLACKLIST[@]/#/--exclude=}" * "${INSTALL_DIR}" >> ${LOG_FILE} 2>&1; then
      _error=1
      error_handler
      close
    fi
    cd "${OLDPWD}"
    error_handler
  else
    log "Overlay directory does not exist in ${PWD}"
  fi
}

function create_environment
{
  echolog -n "Creating runtime environment script..."

  #as a failsafe, create the bin dir?
  mkdir -p "${INSTALL_DIR}/bin" >> ${LOG_FILE} 2>&1

  touch "${INSTALL_DIR}/bin/.niagara" >> ${LOG_FILE} 2>&1
  cat > "${INSTALL_DIR}/bin/.niagara" << _EOF_
#!/bin/bash
unset niagara_home NIAGARA_JRE_HOME
export niagara_home="${INSTALL_DIR}"
export NIAGARA_JRE_HOME="\${niagara_home}/jre"
export PS1="\\u@Niagara-${VERSION}# "

if [ ! "\${PATH}" ]; then
  export PATH="\${niagara_home}/bin:\${NIAGARA_JRE_HOME}/bin"
else
  echo "\${PATH}" | grep "\${niagara_home}/bin:\${NIAGARA_JRE_HOME}/bin" > /dev/null 2>&1
  if [ "\${?}" = "0" ]; then
    :
  else
    export PATH="\${PATH}:\${niagara_home}/bin:\${NIAGARA_JRE_HOME}/bin"
  fi
fi

if [ ! "\${CLASSPATH}" ]; then
  export CLASSPATH="\${niagara_home}/modules/baja.jar"
else
  echo "\${CLASSPATH}" | grep "\${niagara_home}/modules/baja.jar" > /dev/null 2>&1
  if [ "\${?}" = "0" ]; then
    :
  else
    export CLASSPATH="\${CLASSPATH}:\${niagara_home}/modules/baja.jar"
  fi
fi

if [ ! "\${LD_LIBRARY_PATH}" ]; then
  export LD_LIBRARY_PATH="\${NIAGARA_JRE_HOME}/lib/amd64/server:\${NIAGARA_JRE_HOME}/lib/amd64:\${niagara_home}/bin"
else
  echo "\${LD_LIBRARY_PATH}" | grep "\${NIAGARA_JRE_HOME}/lib/amd64/server:\${NIAGARA_JRE_HOME}/lib/amd64:\${niagara_home}/bin" > /dev/null 2>&1
  if [ "\${?}" = "0" ]; then
    :
  else
    export LD_LIBRARY_PATH="\${NIAGARA_JRE_HOME}/lib/amd64/server:\${NIAGARA_JRE_HOME}/lib/amd64:\${niagara_home}/bin:\${LD_LIBRARY_PATH}"
  fi
fi
_EOF_

  _error=0
  error_handler
}

function check_partition
{
  local suspect="${1}"

  if [ -e "${suspect}" ]; then
    if [ -f "${suspect}" ]; then
      _error=1
      error_handler
      echolog
      echolog "The provided path leads to a currently existing file"
      return 0
    fi
  fi

  _space_available=0
  get_available_space "${suspect}"

  if (( _space_available != 0 )); then
    if (( _space_available <= _space_required )); then
      _error=1
      error_handler
      echolog
      echolog "There is only $(printf "%'d" ${_space_available})K available on that"
      echolog "disk and Niagara requires $(printf "%'d" ${_space_required})K."
      return 0
    else
      error_handler
      let "_space_available=${_space_available}-${_space_required}"
    fi
  else
    ${SETFORE_WHITE} && ${SETBACK_BROWN} && ${MOVE_TO_COL_65}
    echolog -n "${WARNING_MESSAGE}"
    ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
    echolog
    echolog ": The Niagara 4 installer could not determine the amount "
    echolog "of free space on the disk. Please verify externally that you have "
    echolog "at least $(printf "%'d" ${_space_required})K of space available."
  fi

  return 1
}

function get_available_space
{
  echolog -n "Verifying space at \"${1}\":"

  local word="${1}"
  local disk
  while [ "${word}" ]; do
    disk="$(df -P | grep "${word}$")"
    if (( ${?} == 0 )); then
      break
    else
      word="$(echo "${word%/*[-~%A-Za-z0-9\._]}")"
    fi
  done

  if [ ! "${word}" ]; then
    disk=$(df -P | grep "/$" | grep -v grep)
  fi

  local counter=0
  local test
  for word in ${disk}; do
    test=$(echo "${word}" | egrep ^[0-9][0-9]+[0-9]$)

    if [ "${test}" ]; then
      let "counter=${counter}+1"
    fi

    if (( $counter == 3 )); then
      _space_available=${test}
      break
    else
      _space_available=0
    fi
  done;
}

# If the .sp exists and is greater than zero length, it contains the system password.
# No need to prompt the user for the system password.
# If .sp exists but is zero length, remove it
# If .sp does not exist or is zero length, later in the install, prompt the user
# for a system password, create a .sp file, and write the supplied system
# password to this file.
function check_sp_file
{
  # Encrypted system password file
  local sp="${NIAGARA_ETC_DIR}/${NIAGARA_SP_FILE}"

  if [ -e "${sp}" ]; then
    # .sp exists
    if [ ! -f "${sp}" ]; then
      # .sp is not a file
      echolog
      echolog "The Niagara 4 installer has found a directory "
      echolog "${sp}"
      echolog "instead of a file. This directory must be removed before the installer can "
      echolog "proceed."
      close
    elif [ ! -s "${sp}" ]; then
      # .sp is zero length
      if ! rm -f "${sp}" >> ${LOG_FILE} 2>&1; then
         # ... but could not be removed
        echolog
        echolog "The Niagara 4 installer could not remove the invalid file "
        echolog "${sp}"
        close
      else
        # .sp existed but was empty and so was removed; must prompt for system
        # password.
        log
        log "Empty .sp was removed- user will be prompted for system password"
        _has_system_pwd=false
      fi
    else
      # .sp exists and is greater than zero length; do not need to prompt for
      # the system password during install.  Will attempt to set permissions on
      # this file once the niagara user is created.
      log
      log ".sp exists- do not prompt for system password"
      _has_system_pwd=true
    fi
  else
    # .sp does not exist; do not create it or its directory here- we need to
    # create the niagara user first so we can give that user ownership and set
    # permissions correctly. Will need to prompt for system password.
    log
    log ".sp does not exist- user will be prompted for system password"
    _has_system_pwd=false
  fi
}

function check_install_files
{
  # Verify the pwd
  if [ ! -e "install.sh" ]; then
    echolog
    echolog "The Niagara 4 installer has detected that you are not"
    echolog "operating from the correct directory to sucessfully install Niagara."
    echolog
    echolog "Please verify that you are working in the same directory as the "
    echolog "installation script."
    echolog
    close
  fi

  # Verify the core dist files exist
  if [ ! -e "${NRE_CORE_DIST_DIR}/${CORE_DIST_X86_64}" ]; then
    echolog
    get_install_prop_value installIntroFalse.message "The Niagara 4 installer could not find file"
    echolog "${_prop_value} ${CORE_DIST_X86_64}"
    get_install_prop_value installIntroFalse.message2 "in directory"
    echolog "${_prop_value} ${NRE_CORE_DIST_DIR}"
    close
  elif [ ! -e "${JRE_DIST_DIR}/${JRE_DIST_X86_64}" ]; then
    echolog
    get_install_prop_value installIntroFalse.message "The Niagara 4 installer could not find file"
    echolog "${_prop_value} ${JRE_DIST_X86_64}"
    get_install_prop_value installIntroFalse.message2 "in directory"
    echolog "${_prop_value} ${JRE_DIST_DIR}"
    close
  elif [ ! -e "${NRE_CONFIG_DIST_DIR}/${CONFIG_DIST_X86_64}" ]; then
    echolog
    get_install_prop_value installIntroFalse.message "The Niagara 4 installer could not find file"
    echolog "${_prop_value} ${CONFIG_DIST_X86_64}"
    get_install_prop_value installIntroFalse.message2 "in directory"
    echolog "${_prop_value} ${NRE_CONFIG_DIST_DIR}"
    close
  else
    echolog
    echolog_prop_value installIntroTrue.message "The Niagara 4 installer will attempt to install"
    echolog "- ${NRE_CORE_DIST_DIR}/${CORE_DIST_X86_64}"
    echolog "- ${JRE_DIST_DIR}/${JRE_DIST_X86_64}"
    echolog "- ${NRE_CONFIG_DIST_DIR}/${CONFIG_DIST_X86_64}"
    echolog
  fi
}

function accept_license
{
  # Look for branded license agreement
  local brand_license=""
  if [ -n "${BRAND_ID}" ]; then
    brand_license="${OVERLAY_LIB}/${BRAND_ID}LicenseAgreement.txt"
  fi

  echolog
  echolog_prop_value licenseAgreement.message "Please read the following license agreement:"

  echolog
  echolog -r "${ENTER_MESSAGE}"
  echolog

  # Display agreement
  echolog
  if [ -r "${brand_license}" ]; then
    cat <(unzip -p "${NRE_CONFIG_DIST_DIR}/${CONFIG_DIST_X86_64}" "${LICENSE_AGREEMENT}") <(echo) "${brand_license}" | fold -s | more
  else
    unzip -p "${NRE_CONFIG_DIST_DIR}/${CONFIG_DIST_X86_64}" "${LICENSE_AGREEMENT}" | fold -s | more
  fi

  # Accept
  while true; do
    echolog
    echolog_prop_value -n licenseAgreement.accept "Do you accept this agreement?"
    echolog -n " "
    echolog_prop_value -r userEntry.noDefault "[yes/no]:"
    get_user_response

    if ${_resp_no}; then
      echolog
      echolog_prop_value licenseAgreement.decline "You need to accept the end user license agreement to install Niagara ${VERSION}, goodbye."
      close
    elif ${_resp_yes}; then
      break
    fi
  done
}

function calc_install_sizes
{
  # Calculate the space required for install
  _space_required=$(stat -c%s "${NRE_CORE_DIST_DIR}/${CORE_DIST_X86_64}")

  if [ -d "${PWD}/modules" ]; then
    cd "${PWD}/modules"
    get_size "${PWD}"
    cd ..
    let "_space_required=${_space_required}+${_generic_size}"
  fi

  # Gather dist and doc space required
  echolog
  echolog_prop_value -n fileSize.query "Gathering information about Niagara ${VERSION} file sizes:"

  if [ -d "${PWD}/docs" ]; then
    cd "${PWD}/docs"
    get_size "${PWD}"
    _doc_size=${_generic_size}
    cd ..
  fi

  if [ -d "${PWD}/dist" ]; then
    cd "${PWD}/dist"
    get_size "${PWD}"
    _dist_size=${_generic_size}
    cd ..
  fi

  let "_space_required=${_space_required}/1024"
  let "_dist_size=${_dist_size}/1024"
  let "_doc_size=${_doc_size}/1024"

  if (( ${_space_required} == 0 )); then
    size_error_undetermined
  elif (( ${_doc_size} == 0 )) && [ -d "${PWD}/docs" ]; then
    size_error_undetermined " documentation"
  elif (( ${_dist_size} == 0 )) && [ -d "${PWD}/dist" ]; then
    size_error_undetermined " as an installation tool"
  else
    error_handler
  fi

  echolog
}

function prompt_system_pwd
{
  if ${_has_system_pwd}; then
    log "System password already exists and user is not prompted"
    return
  fi

  echolog "Set the passphrase used to encrypt sensitive information on the filesystem."
  echolog "The passphrase must be at least ten characters long and may only contain spaces, "
  echolog "letters, numbers, or punctuation/symbols (!\"#\$%&'()*+,-./:;<=>?@[\\]^_\`{|}~). "
  echolog "It must contain at least one uppercase letter, at least one lowercase letter, "
  echolog "and at least one number."

  while true; do
    echolog
    read -rs -p "Passphrase: "
    local entered_pwd="${REPLY}"
    echo

    if [ -z "${entered_pwd}" ]; then
      echolog "Passphrase cannot be empty."
      continue
    fi

    read -rs -p "Confirm Passphrase: "
    if [ "${REPLY}" != "${entered_pwd}" ]; then
      echo
      echolog "Passphrase values do not match. Please try again."
      continue
    fi
    echo

    local count="${#entered_pwd}"
    if [ "${count}" -lt "10" ]; then
      echolog "Passphrase contains ${count} characters instead of at least 10."
      continue
    fi

    local result="${entered_pwd//[[:graph:] ]}"
    if [ "${#result}" -gt "0" ]; then
      echolog "Passphrase contains one or more invalid characters."
      continue
    fi

    local result="${entered_pwd//[[:alpha:][:punct:] ]}"
    if [ "${#result}" -lt "1" ]; then
      echolog "Passphrase does not contain at least 1 number."
      continue
    fi

    local result="${entered_pwd//[[:digit:][:lower:][:punct:] ]}"
    if [ "${#result}" -lt "1" ]; then
      echolog "Passphrase does not contain at least 1 uppercase letter."
      continue
    fi

    local result="${entered_pwd//[[:digit:][:upper:][:punct:] ]}"
    if [ "${#result}" -lt "1" ]; then
      echolog "Passphrase does not contain at least 1 lowercase letter."
      continue
    fi

    # Passphrase meets requirements
    echolog "Passphrase accepted"
    echolog
    _system_pwd="${entered_pwd}"
    break
  done
}

function store_system_pwd
{
  if ${_has_system_pwd}; then
    # System password already exists; this also means /etc/niagara already
    # exists because, otherwise, it would not have found .sp
    
    # Make sure that the .sp file has the appropriate permissions
    chown ${NIAGARA_USER}:${NIAGARA_GROUP} "${NIAGARA_ETC_DIR}/${NIAGARA_SP_FILE}" >> ${LOG_FILE} 2>&1
    chmod 0660 "${NIAGARA_ETC_DIR}/${NIAGARA_SP_FILE}"                             >> ${LOG_FILE} 2>&1
    
    # Nothing else to do
    return
  fi

  # If directory does not exist, create it.
  if ! mkdir -p "${NIAGARA_ETC_DIR}" >> ${LOG_FILE} 2>&1; then
    echolog
    echolog "The Niagara 4 installer failed to create a directory for Niagara configuration "
    echolog "files."
    close
  fi

  # Set permissions on the directory
  # Niagara user needs r/w to regenerate the system password file if it is
  # changed through the daemon.
  if ! chown "${NIAGARA_USER}":"${NIAGARA_GROUP}" "${NIAGARA_ETC_DIR}" >> ${LOG_FILE} 2>&1 ||
     ! chmod 0770 "${NIAGARA_ETC_DIR}"                                 >> ${LOG_FILE} 2>&1; then
    echolog
    echolog "The Niagara 4 installer failed to setup a directory for Niagara configuration "
    echolog "files."
    close
  fi

  # Create the sp file
  # Niagara user needs r/w to regenerate the system password file if it is 
  # changed through the daemon. Niagara group (Stations) should not require
  # read access at all.
  local sp="${NIAGARA_ETC_DIR}/${NIAGARA_SP_FILE}"
  if ! touch "${sp}" ||
     ! echo -n "${_system_pwd}" >> "${sp}" ||
     ! chown ${NIAGARA_USER}:${NIAGARA_GROUP} "${sp}" >> ${LOG_FILE} 2>&1 ||
     ! chmod 0660 "${sp}" >> ${LOG_FILE} 2>&1; then
    echolog
    echolog "The Niagara 4 installer failed to create a Niagara system password file. "
    close
  fi
}

function run_nre_commands
{
  # Assert pre-conditions
  
  # If directory does not exist, create it.
  if ! mkdir -p "${NIAGARA_ETC_DIR}" >> ${LOG_FILE} 2>&1; then
    echolog
    echolog "The Niagara 4 installer failed to create a directory for Niagara configuration "
    echolog "files."
    close
  fi

  # Set permissions on the directory
  # Niagara user needs r/w to regenerate the system password file if it is
  # changed through the daemon.
  if ! chown "${NIAGARA_USER}":"${NIAGARA_GROUP}" "${NIAGARA_ETC_DIR}" >> ${LOG_FILE} 2>&1 ||
     ! chmod 0770 "${NIAGARA_ETC_DIR}"                                 >> ${LOG_FILE} 2>&1; then
    echolog
    echolog "The Niagara 4 installer failed to setup a directory for Niagara configuration "
    echolog "files."
    close
  fi  
  
  # If the key material file already exists make sure niagara user can read/write  
  if [ -e "${NIAGARA_ETC_DIR}/${NIAGARA_KM_FILE}" ]; then
    chown ${NIAGARA_USER}:${NIAGARA_GROUP} "${NIAGARA_ETC_DIR}/${NIAGARA_KM_FILE}" >> ${LOG_FILE} 2>&1
    chmod 0660 "${NIAGARA_ETC_DIR}/${NIAGARA_KM_FILE}"                             >> ${LOG_FILE} 2>&1
  fi
  
  # If the physical address file already exists make sure niagara user is owner
  if [ -e "${INSTALL_DIR}/etc/.paddr" ]; then 
    chown ${NIAGARA_USER}:${NIAGARA_GROUP} "${INSTALL_DIR}/etc/.paddr" >> ${LOG_FILE} 2>&1
  fi   

  OLDPWD="${PWD}"
  cd "${INSTALL_DIR}/bin"
  
  # Manually specify niagara user's home to prevent root folder from being created
  local niagara_dir="/home/${NIAGARA_USER}/Niagara4.9"
  local brand_dir="${niagara_dir}/${BRAND_ID:-"tridium"}"  
  export niagara_user_home="${brand_dir}"
  
  # Make sure the nre command can be executed
  chmod 0755 "${INSTALL_DIR}/bin/nre"                             >> ${LOG_FILE} 2>&1
  chown ${NIAGARA_USER}:${NIAGARA_GROUP} "${INSTALL_DIR}/bin/nre" >> ${LOG_FILE} 2>&1
    
  # Create an installer helper script to run the nre command
  echo "#!/bin/bash"                        > "${INSTALL_DIR}/bin/installer_helper.sh"
  echo "\"${INSTALL_DIR}/bin/nre\" -hostid" >> "${INSTALL_DIR}/bin/installer_helper.sh"
  chmod 0755 "${INSTALL_DIR}/bin/installer_helper.sh"                             >> ${LOG_FILE} 2>&1
  chown ${NIAGARA_USER}:${NIAGARA_GROUP} "${INSTALL_DIR}/bin/installer_helper.sh" >> ${LOG_FILE} 2>&1
  
  # Set niagara environment variables
  if ! source .niagara >> ${LOG_FILE} 2>&1; then
    _error=1
    error_handler
    echolog
    echolog "The Niagara 4 installer failed to set the host ID and generate key material."
    unset niagara_user_home
    close  
    
  # NCCB-24893: The linux installer needs to run the nre hostid command as the niagara user and not as root
  # Create hostID and key material as niagara user, use current directory specifier to get around possible space content
  elif ! runuser -m -u "${NIAGARA_USER}" -g "${NIAGARA_GROUP}" "./installer_helper.sh" >> ${LOG_FILE} 2>&1; then
    _error=1
    error_handler
    echolog
    echolog "The Niagara 4 installer failed to set the host ID."
    unset niagara_user_home
    rm -f "./installer_helper.sh"
    close

  # Assert that ownership is niagara:niagara, permissions to 0440
  elif ! chown ${NIAGARA_USER}:${NIAGARA_GROUP} "${INSTALL_DIR}/etc/.paddr" >> ${LOG_FILE} 2>&1; then
    _error=1
    error_handler
    echolog
    echolog "The Niagara 4 installer failed to set permissions on the host ID file."
    unset niagara_user_home    
    rm -f "./installer_helper.sh"
    close

  # Assert that ownership is niagara:niagara, permissions to 0660
  elif ! chown ${NIAGARA_USER}:${NIAGARA_GROUP} "${NIAGARA_ETC_DIR}/${NIAGARA_KM_FILE}" >> ${LOG_FILE} 2>&1 ||
       ! chmod 0660 "${NIAGARA_ETC_DIR}/${NIAGARA_KM_FILE}" >> ${LOG_FILE} 2>&1; then
    _error=1
    error_handler
    echolog
    echolog "The Niagara 4 installer failed to set permissions on the key material file."
    unset niagara_user_home
    rm -f "./installer_helper.sh"
    close
  fi
  
  # Remove the root's niagara user home created by the nre command (if it exists)
  if [ -d "/root/Niagara4.9" ]; then
    if ! rm -rf "/root/Niagara4.9" >> ${LOG_FILE} 2>&1; then
      log "WARNING: Failed to remove root's niagara home"
    fi
  fi
  
  # Clean up
  unset niagara_user_home
  rm -f "./installer_helper.sh"

  cd "${OLDPWD}"
}

function prompt_install_dir
{
  # Enter the absolute path to the directory where you want to install Niagara
  while true; do
    echolog_prop_value installDirectory.query1 "Enter the absolute path to the directory where you want"
    echolog_prop_value -n installDirectory.query2 "to install Niagara ${VERSION}"
    echolog -r " [${DEFAULT_INSTALL_DIR}]:"
    _selected_dir="${REPLY}"
    get_user_response

    if ${_resp_default}; then
      # Using default location/file
      echolog
      echolog_prop_value -n installDirectory.default "Using default location/file"
      echolog " ${DEFAULT_INSTALL_DIR}..."
      echolog
      _selected_dir="${DEFAULT_INSTALL_DIR}"
    else
      if echo "${_selected_dir}" | egrep -x "/([-%~A-Za-z0-9._ ]+/?)*" > /dev/null 2>&1; then
        :
      else
        invalid_path
        continue
      fi

      echolog
      if echo "${_selected_dir}" | grep /$ > /dev/null 2>&1; then
        _selected_dir="$(echo "${_selected_dir%"/"}")"
      fi
    fi

    # Check the size of the selected partition
    if check_partition "${_selected_dir}"; then
      invalid_path
      continue
    else
      if [ -d "${_selected_dir}" ]; then
        break
      fi

      echolog
      ${SETFORE_WHITE} && ${SETBACK_BROWN}
      echolog -n "${WARNING_MESSAGE}"
      ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
      echolog ": The directory \"${_selected_dir}\" does not exist."

      while true; do
        # As if the user would like to create the directory if it does not exist
        echolog -r "Would you like to create it? [YES/no]:"
        get_user_response

        if ${_resp_yes} || ${_resp_default}; then
          break
        elif ${_resp_no}; then
          echolog
          echolog_prop_value -n installDirectory.decline "Niagara ${VERSION} cannot be installed without creating"
          echolog " \"${_selected_dir}\""
          continue
        fi

        invalid_entry
      done
      break
    fi
  done

  readonly _selected_dir
}

function prompt_users
{
  while true; do
    echolog
    echolog_prop_value -r userAdd.query "Would you like to configure which users can use Niagara 4? [YES/no]:"
    get_user_response

    if ${_resp_yes} || ${_resp_default}; then
      while true; do
        echolog
        echolog_prop_value -r userAdd.getID "Enter the username of a user who will be using Niagara 4:"
        get_user_response

        if ${_resp_default}; then
          continue
        else
          if awk -F: '{print $1}' /etc/passwd | grep -o "^${REPLY}\$" > /dev/null 2>&1; then
            _users[_users_count]=${REPLY}
            let "_users_count=${_users_count}+1"

            echolog
            echolog_prop_value -r userAdd.accept "User accepted. Would you like to add another? [YES/no]:"
            get_user_response

            if ${_resp_yes} || ${_resp_default}; then
              continue;
            elif ${_resp_no}; then
              break
            else
              invalid_entry
              continue
            fi

          else
            echolog
            echolog -n "User ${REPLY} "
            echolog_prop_value -r userAdd.reject "does not appear to be a valid user. Would you like to enter another? [YES/no]:"
            get_user_response

            if ${_resp_yes} || ${_resp_default}; then
              continue;
            elif ${_resp_no}; then
              break
            else
              invalid_entry
              continue
            fi
          fi
        fi
      done

      break

    elif ${_resp_no}; then
      break
    else
      invalid_entry
      continue
    fi
  done
}

function prompt_sudoers
{
  echolog
  echolog "As a security precaution, only the user \"${NIAGARA_USER}\" may start and stop the "
  echolog "niagarad process. The file \"/etc/sudoers\" can be modified to grant all users "
  echolog "in the group \"${NIAGARA_GROUP}\" permission to start and stop the niagarad "
  echolog "process."

  while true; do
    echolog
    echolog -r "Should the installer make the necessary modifications to \"/etc/sudoers\"? [yes/NO]:"

    get_user_response

    if ${_resp_yes}; then
      _add_etc_sudoers=true
      break;
    elif ${_resp_no} || ${_resp_default}; then
      _add_etc_sudoers=false
      break;
    fi

    invalid_entry
  done
}

function prompt_docs
{
  while true && [ -d "${PWD}/docs" ]; do
    echolog
    get_install_prop_value installDoc.query "Do you want to install Niagara documentation"
    echolog -n "${_prop_value} ($(printf "%'d" ${_doc_size})K)? "
    echolog_prop_value -r userEntry.defaultYes "[YES/no]:"
    get_user_response

    if ${_resp_yes} || ${_resp_default}; then
      if (( ${_doc_size} >= ${_space_available} )); then
        size_error_not_enough "docs file" ${_doc_size}
      else
        _install_doc=true
        let "_space_available=${_space_available}-${_doc_size}"
        break
      fi
    elif ${_resp_no}; then
      _install_doc=false
      break
    fi

    invalid_entry
  done
}

function prompt_install_tool
{
  get_install_prop_value "install.installationTool" "true"
  if [ "${_prop_value}" == "true" -a -d "${PWD}/dist" ]; then
    _prompt_for_dist=true
    
    while true; do
      echolog
      echolog_prop_value -n installDist.query "Do you want Niagara to be used as an installation tool"
      echolog -n " ($(printf "%'d" ${_dist_size})K)? "
      echolog_prop_value -r userEntry.defaultYes "[YES/no]:"
      get_user_response

      if ${_resp_yes} || ${_resp_default}; then
        if (( ${_dist_size} >= ${_space_available} )); then
          size_error_not_enough "installation tool" ${_dist_size}
        else
          _install_dist=true
          let "_space_available=${_space_available}-${_dist_size}"
          break
        fi
      elif ${_resp_no}; then
        _install_dist=false
        break
      fi

      invalid_entry
    done
  else
    _prompt_for_dist=false
    _install_dist=false
  fi
}

function verify_install_settings
{
  # Please review the following installation settings:
  echolog
  echolog_prop_value install.verifyIntro "Please review the following installation settings:"
  echolog
  echolog "Installation Directory: ${_selected_dir}"

  #if (( ${_users_count} == 1 )); then
  #  echolog "Generate sudoers configuration for user: ${_users[0]}"
  #elif (( ${_users_count} > 1 )); then
  #  echolog -n "Generate sudoers configuration for users: "
  #  for ((idx=0;${idx}<${_users_count};idx++)); do
  #    echolog -n "${user} "
  #  done
  #  echolog
  #fi

  if ${_add_etc_sudoers}; then
    echolog "Modify \"/etc/sudoers\" for group: niagara"
  fi

  if ${_install_desktop_shortcuts}; then
    if (( ${_users_count} == 1 )); then
      echolog "Add GNOME desktop shortcuts for user: ${_users[0]}"
    elif (( ${_users_count} > 1 )); then
      echolog -n "Add GNOME desktop shortcuts for users: "
      local idx
      for ((idx=0;${idx}<${_users_count};idx++)); do
        echolog -n "${_users[${idx}]} "
      done
      echolog
    fi
  fi

  if ${_install_menu_shortcuts}; then
    if (( ${_users_count} == 1 )); then
      echolog "Add GNOME menu shortcuts for user: ${_users[0]}"
    elif (( ${_users_count} > 1 )); then
      echolog -n "Add GNOME menu shortcuts for users: "
      local idx
      for ((idx=0;${idx}<${_users_count};idx++)); do
        echolog -n "${_users[${idx}]} "
      done
      echolog
    fi
  fi

  if [ -d "${PWD}/docs" ]; then
    echolog -n "Install documentation: "
    if ! ${_install_doc}; then
      echolog "no"
    else
      echolog "yes"
    fi
  fi

  if ${_prompt_for_dist}; then
    echolog -n "Install distribution files: "
    if ! ${_install_dist}; then
      echolog "no"
    else
      echolog "yes"
    fi
  fi

  echolog

  while true; do
    echolog_prop_value -r install.verifyConfirm "Please verify these settings. Do you want to continue? [YES/no]:"
    get_user_response

    if ${_resp_yes} || ${_resp_default}; then
      echolog
      break
    elif ${_resp_no}; then
      get_install_prop_value install.verifyReject "Please restart install.sh and enter the correct settings."
      close
    fi

    invalid_entry
  done
}

function create_niagara_user_user_home
{
  #create the base directory if required
  if [ ! -d "/home/${NIAGARA_USER}" ]; then
    mkdir -p "/home/${NIAGARA_USER}"                                  >> ${LOG_FILE} 2>&1
  fi
  
  #make sure the base directory is usable by the niagara group
  chown "${NIAGARA_USER}":"${NIAGARA_GROUP}" "/home/${NIAGARA_USER}"  >> ${LOG_FILE} 2>&1
  chmod 0750 "/home/${NIAGARA_USER}"                                  >> ${LOG_FILE} 2>&1
  
  #create directories sub items
  local niagara_dir="/home/${NIAGARA_USER}/Niagara4.9"
  local brand_dir="${niagara_dir}/${BRAND_ID:-"tridium"}"
  if ! mkdir -p "${brand_dir}"                                     >> ${LOG_FILE} 2>&1 ||
     ! chown "${NIAGARA_USER}":"${NIAGARA_GROUP}" "${niagara_dir}" >> ${LOG_FILE} 2>&1 ||
     ! chown "${NIAGARA_USER}":"${NIAGARA_GROUP}" "${brand_dir}"   >> ${LOG_FILE} 2>&1 ; then
    echolog
    echolog "The Niagara 4 installer failed to create a niagara user home for the niagara "
    echolog "user: ${brand_dir}"
    close
  fi
}

function create_niagara_user_group
{
  echolog -n "Creating the user ${NIAGARA_USER}:${NIAGARA_GROUP}..."
  # Assume if you find the user id in the system that the group also exists.
  if cat /etc/passwd | grep "^${NIAGARA_USER}:x:.*:${_useradd_nologin_arg}$" >> ${LOG_FILE} 2>&1; then
    create_niagara_user_user_home
    
    _error=0
    error_handler
    log "${NIAGARA_USER} already exists"
  else
    # force the addition of the user
    if /usr/sbin/groupadd ${_groupadd_force_arg} \
                          ${_groupadd_gid_arg}   \
                          5011                   \
                          ${NIAGARA_GROUP} >> ${LOG_FILE} 2>&1; then
      if /usr/sbin/useradd ${_useradd_comment_arg}     \
                           "Niagara Daemon User"       \
                           ${_useradd_gid_arg}         \
                           ${NIAGARA_GROUP}            \
                           ${_useradd_create_home_arg} \
                           ${_useradd_shell_arg}       \
                           ${_useradd_nologin_arg}     \
                           ${_useradd_uid_arg}         \
                           5011                        \
                           ${NIAGARA_USER} >> ${LOG_FILE} 2>&1; then
        create_niagara_user_user_home

        _error=0
        error_handler
        log "${NIAGARA_GROUP} group added; ${NIAGARA_USER} user added"
      else
        # if the return code is 9, means the user already exists, so suppress
        # and continue
        if [ "${?}" != "9" ]; then
          _error=1
          error_handler

          get_install_prop_value userAdd.userFail "The Niagara 4 installer could not create the user"
          echolog "${_prop_value} ${NIAGARA_USER}."
          echolog_prop_value userAdd.cannotContinue "The installer cannot continue."
          close
        else
          create_niagara_user_user_home

          _error=0
          error_handler
          log "${NIAGARA_GROUP} group added; ${NIAGARA_USER} user already exists"
        fi
      fi
    else
      _error=1
      error_handler

      get_install_prop_value userAdd.groupFail "The Niagara 4 installer could not create the group"
      echolog "${_prop_value} ${NIAGARA_GROUP}."
      echolog_prop_value userAdd.cannotContinue "The installer cannot continue."
      close
    fi
  fi
}

function create_install_dir
{
  local current_create
  local current_level
  local word
  local last_word

  if [ -d "${_selected_dir}" ]; then
    log "Selected directory ${_selected_dir} already exists"
    current_create="${_selected_dir}"
  else
    log "Selected directory ${_selected_dir} DOES NOT exist"

    current_create=""
    current_level="${_selected_dir}"

    while [ "${current_level}" ]; do
      word="${current_level}"
      while [ "${word}" ]; do
        last_word="${word}"
        word="$(echo "${word%/*[_-~%A-Za-z0-9\.]}")"
      done

      current_create="${current_create}${last_word}"

      log -n "Creating ${current_create}..."
      if [ -e "${current_create}" ]; then
        if [ -f "${current_create}" ]; then
          echolog "\"${current_create}\" already exists as a normal file."
          echolog "Installer cannot continue."
          close
        else
          log "already exists."
        fi
      else
        if ! mkdir "${current_create}"; then
          echolog "Error creating directory \"${current_create}\"."
          echolog "Installer cannot continue."
          close
        elif ! chown "${NIAGARA_USER}":"${NIAGARA_GROUP}" "${current_create}"; then
          echolog "Error changing ownership of directory \"${current_create}\"."
          echolog "Installer cannot continue."
          close
        else
          log "success."
        fi
      fi

      current_level="$(echo "${current_level#"${last_word}"}")"
    done
  fi

  INSTALL_DIR="${current_create}"
  readonly INSTALL_DIR
  log "Installing to ${INSTALL_DIR}"
}

function scrub_scripts
{
  scrub_script "${INSTALL_DIR}/bin/gradlew"
  scrub_script "${INSTALL_DIR}/bin/niagaradlog"
  scrub_script "${INSTALL_DIR}/bin/.niagara"
  scrub_script "${INSTALL_DIR}/defaults/colorCoding.properties"
  scrub_script "${INSTALL_DIR}/defaults/nre.properties"
  scrub_script "${INSTALL_DIR}/defaults/system.properties"
  scrub_script "${INSTALL_DIR}/defaults/workbench/facetKeys.properties"
  scrub_script "${INSTALL_DIR}/etc/brand.properties"
  scrub_script "${INSTALL_DIR}/etc/extensions.properties"
  scrub_script "${INSTALL_DIR}/install/add_n4_user.sh"
  scrub_script "${INSTALL_DIR}/install/install_common.sh"
  scrub_script "${INSTALL_DIR}/install/install_service.sh"
  scrub_script "${INSTALL_DIR}/install/niagarad_generic"
  scrub_script "${INSTALL_DIR}/install/remove_n4_user.sh"
  scrub_script "${INSTALL_DIR}/lib/licenseAgreement.txt"
  scrub_script "${INSTALL_DIR}/lib/readmeLicenses.txt"
  scrub_script "${INSTALL_DIR}/uninstall/uninstall.sh"
  scrub_script "${INSTALL_DIR}/uninstall/uninstall_service.sh"
}

function cleanup_files
{
  rm -rf "${INSTALL_DIR}/${CONFIG_DIST_X86_64}" >> ${LOG_FILE} 2>&1
  rm -rf "${INSTALL_DIR}/${CORE_DIST_X86_64}"   >> ${LOG_FILE} 2>&1
  rm -rf "${INSTALL_DIR}/${JRE_DIST_X86_64}"    >> ${LOG_FILE} 2>&1

  # install-data should be in install
  if ! cp -R "./install-data" "${INSTALL_DIR}/install" >> ${LOG_FILE} 2>&1; then
    _error=1
    error_handler
    echolog "Failed to copy ./install-data to ${INSTALL_DIR}/install"
    close
  fi

  # Move install_common.sh to install for use by add/remove user,
  # install/uninstall service, and uninstall application scripts
  if ! cp install_common.sh "${INSTALL_DIR}/install" >> ${LOG_FILE} 2>&1; then
    _error=1
    error_handler
    echolog "Failed to copy install_common.sh to ${INSTALL_DIR}/install"
    close
  fi

  # Move niagarad_generic to the install directory, as it only has to do with
  # installation...
  if ! mv "${INSTALL_DIR}/bin/niagarad_generic" "${INSTALL_DIR}/install" >> ${LOG_FILE} 2>&1; then
    _error=1
    error_handler
    echolog "Failed to move ${INSTALL_DIR}/bin/niagarad_generic to ${INSTALL_DIR}/install"
    close
  fi

  # Do not include the install.sh script in the install directory
  rm -f "${INSTALL_DIR}/install/install.sh" >> ${LOG_FILE} 2>&1
}

function set_permissions
{
  # run a blind pass
  if ! chmod -R 0775 "${INSTALL_DIR}"                               >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chown -R "${NIAGARA_USER}:${NIAGARA_GROUP}" "${INSTALL_DIR}" >> ${LOG_FILE} 2>&1; then _error=1; fi

  # do some stuff on executable dirs
  if ! chmod 0775 "${INSTALL_DIR}/bin"        >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod 0775 "${INSTALL_DIR}/lib"        >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod -R 0775 "${INSTALL_DIR}/jre/bin" >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod -R 0775 "${INSTALL_DIR}/jre/lib" >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod -R 0775 "${INSTALL_DIR}/modules" >> ${LOG_FILE} 2>&1; then _error=1; fi

  #do some stuff on exec dir contents
  if ! chmod 0755 "${INSTALL_DIR}/bin/"*        >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod 0755 "${INSTALL_DIR}/bin/.niagara" >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod 0775 "${INSTALL_DIR}/lib/"*        >> ${LOG_FILE} 2>&1; then _error=1; fi

  # tighten down security on sensitive executables, only owning user and group can execute

  # if the install scripts are at the parent level, move them into the appropriate sub-directories
  if [ ! -d "${INSTALL_DIR}/install" ]; then
    if ! mkdir -p "${INSTALL_DIR}/install"                                    >> ${LOG_FILE} 2>&1; then _error=1; fi
    if ! chmod -R 0770 "${INSTALL_DIR}/install"                               >> ${LOG_FILE} 2>&1; then _error=1; fi
    if ! chown -R "${NIAGARA_USER}:${NIAGARA_GROUP}" "${INSTALL_DIR}/install" >> ${LOG_FILE} 2>&1; then _error=1; fi    
  fi
  
  if [ ! -d "${INSTALL_DIR}/uninstall" ]; then
    if ! mkdir -p "${INSTALL_DIR}/uninstall"                                    >> ${LOG_FILE} 2>&1; then _error=1; fi
    if ! chmod -R 0770 "${INSTALL_DIR}/uninstall"                               >> ${LOG_FILE} 2>&1; then _error=1; fi
    if ! chown -R "${NIAGARA_USER}:${NIAGARA_GROUP}" "${INSTALL_DIR}/uninstall" >> ${LOG_FILE} 2>&1; then _error=1; fi    
  fi
  
  if [ -e "${INSTALL_DIR}/INSTALL" ]; then
    mv -f "${INSTALL_DIR}/INSTALL" "${INSTALL_DIR}/install/INSTALL"
  fi   
  
  if [ -e "${INSTALL_DIR}/README" ]; then
    mv -f "${INSTALL_DIR}/README" "${INSTALL_DIR}/install/README"
  fi    
  
  if [ -e "${INSTALL_DIR}/install.sh" ]; then
    mv -f "${INSTALL_DIR}/install.sh" "${INSTALL_DIR}/install/install.sh"
  fi  
  
  if [ -e "${INSTALL_DIR}/install_common.sh" ]; then
    mv -f "${INSTALL_DIR}/install_common.sh" "${INSTALL_DIR}/install/install_common.sh"
  fi
  
  if [ -e "${INSTALL_DIR}/install_service.sh" ]; then
    mv -f "${INSTALL_DIR}/install_service.sh" "${INSTALL_DIR}/install/install_service.sh"
  fi
  
  if [ -e "${INSTALL_DIR}/add_n4_user.sh" ]; then
    mv -f "${INSTALL_DIR}/add_n4_user.sh" "${INSTALL_DIR}/install/add_n4_user.sh"
  fi
  
  if [ -e "${INSTALL_DIR}/remove_n4_user.sh" ]; then
    mv -f "${INSTALL_DIR}/remove_n4_user.sh" "${INSTALL_DIR}/install/remove_n4_user.sh"
  fi
  
  if [ -e "${INSTALL_DIR}/uninstall_service.sh" ]; then
    mv -f "${INSTALL_DIR}/uninstall_service.sh" "${INSTALL_DIR}/uninstall/uninstall_service.sh"
  fi
  
  if [ -e "${INSTALL_DIR}/uninstall.sh" ]; then
    mv -f "${INSTALL_DIR}/uninstall.sh" "${INSTALL_DIR}/uninstall/uninstall.sh"
  fi    
  
  if ! chmod 0550 "${INSTALL_DIR}/install/install_common.sh"      >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod 0550 "${INSTALL_DIR}/install/install_service.sh"     >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod 0550 "${INSTALL_DIR}/install/add_n4_user.sh"         >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod 0550 "${INSTALL_DIR}/install/remove_n4_user.sh"      >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod 0550 "${INSTALL_DIR}/uninstall/uninstall_service.sh" >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod 0550 "${INSTALL_DIR}/uninstall/uninstall.sh"         >> ${LOG_FILE} 2>&1; then _error=1; fi
  
  if ! chmod 0550 "${INSTALL_DIR}/bin/${LAUNCHER_NAME}"           >> ${LOG_FILE} 2>&1; then _error=1; fi
   
  # set permissions on the niagaradctl service manager
  set_niagaradctl_permissions

  # setuid on nsupport, run as root when invoked
  if ! chmod 0000 "${INSTALL_DIR}/bin/nsupport"                 >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chown 0:${NIAGARA_GROUP} "${INSTALL_DIR}/bin/nsupport"   >> ${LOG_FILE} 2>&1; then _error=1; fi
  if ! chmod 4410 "${INSTALL_DIR}/bin/nsupport"                 >> ${LOG_FILE} 2>&1; then _error=1; fi

  # determine if SELinux is enabled, if so, update the context of the Niagara binaries 
  if selinuxenabled; then
    # SELinux enabled    
    chcon -t texrel_shlib_t "${INSTALL_DIR}"/bin/*.so                  >> ${LOG_FILE} 2>&1
    chcon -t texrel_shlib_t "${INSTALL_DIR}"/jre/lib/amd64/*.so        >> ${LOG_FILE} 2>&1
    chcon -t texrel_shlib_t "${INSTALL_DIR}"/jre/lib/amd64/server/*.so >> ${LOG_FILE} 2>&1    
  else 
    # SELinux disabled, if they ever change this they may have to manually update the
    # context themselves
    :
  fi
  
  #NCCB-19124: Linux: Error initializing local license database error in the station output
  #add gid bits to folders under niagara_home we expect to be modified
  
  #we expect modules to be added
  if ! chmod g+s "${INSTALL_DIR}/modules" >> ${LOG_FILE} 2>&1; then _error=1; fi
  
  #we expect licenses to be added
  if [ ! -d "${INSTALL_DIR}/security/licenses" ]; then
    if ! mkdir -p "${INSTALL_DIR}/security/licenses"                                    >> ${LOG_FILE} 2>&1; then _error=1; fi
    if ! chmod -R 0775 "${INSTALL_DIR}/security/licenses"                               >> ${LOG_FILE} 2>&1; then _error=1; fi
    if ! chown -R "${NIAGARA_USER}:${NIAGARA_GROUP}" "${INSTALL_DIR}/security/licenses" >> ${LOG_FILE} 2>&1; then _error=1; fi
  fi
  
  if ! chmod g+s "${INSTALL_DIR}/security/licenses" >> ${LOG_FILE} 2>&1; then _error=1; fi
  
  #we expect certificates to be added
  if [ ! -d "${INSTALL_DIR}/security/certificates" ]; then
    if ! mkdir -p "${INSTALL_DIR}/security/certificates"                                    >> ${LOG_FILE} 2>&1; then _error=1; fi
    if ! chmod -R 0775 "${INSTALL_DIR}/security/certificates"                               >> ${LOG_FILE} 2>&1; then _error=1; fi
    if ! chown -R "${NIAGARA_USER}:${NIAGARA_GROUP}" "${INSTALL_DIR}/security/certificates" >> ${LOG_FILE} 2>&1; then _error=1; fi
  fi
  
  if ! chmod g+s "${INSTALL_DIR}/security/certificates" >> ${LOG_FILE} 2>&1; then _error=1; fi  
  
  #we expect sw to be imported
  if [ ! -d "${INSTALL_DIR}/sw" ]; then
    if ! mkdir -p "${INSTALL_DIR}/sw"                                    >> ${LOG_FILE} 2>&1; then _error=1; fi
    if ! chmod -R 0775 "${INSTALL_DIR}/sw"                               >> ${LOG_FILE} 2>&1; then _error=1; fi
    if ! chown -R "${NIAGARA_USER}:${NIAGARA_GROUP}" "${INSTALL_DIR}/sw" >> ${LOG_FILE} 2>&1; then _error=1; fi
  fi  
  
  if ! chmod g+s "${INSTALL_DIR}/sw" >> ${LOG_FILE} 2>&1; then _error=1; fi
  
  #anything else?  

  if (( _error != 0 )); then
    error_handler
    close
  fi
}

# Also creates the uninstall file
function summarize_install
{
  echo "#UNDER NO CIRCUMSTANCES SHOULD YOU MODIFY THIS FILE, SERIOUSLY!" > "${INSTALL_DIR}/uninstall.conf"
  echo "INSTALL_DIR=${INSTALL_DIR}" >> "${INSTALL_DIR}/uninstall.conf"

  echolog
  echolog_prop_value installFinished.summary "Summary"
  echolog "--------------------------------------------------------------------------------"

  get_install_prop_value installFinished.installedAt "Niagara ${VERSION} was installed at"
  echolog "${_prop_value} ${_selected_dir}."

  if [ -d "${PWD}/docs" ]; then
    if ${_install_doc}; then
      echolog_prop_value installFinished.installedDocTrue "Niagara documentation was installed."
    else
      echolog_prop_value installFinished.installedDocFalse "Niagara documentation was not installed."
    fi
  fi

  if ${_prompt_for_dist}; then
    if ${_install_dist}; then
      echolog_prop_value installFinished.installedDistTrue "Niagara will function as an installation tool."
    else
      echolog_prop_value installFinished.installedDistFalse "Niagara will not function as an installation tool."
    fi
  fi

  if (( ${_users_count} >= 1 )); then
    if ${_install_desktop_shortcuts}; then
      echolog_prop_value installFinished.installedDesktopTrue "Niagara added GNOME shortcuts to the desktop."
    else
      echolog_prop_value installFinished.installedDesktopFalse "Niagara did not add GNOME shortcuts to the desktop."
    fi
  fi

  if (( ${_users_count} >= 1 )); then
    if ${_install_menu_shortcuts}; then
      echolog_prop_value installFinished.installedMenuTrue "Niagara added GNOME shortcuts to the menu."
    else
      echolog_prop_value installFinished.installedMenuFalse "Niagara did not add GNOME shortcuts to the menu."
    fi
  fi

  summarize_service_install

  if ${_installed_usr_bin}; then
    echo "USR_BIN_INSTALLED=true"  >> "${INSTALL_DIR}/uninstall.conf"
  else
    echo "USR_BIN_INSTALLED=false" >> "${INSTALL_DIR}/uninstall.conf"
  fi

  if ${_installed_service}; then
    echo "SERVICE=true" >> "${INSTALL_DIR}/uninstall.conf"
  fi

  local uninstall_dest="${INSTALL_DIR}/uninstall/uninstall.conf"
  mv "${INSTALL_DIR}/uninstall.conf" "${uninstall_dest}"       >> ${LOG_FILE} 2>&1
  chmod 0444 "${uninstall_dest}"                               >> ${LOG_FILE} 2>&1
  chown "${NIAGARA_USER}:${NIAGARA_GROUP}" "${uninstall_dest}" >> ${LOG_FILE} 2>&1

  echolog "--------------------------------------------------------------------------------"
}

function fix_jx_browser
{
  # If we already have libcrypto.so.1.0.0, do nothing
  # If we have another version of libcrypto, make a symlink to libcrypto.so.1.0.0
  # If we do not have libcrypto, we will warn the user to install openssl later
  local libcrypto="$(ls /usr/lib64/ | grep libcrypto.so | sed -e '$!d')"
  if [ -e "/usr/lib64/libcrypto.so.1.0.0" ]; then
    _libcrypto_found=true
  elif [ "${libcrypto}" != "" ]; then
    _libcrypto_found=true
    if ! ln -s "${libcrypto}" /usr/lib64/libcrypto.so.1.0.0 >> ${LOG_FILE} 2>&1; then
      _error=1
      error_handler
      echolog
      echolog "Failed to create a symlink to libcrypto.so.1.0.0"
      close
    fi
  fi
  
  # If do not have libXss, we will warn the user to install it later
  if [ -e "/usr/lib64/libXss.so.1" ]; then
    _libxss_found=true
  fi
}

function final_instructions
{
  echolog
  echolog "BEFORE YOU CAN BEGIN USING NIAGARA:"
  echolog "In order to start using niagarad you will need to do a few manual steps."
  echolog

  if ${_add_etc_sudoers}; then
    #check to see if they already have a sudoers entry?
    if cat /etc/sudoers | grep "^%${NIAGARA_GROUP}" > /dev/null 2>&1; then
      #already have it?
      echolog "You selected to add necessary information to the \"/etc/sudoers\" file,"
      echolog "but it appears the necessary entry is already there."
    else
      echo                                                                                   >> /etc/sudoers
      echo "# Members of the ${NIAGARA_GROUP} group may start and stop the niagarad process" >> /etc/sudoers
      echo "%${NIAGARA_GROUP} ALL=(${NIAGARA_GROUP}) NOPASSWD: /usr/bin/niagaradctl"         >> /etc/sudoers

      echolog "The following information was added to your \"/etc/sudoers\" file:"
      echolog
      echolog "# Members of the ${NIAGARA_GROUP} group may start and stop the niagarad process"
      echolog "%${NIAGARA_GROUP} ALL=(${NIAGARA_GROUP}) NOPASSWD: /usr/bin/niagaradctl"
    fi
  else
    echolog "As a security precaution, Niagara is owned by the new user/group ${NIAGARA_GROUP}."
    echolog "You will need to modify the file \"/etc/sudoers\" with the command 'visudo'"
    echolog "to grant other users the permissions to run Niagara as the user ${NIAGARA_USER}."
    echolog "Niagara has generated the following configuration for \"/etc/sudoers\":"
    echolog

    echolog "# Members of the ${NIAGARA_GROUP} group may start and stop the niagarad process"
    echolog "%${NIAGARA_GROUP} ALL=(${NIAGARA_GROUP}) NOPASSWD: /usr/bin/niagaradctl"

    #if (( ${_users_count} == 0 )); then
    #  echolog "add user(s) here       ALL=(${NIAGARA_GROUP}) NOPASSWD: ${USR_BIN_NAME}"
    #elif (( ${_users_count} == 1 )); then
    #  echolog "${_users[0]}  ALL=(${NIAGARA_GROUP}) NOPASSWD: ${USR_BIN_NAME}"
    #else
    #  for ((idx=0;${idx}<${_users_count};idx++)); do
    #    TEMP=
    #    let "TEMP=${idx}+1"
    #    if (( $TEMP == ${_users_count} )); then
    #      echolog -n "${_users[${idx}]}"
    #    else
    #      echolog -n "${_users[${idx}]},"
    #    fi
    #  done
    #  echolog "  ALL=(${NIAGARA_GROUP}) NOPASSWD: ${USR_BIN_NAME}"
    #fi
  fi

  echolog
  echolog "You will need to source the .niagara script in "
  echolog "${INSTALL_DIR}/bin "
  echolog "before you will be able to use Workbench or Nre from a terminal. We advise "
  echolog "linking this script to your home directory and including it in the execution of "
  echolog "your .bash_profile and .bashrc scripts."
  echolog
  echolog "\"Sourcing\" the script is accomplished by typing "
  echolog "\". ${INSTALL_DIR}/bin/.niagara\" "
  echolog "at the prompt"
  echolog
  echolog "You will also need to allow udp traffic on port 4911 and tcp traffic on ports"
  echolog "4911, 5011 and 8443 to pass through your local fire wall if you intend to"
  echolog "connect to the local Niagara daemon."
  echolog

  if ${_is_redhat}; then
    echolog "  firewall-cmd --zone=public --permanent --add-port=4911/udp"
    echolog "  firewall-cmd --zone=public --permanent --add-port=4911/tcp"
    echolog "  firewall-cmd --zone=public --permanent --add-port=5011/tcp"
    echolog "  firewall-cmd --zone=public --permanent --add-port=8443/tcp"
    echolog "  firewall-cmd --reload"
    echolog
    echolog "Add the following if you wish to redirect traffic for port 443 to port 8443:"
    echolog
    echolog "  firewall-cmd --zone=public --permanent --add-forward-port=port=443:proto=tcp:toport=8443"
    echolog "  firewall-cmd --reload"
    echolog
  elif ${_is_debian} || ${_is_amazon}; then
    echolog "  iptables -A INPUT -p udp -m state --state NEW --destination-port 4911 -j ACCEPT"
    echolog "  iptables -A INPUT -p tcp -m state --state NEW --destination-port 4911 -j ACCEPT"
    echolog "  iptables -A INPUT -p tcp -m state --state NEW --destination-port 5011 -j ACCEPT"
    echolog "  iptables -A INPUT -p tcp -m state --state NEW --destination-port 8443 -j ACCEPT"
    echolog
    echolog "Add the following if you wish to redirect traffic for port 443 to port 8443:"
    echolog
    echolog "  iptables -t nat -A PREROUTING -p tcp -m tcp --destination-port 443 -j REDIRECT --to-ports 8443"
    echolog
    echolog "If you intend to make IPv6 connections to Niagara instances, please modify your"
    echolog "IPv6 firewall, using the \"ip6tables\" command, as well."
    echolog
  fi
  
  if ! ${_libcrypto_found}; then
    ${SETFORE_WHITE} && ${SETBACK_BROWN}
    echolog -n "${WARNING_MESSAGE}"
    ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
    echolog ": Could not find openssl package required for fully functional"
    echolog "Workbench web views. If you intend to use Workbench, please install"
    echolog "openssl with \"sudo yum install openssl\" and create a symlink from"
    echolog "\"usr/lib64/libcrypto.x.x.x\" to \"/usr/lib64/libcrypto.so.1.0.0\"."
    echolog
  fi
  if ! ${_libxss_found}; then
    ${SETFORE_WHITE} && ${SETBACK_BROWN}
    echolog -n "${WARNING_MESSAGE}"
    ${SETFORE_NORMAL} && ${SETBACK_NORMAL}
    echolog ": Could not find libXScrnSaver package required for fully functional"
    echolog "Workbench web views. If you intend to use Workbench, please install"
    echolog "libXScrnSaver with \"sudo yum install libXScrnSaver\"."
    echolog
  fi

  ${SETFORE_BLUE}
  echolog "If you installed Niagara ${VERSION} while logged in as one of the configured"
  echolog "users, you will need to logout/login before his new permissions will take effect."
  echolog
  ${SETFORE_NORMAL}
}

function main
{
  remove_existing_log

  check_if_root
  check_os
  check_executables
  check_cmd_arg_format

  scrub_props_files
  get_localized_msgs
  get_brand_id
  get_nre_config_distribution_dir
  get_nre_core_distribution_dir
  get_jre_distribution_dir  
  get_default_install_dir
  check_sp_file
  check_install_files

  clear

  echolog_prop_value welcome.message "Welcome to Niagara Install!"
  echolog_prop_value welcome.message2 "This program will install the Niagara4 Runtime Environment onto your computer."
  echolog
  echolog "${BUILD}"
  echolog "${BUILD_DATE}"

  accept_license

  calc_install_sizes

  prompt_system_pwd
  prompt_install_dir
  prompt_users
  prompt_sudoers
  prompt_desktop_shortcuts
  prompt_menu_shortcuts
  prompt_docs
  prompt_install_tool

  verify_install_settings

  get_install_prop_value installStart.verifyAccept "Niagara will now install. This will take a while."
  sleep 1

  create_niagara_user_group
  create_users_of_niagara

  store_system_pwd

  create_install_dir
  install_dists

  install_folder "modules"

  if ${_install_doc}; then
    install_folder "docs"
  fi

  if ${_install_dist}; then
    echolog -n "Installing folder: dist..."
    if ! cp -R "${PWD}/dist" "${INSTALL_DIR}/sw" >> ${LOG_FILE} 2>&1; then
      _error=1
      error_handler
      close
    fi
    error_handler
  else
    mkdir -p "${INSTALL_DIR}/sw" >> ${LOG_FILE} 2>&1
  fi

  # Always create the application launcher even if not creating desktop or menu shortcuts.
  # This will ensure that the application launcher permissions are set correctly when
  # referenced by shortcuts created using the add_n4_user script
  create_app_launcher
  scrub_script "${INSTALL_DIR}/bin/${LAUNCHER_NAME}"

  if ${_install_desktop_shortcuts}; then
    install_desktop_shortcuts
  fi

  if ${_install_menu_shortcuts}; then
    install_menu_shortcuts
  fi

  echolog -n "Reticulating splines..."
  sleep 2
  _error=0
  error_handler

  _niagarad_generic_file="${INSTALL_DIR}/bin/niagarad_generic"
  if check_service && check_usrbin; then
    install_service
  fi

  create_environment

  echolog -n "Setting permissions and cleaning up..."

  mkdir -p "${INSTALL_DIR}/uninstall" >> ${LOG_FILE} 2>&1
  mkdir -p "${INSTALL_DIR}/install"   >> ${LOG_FILE} 2>&1
  mkdir -p "${INSTALL_DIR}/logs"      >> ${LOG_FILE} 2>&1

  cleanup_files
  set_permissions
  scrub_scripts

  run_nre_commands
  fix_jx_browser

  error_handler

  echolog
  echolog_prop_value installFinished.message "Niagara ${VERSION} installation is complete!"

  summarize_install
  final_instructions

  echolog_prop_value installFinished.thanks "Thank you for installing Niagara ${VERSION}"
  echolog

  close_log

  exit 0
}

main "$@"
