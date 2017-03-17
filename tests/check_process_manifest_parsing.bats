#!/usr/bin/env bats

source "../lib/check_process_parsing.sh"

setup() {
  declare -A level

  INPUT_FILE="../fixtures/check_process"

  IN_PROCESS=0
  MANIFEST_DOMAIN=""
  MANIFEST_PATH=""
  MANIFEST_USER=""
  MANIFEST_PUBLIC=""
  MANIFEST_PUBLIC_public=""
  MANIFEST_PUBLIC_private=""
  MANIFEST_PASSWORD=""
  MANIFEST_PORT=""
  MANIFEST_ARGS=""
}

teardown() {
 echo ""
 # Implement me
}

@test "_line_is_manifest_section" {

  run  _line_is_manifest_section "; Manifest is cool"

  [[ $status == 0 ]]
}

@test "Manifest section is found" {
  _parse_test_setup $INPUT_FILE

  (( $IN_PROCESS == 1 ))
}


@test "Manifest DOMAIN is correctly parsed" {
  _parse_test_setup $INPUT_FILE

  [[ $MANIFEST_DOMAIN == "domain" ]]
  # [[ $MANIFEST_ARGS == "domain=domain.tld&" ]]
}

@test "Manifest PATH is correctly parsed" {
  _parse_test_setup $INPUT_FILE

  [[ $MANIFEST_PATH == "path" ]]
}

@test "Manifest USER is correctly parsed" {
  _parse_test_setup $INPUT_FILE

  [[ $MANIFEST_USER == "admin" ]]
}

@test "Manifest PASSWORD is correctly parsed" {
  _parse_test_setup $INPUT_FILE

  [[ $MANIFEST_PASSWORD == "password" ]]
}

@test "Manifest PORT is correctly parsed" {
  _parse_test_setup $INPUT_FILE

  [[ $MANIFEST_PORT == "port" ]]
}

@test "Manifest PUBLIC is correctly parsed" {
  _parse_test_setup $INPUT_FILE

  [[ $MANIFEST_PUBLIC == "is_public" ]]
}

@test "Manifest PUBLIC_public is correctly parsed" {
  _parse_test_setup $INPUT_FILE

  [[ $MANIFEST_PUBLIC_public == "Yes" ]]
}

@test "Manifest PUBLIC_private is correctly parsed" {
  _parse_test_setup $INPUT_FILE

  [[ $MANIFEST_PUBLIC_private == "No" ]]
}

@test "Manifest MANIFEST_ARGS is correctly set" {
  _parse_test_setup $INPUT_FILE

  expected="domain=domain.tld&path=/path&admin=john&is_public=Yes&password=pass&port=666&"

  [[ $MANIFEST_ARGS == $expected ]]
}
