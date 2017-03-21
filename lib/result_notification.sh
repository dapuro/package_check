#!/bin/bash

notify_via_xmpp() {
  local -r message=$1
  local -r conf_file=$( _auto_build_conf_file )
  local -r xmpp_bot_post_script=$( _xmpp_bot_post_script )
  local -r domain=""
  local -r path=""

  if file_exists $conf_file; then
    domain=$(grep "DOMAIN=" "$script_dir/../auto_build/auto.conf" | cut -d= -f2)
    path=$(grep "CI_PATH=" "$script_dir/../auto_build/auto.conf" | cut -d= -f2)
    ci_path="$domain/$path"

    message="$message sur https://$ci_path"

    xmpp_bot_post_script $message
  fi
}

get_app_maintainer_email() {
  local -r test_app_manifest_file=$( _test_app_manifest_file )

  echo $(cat "$test_app_manifest_file" | grep '\"email\": ' | cut -d '"' -f 4)
}

notify_via_mail() {
  local -r message=$1
  local -r level=$2
  local -r config_file="$script_dir/../config" # FIXME: what config file is this?
  local -r recipient=""

  if [[ $level == 0 && $( file_exists $config_file ) ]]; then	

    recipient=$( get_app_maintainer_email )

    ci_path=$(grep "CI_URL=" $config_file | cut -d= -f2)
    
    if [[ -n $ci_path ]]; then
      message="$message sur $ci_path"
    fi
    mail -s "[YunoHost] Failed to install an application in the CI" "$recpicient" <<< "$message"
  fi
}

