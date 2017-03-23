#!/usr/bin/env bats

source "../lib/check_process_parsing.sh"

setup() {
  declare -A level

  INPUT_FILE="../fixtures/check_process"
  all_test=0
  pkg_linter=-1
  setup_sub_dir=-1
  setup_root=-1
  setup_nourl=-1
  setup_private=-1
  setup_public=-1
  upgrade=-1
  backup_restore=-1
  multi_instance=-1
  wrong_user=-1
  wrong_path=-1
  incorrect_path=-1
  corrupt_source=-1
  fail_download_source=-1
  final_path_already_use=-1
  port_already_use=-1
  PORTX=-1
}

teardown() {
 echo ""
 # Implement me
}

@test "_get_and_process_checks_value when arg is found" {

  skip

  local -r line="pkg_linter=1"

  _get_and_process_checks_value "$line" "pkg_linter"

  [[ $? == 0 ]]
  (( $all_test == 1 ))
}

@test "_get_checks_value when arg is not found" {
  
  skip

  local -r line="upgrade=1"

  run _get_and_process_checks_value "$line" "pkg_linter" 


  [[ $status == 1 ]]
  (( $all_test == 0 ))
}

@test "_parse_test_setup" {

  _parse_test_setup $INPUT_FILE

  [[ $pkg_linter == 1 ]]
  [[ $setup_sub_dir == 1 ]]
  [[ $setup_root == 1 ]]
  [[ $setup_nourl == 1 ]]
  [[ $setup_private == 1 ]]
  [[ $setup_public == 1 ]]
  [[ $upgrade == 1 ]]
  [[ $backup_restore == 1 ]]
  [[ $multi_instance == 1 ]]
  [[ $wrong_user == 1 ]]
  [[ $wrong_path == 1 ]]
  [[ $incorrect_path == 1 ]]
  [[ $corrupt_source == 1 ]]
  [[ $fail_download_source == 1 ]]
  [[ $final_path_already_use == 1 ]]
  [[ $port_already_use == 1 ]]

  # [[ $PORTX == 66 ]]
}
