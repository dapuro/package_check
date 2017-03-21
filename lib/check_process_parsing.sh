#!/bin/bash

_line_is_comment() {
  local -r line=$1

  [[ ${line:0:1} == "#" ]]
}

_clear_spaces_from_beginning() {
  local -r line=$1

  echo $line | sed -e 's/^ *//g'
}

_line_is_levels_section() {
  local -r line=$1

  echo "$line" | grep -q "^;;; Levels"
}

_line_is_levels_setting() {
  local -r line=$1

  echo "$line" | grep -q "Level" 
}

# Depends on global variable $level[]
_parse_levels() {
  local -r input_file=$1
  local index=-1
  local value=""
  local line=""

  IN_LEVELS=0
  while read <&4 line; do
    line=$( _clear_spaces_from_beginning "$line" )

    if _line_is_comment $line; then
      continue
    fi

    if $( _line_is_levels_section "$line" ); then
      IN_LEVELS=1
    fi

    if (( $IN_LEVELS == 1 )); then
      if _line_is_levels_setting "$line"; then
        index=$(echo "$line" | cut -d '=' -f1 | cut -d ' ' -f2)
        value=$(echo "$line" | cut -d '=' -f2)
        level[$index]=$value
      fi
    fi
  done 4< $input_file
}

_line_is_autoremove() {
  local -r line=$1

  echo $line | grep -q "^auto_remove="
}

# starts with two ";
_line_is_test_section() {
  local -r line=$1

  echo "$line" | grep -q "^;;" && ! echo "$line" | grep -q "^;;;"
}

_line_is_manifest_section() {
  local -r line=$1

  echo "$line" | grep -q "^; Manifest"
}

_line_is_checks_section() {
  local -r line=$1

  echo "$line" | grep -q "^; Checks"
}

_line_is_a_setting() {
  local -r line=$1

  echo "$line" | grep -q "="
}

_get_setting_key() {
  local -r line=$1

  echo "$line" | cut -d '=' -f1
}

_remove_setting_indicator() {
  local -r line=$1

  echo "$line" | cut -d '(' -f1
}

_remove_whitspace_and_quotes() {
  local -r line=$1

  echo $line | sed 's/^ *\| *$\|\"//g'
}

_get_and_process_checks_value() {
  local -r line=$1
  local -r varname=$2
  local value=""

  if echo "$line" | grep -q "^${varname}="; then

    value=$(echo "$line" | cut -d '=' -f2)

    # Special Case "port"
    if echo "$line" | grep -q "([0-9]*)"; then	

      # FIXME: for some reason assignment doesnt stick?
      # PORTX=66 #"$( echo $line | cut -d '(' -f2 | cut -d ')' -f1)"

      value=${value:0:1}
    fi

    if [[ $value == 1 ]]; then
      all_test=$((all_test+1))
    fi

    echo $value
  else
    echo ${!varname}
  fi
}

# Depends on global variables: 
# $auto_remove,  $IN_PROCESS, $bash_mode, 
# $PROCESS_NAME, $MANIFEST, $CHECKS
# $MANIFEST_ARGS                             
_parse_test_setup() {
  local -r input_file=$1
  local line=""
  local arg=""

  while read <&4 line; do
    line=$( _clear_spaces_from_beginning "$line" )

    if _line_is_comment $line; then
      continue
    fi

    if _line_is_autoremove $line; then
      value=$(echo "$line" | cut -d '=' -f2)
      auto_remove=$value
    fi

    if _line_is_test_section "$line"; then

      # FIXME: when is this ever the case?
      if [[ $IN_PROCESS -eq 1 ]]; then # A scenario is already underway. So we reached the end of the scenario.
        TESTING_PROCESS
        TEST_RESULTS
        INIT_VAR

        if [[ "$bash_mode" -ne 1 ]]; then
          read -p "Press a key to start the next test scenario..." < /dev/tty
        fi
      fi

      PROCESS_NAME=${line#;; }
      IN_PROCESS=1
      MANIFEST=0
      CHECKS=0
      IN_LEVELS=0
    fi

    if [ "$IN_PROCESS" -eq 1 ]; then

      if _line_is_manifest_section "$line"; then
        MANIFEST=1
        MANIFEST_ARGS=""
      fi

      if _line_is_checks_section "$line"; then
        MANIFEST=0
        CHECKS=1
      fi

      if [[ $MANIFEST -eq 1 ]]; then

        if _line_is_a_setting "$line"; then

          if echo "$line" | grep -q "(DOMAIN)"; then
            MANIFEST_DOMAIN=$( _get_setting_key "$line" )
          fi

          if echo "$line" | grep -q "(PATH)"; then
            MANIFEST_PATH=$( _get_setting_key "$line" )
          fi

          if echo "$line" | grep -q "(USER)"; then
            MANIFEST_USER=$( _get_setting_key $line )					
          fi

          if echo "$line" | grep -q "(PUBLIC"; then	
            MANIFEST_PUBLIC=$( _get_setting_key $line )
            MANIFEST_PUBLIC_public=$(echo "$line" | grep -o "|public=[[:alnum:]]*" | cut -d "=" -f2)
            MANIFEST_PUBLIC_private=$(echo "$line" | grep -o "|private=[[:alnum:]]*" | cut -d "=" -f2)
          fi

          if echo "$line" | grep -q "(PASSWORD)"; then
            MANIFEST_PASSWORD=$( _get_setting_key $line )
          fi

          if echo "$line" | grep -q "(PORT)"; then
            MANIFEST_PORT=$( _get_setting_key $line )
          fi

          line=$( _remove_setting_indicator $line )

          arg=$( _remove_whitspace_and_quotes $line )

          MANIFEST_ARGS="$MANIFEST_ARGS$arg&"
        fi
      fi

      if [[ $CHECKS -eq 1 ]]; then

        pkg_linter=$( _get_and_process_checks_value "$line" "pkg_linter" )
        setup_sub_dir=$( _get_and_process_checks_value "$line" "setup_sub_dir" )
        setup_root=$( _get_and_process_checks_value "$line" "setup_root" )
        setup_nourl=$( _get_and_process_checks_value "$line" "setup_nourl" )
        setup_private=$( _get_and_process_checks_value "$line" "setup_private" )
        setup_public=$( _get_and_process_checks_value "$line" "setup_public" )
        upgrade=$( _get_and_process_checks_value "$line" "upgrade" )
        backup_restore=$( _get_and_process_checks_value "$line" "backup_restore" )
        multi_instance=$( _get_and_process_checks_value "$line" "multi_instance" )
        wrong_user=$( _get_and_process_checks_value "$line" "wrong_user" )
        wrong_path=$( _get_and_process_checks_value "$line" "wrong_path" )
        incorrect_path=$( _get_and_process_checks_value "$line" "incorrect_path" )
        corrupt_source=$( _get_and_process_checks_value "$line" "corrupt_source" )
        fail_download_source=$( _get_and_process_checks_value "$line" "fail_download_source" )
        final_path_already_use=$( _get_and_process_checks_value "$line" "final_path_already_use" )
        port_already_use=$( _get_and_process_checks_value "$line" "port_already_use" )
      fi
    fi
  done 4< $input_file
}
