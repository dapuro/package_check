#!/usr/bin/env bats

source "../lib/check_process_parsing.sh"

setup() {
  declare -A level

  INPUT_FILE="../fixtures/check_process"
}

teardown() {
 echo ""
 # Implement me
}

@test "_clear_spaces_from_beginning" {
  line=" This is a test"

  result=$( _clear_spaces_from_beginning "$line" )

  [[ $result == "This is a test" ]]
}

@test "_parse_levels" {
  _parse_levels $INPUT_FILE

  [[ ${level[1]} == "auto" ]]
  [[ ${level[2]} == "na" ]]
}
