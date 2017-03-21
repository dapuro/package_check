#!/bin/bash

# Depends on global variables: $level[*], $GLOBAL* ...
_test_result_positive() {
  local -r index=$1

  case $index in 
    1)
      [[ $GLOBAL_CHECK_SETUP == 1 && $GLOBAL_CHECK_REMOVE == 1 ]]
      ;;
    2)
      [[ $GLOBAL_CHECK_SUB_DIR != -1 && $GLOBAL_CHECK_REMOVE_SUBDIR != -1 && $GLOBAL_CHECK_ROOT != -1 && $GLOBAL_CHECK_REMOVE_ROOT != -1 && $GLOBAL_CHECK_PRIVATE != -1 && $GLOBAL_CHECK_PUBLIC != -1 && $GLOBAL_CHECK_MULTI_INSTANCE != -1 ]]
      ;;
    3)
      [[ $GLOBAL_CHECK_UPGRADE == 1 || ( ${level[3]} == "2" && $GLOBAL_CHECK_UPGRADE != -1 ) ]]
      ;;
    5)
      [[ $GLOBAL_LINTER == 1 || ( ${level[5]} == "2" && $GLOBAL_LINTER != -1 ) ]]
      ;;
    6)
      [[ $GLOBAL_CHECK_BACKUP == 1 && $GLOBAL_CHECK_RESTORE == 1 || ( ${level[6]} == "2" && $GLOBAL_CHECK_BACKUP != -1 && $GLOBAL_CHECK_RESTORE != -1 ) ]]
      ;;
    7)
      [[ $GLOBAL_CHECK_SETUP != -1 && $GLOBAL_CHECK_REMOVE != -1 && $GLOBAL_CHECK_SUB_DIR != -1 && $GLOBAL_CHECK_REMOVE_SUBDIR != -1 && $GLOBAL_CHECK_REMOVE_ROOT != -1 && $GLOBAL_CHECK_UPGRADE != -1 && $GLOBAL_CHECK_PRIVATE != -1 && $GLOBAL_CHECK_PUBLIC != -1 && $GLOBAL_CHECK_MULTI_INSTANCE != -1 && $GLOBAL_CHECK_ADMIN != -1 && $GLOBAL_CHECK_DOMAIN != -1 && $GLOBAL_CHECK_PATH != -1 && $GLOBAL_CHECK_PORT != -1 && $GLOBAL_CHECK_BACKUP != -1 && $GLOBAL_CHECK_RESTORE != -1 && ${level[5]} -ge -1 ]]
      ;;
  esac
}

# Depends on global variables: $level[*]
_map_test_results_to_level() {
  local i=-1

  for i in {1..7}; do

    if [[ $i == 4 ]]; then
      continue
    fi

    if [[ ${level[$i]} == "auto" || ${level[$i]} == 2 ]]; then
      if _test_result_positive $i; then
        level[$i]=2
      else
        level[$i]=0
      fi
    fi
  done
}

# Depends on global variables: level[*]
_calculate_final_level() {
  local i=-1
  local result=0

	for i in {1..10}; do
		if [[ ${level[$i]} == "auto" ]]; then
			level[$i]=0
		elif [[ ${level[$i]} == "na" ]]; then
			continue
		elif [[ ${level[$i]} -ge 1 ]]; then
			result=$i
		else
			break
		fi
	done

  echo $result
}

APP_LEVEL() {
	level=0 	# Initialise le niveau final à 0

  _map_test_results_to_level

  level=$( _calculate_final_level )
}

_print_test_result() {
  local -r result=$1
  local -r title=$2

  printf "%28s" "${title}:"

	if [[ $result -eq 1 ]]; then
		ECHO_FORMAT "\tSUCCESS\n" "lgreen"
	elif [[ $result -eq -1 ]]; then
		ECHO_FORMAT "\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\tNot evaluated.\n" "white"
	fi
}

# FIXME: 
# 1) the order in which test results are displayed
# 2) displayed tab indention
# Depends on global variables: $GLOBAL*
_print_test_results() {
  declare -A results
  local result=0
  local title=""
  local value=""
  local i=-1

  results[1]="Package Linter:$GLOBAL_LINTER"
  results[2]="Installation:$GLOBAL_CHECK_SETUP"
  results[3]="Removal:$GLOBAL_CHECK_REMOVE"
  results[4]="Installation on sub-path:$GLOBAL_CHECK_SUB_DIR"
  results[5]="Removal from sub-path:$GLOBAL_CHECK_REMOVE_SUBDIR"
  results[6]="Installation on root-path:$GLOBAL_CHECK_ROOT"
  results[7]="Removal from root-path:$GLOBAL_CHECK_REMOVE_ROOT"
  results[8]="Upgrade:$GLOBAL_CHECK_UPGRADE"
  results[9]="Private installation:$GLOBAL_CHECK_PRIVATE"
  results[10]="Public installation:$GLOBAL_CHECK_PUBLIC"
  results[11]="Multi-instance installation:$GLOBAL_CHECK_MULTI_INSTANCE"
  results[12]="Bad user:$GLOBAL_CHECK_ADMIN"
  results[13]="Wrong domain:$GLOBAL_CHECK_DOMAIN"
  results[14]="Wrong path:$GLOBAL_CHECK_PATH"
  results[15]="Port already in use:$GLOBAL_CHECK_PORT"
  results[16]="Backup:$GLOBAL_CHECK_BACKUP"
  results[17]="Restore:$GLOBAL_CHECK_RESTORE"

  ECHO_FORMAT "\n\n"

  for i in {1..17}; do
    result="${results[$i]}"
    title=$( echo $result | cut -d : -f1 )
    value=$( echo $result | cut -d : -f2 )

    _print_test_result "$value" "$title"
  done
}

# Depends on global variables: $note, $tnote, $level, $level[]
_print_test_results_summary() {
  local color_note=""
  local typo_note=""
  local smiley=""

  ECHO_FORMAT "\n"

  printf '\e[1m\e[97m%28s\e[0m' "Results:"

	ECHO_FORMAT "\t$note/$tnote - " "white" "bold"

	if [[ $note -gt 0 ]]; then
		note=$(( note * 20 / tnote ))
	fi

  if [[ $note -le 5 ]]; then
    color_note="red"
    typo_note="bold"
    smiley=":'("
  elif [[ $note -le 10 ]]; then
    color_note="red"
    smiley=":("
  elif [[ $note -le 15 ]]; then
    color_note="lyellow"
    smiley=":s"
  elif [[ $note -gt 15 ]]; then
    color_note="lgreen"
    smiley=":)"
  fi

  if [[ $note -ge 20 ]]; then
    color_note="lgreen"
    typo_note="bold"
    smiley="\o/"
  fi

	ECHO_FORMAT "$note/20 $smiley\n" "$color_note" "$typo_note"

  printf '\e[1m\e[97m%28s\e[0m' "Test Set:"
	ECHO_FORMAT "\t$tnote/21\n\n" "white" "bold"

  printf "%28s" "Application quality level:"

	ECHO_FORMAT "\t$level\n" "white" "bold"

  ECHO_FORMAT "\n"

	for i in {1..10}
	do
		printf "%28s" "Level $i:"

    ECHO_FORMAT "\t"

		if [[ ${level[i]} == "na" ]]; then
			ECHO_FORMAT "N/A\n"
		elif [[ ${level[i]} -ge 1 ]]; then
			ECHO_FORMAT "1\n" "white" "bold"
		else
			ECHO_FORMAT "0\n"
		fi
	done

  ECHO_FORMAT "\n"
}

TEST_RESULTS() {
  APP_LEVEL

  _print_test_results
  _print_test_results_summary
}
