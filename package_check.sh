#!/bin/bash

### REFACTORED START ###

# GLOBAL VARIABLES

readonly PROGNAME=$(basename $0)
readonly PROGDIR=$(readlink -m $(dirname $0))
readonly PROGFULLPATH="$PROGDIR/$PROGNAME"
readonly ARGS="$@"

bash_mode=0
no_lxc=0
build_lxc=0
gitbranch=""
force_install_ok=0
arg_app=""
script_dir=""

USER_TEST="package_checker"
USER_TEST_CLEAN=""
PASSWORD_TEST="checker_pwd"
PATH_TEST=/check

PLAGE_IP=""
LXC_NAME=""
LXC_BRIDGE=""
YUNO_PWD=""
DOMAIN=""
main_iface=""
SOUS_DOMAIN=""

GIT_PACKAGE=0
APP_CHECK=""
APP_PATH_YUNO=""
check_file=1

note=0
tnote=0
level=0

GLOBAL_LINTER=0
GLOBAL_CHECK_SETUP=0
GLOBAL_CHECK_SUB_DIR=0
GLOBAL_CHECK_ROOT=0
GLOBAL_CHECK_REMOVE=0
GLOBAL_CHECK_REMOVE_SUBDIR=0
GLOBAL_CHECK_REMOVE_ROOT=0
GLOBAL_CHECK_UPGRADE=0
GLOBAL_CHECK_BACKUP=0
GLOBAL_CHECK_RESTORE=0
GLOBAL_CHECK_PRIVATE=0
GLOBAL_CHECK_PUBLIC=0
GLOBAL_CHECK_MULTI_INSTANCE=0
GLOBAL_CHECK_ADMIN=0
GLOBAL_CHECK_DOMAIN=0
GLOBAL_CHECK_PATH=0
GLOBAL_CHECK_CORRUPT=0
GLOBAL_CHECK_DL=0
GLOBAL_CHECK_PORT=0
GLOBAL_CHECK_FINALPATH=0
IN_PROCESS=0
MANIFEST=0
CHECKS=0
auto_remove=1
install_pass=0
all_test=0
use_curl=0

MANIFEST_DOMAIN="null"
MANIFEST_PATH="null"
MANIFEST_USER="null"
MANIFEST_PUBLIC="null"
MANIFEST_PUBLIC_public="null"
MANIFEST_PUBLIC_private="null"
MANIFEST_PASSWORD="null"
MANIFEST_PORT="null"

pkg_linter=0
setup_sub_dir=0
setup_root=0
setup_nourl=0
setup_private=0
setup_public=0
upgrade=0
backup_restore=0
multi_instance=0
wrong_user=0
wrong_path=0
incorrect_path=0
corrupt_source=0
fail_download_source=0
port_already_use=0
final_path_already_use=0

# HELPER FUNCTIONS

file_exists() {
  local file=$1

  [[ -e $file ]]
}

is_empty() {
  local var=$1

  [[ -z $var ]]
}

is_dir() {
  local dir=$1

  [[ -d $dir ]]
}

_setup_user_file() {
  echo "$script_dir/sub_scripts/setup_user"
}

_process_lock_file() { 
  echo "$script_dir/pcheck.lock"
}

_package_check_repo() {
  # FIXME
  # echo "https://github.com/YunoHost/package_check"
  echo "https://github.com/dapuro/package_check"
}

_package_check_upgrade_file() {
  echo "$script_dir/upgrade_script.sh"
}

_package_check_version_file() {
	 echo "$script_dir/package_version"
}

_package_linter_repo() {
	 echo "https://github.com/YunoHost/package_linter"
}

_package_linter_version_file() {
	 echo "$script_dir/plinter_version"
}

_package_linter_dir() {
	 echo "$script_dir/package_linter"
}

_config_file() {
	 echo "$script_dir/config"
}

_build_script_file() {
	 echo "$script_dir/sub_scripts/lxc_build.sh"

}


_lxc_container_domain() {
  local -r container_name=$1

  sudo cat /var/lib/lxc/$container_name/rootfs/etc/yunohost/current_host
}

_test_app_dir() {
  echo "$script_dir/$( basename "$arg_app" )_check"
}

_test_app_check_process_file() {
  local -r test_app_dir=$( _test_app_dir )
  
  echo "${test_app_dir}/check_process"
}

_complete_log_file() {
  echo "$COMPLETE_LOG"
}

_test_results_log_file() {
  echo "$RESULT"
}

_lxc_boot_log_file() {
  echo "$script_dir/lxc_boot.log"
}

# FUNCTIONS

usage() {
  local message=$1

  echo $message

  cat <<- EOF
    Usage $PROGNAME [options] path

    Tests a YunoHost application.

    OPTIONS:

      -c --bash-mode           The script is self-contained. It ignores the value of \$auto_remove
      -n --no-lxc              Does not use lxc container virtualization. Virtualization is used by default if available
      -i --build-lxc           Install lxc and create the machine if necessary
      -f --force-install-ok    Forces the success of installations, even if they fail; Performs the tests that follow even if the installation failed 
      -b --branch branch-name  Tests a branch of the repository, rather than testing master
      -h --help                displays script help

    PARAMETERS:
      
      path                  the path to the git repository of the app that shall be tested
EOF
  exit 0
}

usage_error() { 
  local message=$1

  usage "$PROGNAME: $message"
}

parse_options_and_arguments() {
  local args=''
  local arg=''
  for arg in $ARGS
  do
    local delim=""
    case "$arg" in
      #translate --gnu-long-options to -g (short options)
      --bash-mode)    args="${args}-c ";;
      --no-lxc)       args="${args}-n ";;
      --build-lxc)    args="${args}-i ";;
      --help)         args="${args}-h ";;
      --branch)       args="${args}-b ";;
      --force_install_ok)       args="${args}-f ";;
      #pass through anything else
      *) [[ "${arg:0:1}" == "-" ]] || delim="\""
      args="${args}${delim}${arg}${delim} ";;
    esac
  done

  #Reset the positional parameters to the short options
  eval set -- $args

  while getopts "snihb:" OPTION
  do
    case $OPTION in
      s)
        bash_mode=1
        ;;
      n)
        no_lxc=1
        ;;
      i)
        build_lxc=1
        ;;
      h)
        usage
        ;;
      b)
        gitbranch=$OPTARG
        ;;
      f)
        force_install_ok=1
        ;;
    esac
  done


  # check if positional arguments are present
  if [ $(( $# - $OPTIND )) -lt 0 ]; then
    usage_error "argument is required -- path"
  fi

  arg_app=${@:$OPTIND:1}

  if [ ! -d $arg_app ]; then
    usage_error "path does not exist -- $arg_app"
  fi

  return 0
} 

set_script_dir() {
  if [ "${0:0:1}" == "/" ]; then
    script_dir="$(dirname "$0")";
  else
    script_dir=$PROGDIR
  fi
}

ensure_user_can_execute_sript() {
  local -r file=$( _setup_user_file )
  local current_user=""
  local setup_user=""

  if file_exists $file; then
    current_user=$( whoami )
    setup_user=$( cat $file )

    if [ $current_user != $setup_user ]; then
      echo -e "\e[91mScript must be executed with the user $setup_user!\nThe current user is $current_user."
      echo -en "\e[0m"
      exit 0
    fi
  fi
}

ensure_internet_connection_is_working() {
  local result=1
  local domain=''

  for domain in $@
  do
    ping -q -c 2 $domain > /dev/null 2>&1
    if [ "$?" -eq 0 ]; then
      result=0
      break
    fi
  done
  if [ $result -eq 1 ]; then
    ECHO_FORMAT "Unable to establish a connection to the internet.\n" "red"
    exit 1
  fi
}

ensure_no_other_process_is_executing_script() {
  local -r lock=$( _process_lock_file )
  local -r auto_confirm=$1
  local rep="N"

  if file_exists $lock; then
    echo "The process lock ${lock} exists. Package Check seems already in use."

    if [ $auto_confirm -ne 1 ]; then
      echo -n "Do you want to continue anyway and ignore the lock? (Y/N) :"
      read rep
    fi
    
    case ${rep:0:1} in
      Y|y|O|o) 
              # nothing to do
              ;;
            *)
              echo "The execution of Package Check is canceled!"
              exit 0
              ;;
    esac
  fi
  touch $lock
}

_upgrade_package_check() {
  local -r repo_url=$1
  local -r upgrade_script_file=$2
  local -r process_lock_file=$3
  local -r tmp_dir=$( mktemp --directory )

  ECHO_FORMAT "Updating package_check...\n" "white" "bold"

  rm $upgrade_script_file

  {

    echo -e "#!/bin/bash\n"
    echo "git clone --quiet $repo_url \"$tmp_dir\""
    echo "sudo cp --archive \"$tmp_dir/.\" \"$script_dir/.\""
    echo "sudo rm --force --recursive \"$tmp_dir\""
    echo "sudo rm \"$process_lock_file\""
    echo "exec \"$script_dir\" \"$ARGS\""

  } >> $upgrade_script_file

  chmod +x $upgrade_script_file
  exec $upgrade_script_file
}

_get_git_repo_remote_version() {
  local -r repo_url=$1

  echo $( git ls-remote $repo_url \
    | cut -f 1 \
    | head -n1 
  )
}

ensure_package_check_is_up_to_date() {
  local -r repo_url=$( _package_check_repo )
  local -r upgrade_script_file=$( _package_check_upgrade_file )
  local -r local_version_file=$( _package_check_version_file )
  local -r process_lock_file=$( _process_lock_file )
  local -r remote_version=$( _get_git_repo_remote_version $repo_url )
  local local_version=

  if file_exists $local_version_file; then
    local_version=$( cat $local_version_file )

    if [ $remote_version != $local_version ]; then      
      _upgrade_package_check $repo_url $upgrade_script_file $process_lock_file
    fi
  fi
  echo $remote_version > $local_version_file
}

_upgrade_package_linter() {
  local -r repo_url=$1
  local -r target_dir=$2
  local -r tmp_dir=$( mktemp --directory )

  ECHO_FORMAT "Updating package_linter..." "white" "bold"

  git clone --quiet $repo_url $tmp_dir
  cp --archive $tmp_dir $target_dir 
  rm --recursive --force $tmp_dir
}

_install_package_linter() {
  local repo_url=$1
  local target_dir=$2

  ECHO_FORMAT "Installing package_linter.\n" "white"

  git clone --quiet $repo_url $target_dir
}

ensure_package_linter_is_up_to_date() {
  local -r repo_url=$( _package_linter_repo )
  local -r local_version_file=$( _package_linter_version_file )
  local -r target_dir=$( _package_linter_dir )
  local -r remote_version=$( _get_git_repo_remote_version $repo_url )
  local local_version=""

  if file_exists $local_version_file; then
    local_version=$( cat $local_version_file )

    if [ $remote_version != $local_version ]; then      
      _upgrade_package_linter $repo_url $target_dir
    fi
  else
    _install_package_linter $repo_url $target_dir
  fi
  echo $remote_version > $local_version_file
}

_get_value_from_config_file() {
  local -r file=$( _config_file )
  local -r key=$1
  local result=""

  if file_exists $file; then
    result=$( cat $file \
        | grep "${key}=" \
        | cut -d '=' -f2
      )
  fi
  echo $result
}

_get_value_from_build_script_file() {
  local -r file=$( _build_script_file )
  local -r key=$1
  local result=""

  if file_exists $file; then
    if [ $key = "PLAGE_IP" ]; then
      result=$( cat $file \
          | grep "|| ${key}=" \
          | cut -d '"' -f4
        )
    else
      result=$( cat $file \
          | grep "|| ${key}=" \
          | cut -d '=' -f2
        )
    fi
  fi
  echo $result
}

_write_to_config_file() {
  local config_file=$( _config_file )
  local key=$1
  local value=$2
  local comment=$3

	echo -e "# $comment \n${key}=${value}\n" >> $config_file
}

find_and_store_config_value() {
  local -r key=$1
  local -r config_comment=$2
  local result=$( _get_value_from_config_file $key )

  if is_empty $result; then
    result=$( _get_value_from_build_script_file $key )
    _write_to_config_file $key $result "${config_comment}"
  fi

  echo $result
}

find_and_store_iface_config_value() {
  local -r key=$1
  local -r config_comment=$2
  local result=$( _get_value_from_config_file $key )

  if is_empty $result; then
    # FIXME: do we need a sudo here?
    result=$( sudo route \
      | grep default \
      | awk '{print $8;}' 
    )
  fi
  if is_empty $result; then
    ECHO_FORMAT  "Unable to determine the name of the host's network interface." "red"
    exit 1
  else
    _write_to_config_file $key $result "${config_comment}"
  fi

  echo $result
}

_ynh_domain() {
  sudo yunohost domain list -l 1 \
    | cut -d" " -f 2 
}

_remove_process_lock() {
  # FIXME: do we need sudo here?
  sudo rm $( _process_lock_file )
}

lxc_container_is_used() {
  [[ $no_lxc -eq 0 ]]
}

_lxc_installed() {
  dpkg-query --show --showformat='${Status}' "lxc" 2>/dev/null \
    | grep -q "ok installed";
}

_lxc_container_exists() {
  local name=$1

  sudo lxc-ls | grep -q $name
}

ensure_lxc_container_setup() {
  local -r name=$1
  local -r build_lxc=$2
  local -r build_script_file=$( _build_script_file )

  if _lxc_installed && _lxc_container_exists $name; then
    echo "lxc container $container_name is up and running. nothing to do."
  else
		if [ $build_lxc -eq 1 ]
		then
			exec $build_script_file
		else
      ECHO_FORMAT "Lxc is not installed, or the container  $container_name does not exist.\n" "red"
			ECHO_FORMAT "Use the 'lxc_build.sh' script to install lxc and create the machine.\n" "red"
			ECHO_FORMAT "Or use the optional parameter --no-lxc\n" "red"
      _remove_process_lock
			exit 1
		fi
	fi
}

find_or_create_test_user() {
  local -r test_user=$1
  local -r domain=$2
  local -r password=$3
  local test_user_cleaned=""
  local mail=""
  local firstname=""
  local lastname=""

	echo -e "\nCheck if test user exists ..."

	if ! ynh_user_exists $test_user; then

    # Remove underscores
		test_user_cleaned=${test_user//"_"/""}

    firstname="${test_user_cleaned}"
    lastname="${test_user_cleaned}"
    mail="${test_user_cleaned}@${domain}"

		sudo yunohost user create --firstname $firstname  --lastname $lastname --mail $mail --password $password $test_user

		if [ "$?" -ne 0 ]; then
			ECHO_FORMAT "Test user could not be created. Can not continue ... \n" "red"
      _remove_process_lock
			exit 1
    else
      echo $user_test_clean
		fi
	fi
}

_ynh_domain_exists() {
  local -r domain=$1
  local result=1

  result=$( sudo yunohost domain list | grep --count $domain )
  [[ $result -ne 0 ]]
}

_ynh_create_domain() {
  local -r domain=$1
  local result=1

  sudo yunohost domain add $domain

  result=$?
  [[ $result -eq 0 ]]
}

ensure_subdomain_exists() {
  local -r subdomain=$1

	echo "Checking if domain for test exists ..."

	if ! _ynh_domain_exists $subdomain ; then

		if ! _ynh_create_domain $subdomain; then
			ECHO_FORMAT "The creation of the subdomain for the test failed. Can not continue ... \n" "red"
      _remove_process_lock
			exit 1
		fi
	fi
}

_is_url() {
  local -r string=$1

  echo $string | grep --extended-regexp --quiet "https?:\/\/"
  [[ $? -eq 0 ]]
}

duplicate_app_for_test() {
  local -r source_path=$1
  local -r branch=$2
  local -r target_path=$3
  local -r files_and_folder_to_remove=$4

  echo "Retrieve git repository to test."

  if [ $files_and_folder_to_remove != "/" ]; then
    rm --recursive --force $files_and_folder_to_remove
  fi

  if _is_url $source_path; then
    git clone $source_path $branch $target_path
  else
    # FIXME: do we need sudo here?
    sudo cp --archive --remove-destination $source_path $target_path
  fi

}

ensure_test_app_dir_exists() {
  local -r path_to_test_app=$( _test_app_dir )

  if ! is_dir $path_to_test_app; then
    ECHO_FORMAT "The application test folder can not be found!\n" "red"
    _remove_process_lock
    exit 1
  fi
  # FIXME: do we need sudo here?
  sudo rm --recursive --force "$path_to_test_app/.git"
}

ensure_test_app_has_check_process_file() {
  local -r check_process_file=$( _test_app_check_process_file )

  if ! file_exists $check_process_file; then
  	ECHO_FORMAT "\nUnable to find check_process file $check_process_file.\n" "red"
  	ECHO_FORMAT "PackageCheck will run in degraded mode!\n" "lyellow"
    return 1
  fi
}

INIT_LEVEL() {
  local i=-1

  for i in {1..7}; do
    if [[ $i == 4 ]]; then
      level[$i]=0
    else
      level[$i]="auto"
    fi
  done

  for i in {8..10}; do
    level[$i]=0
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

APP_LEVEL() {
	level=0 	# Initialise le niveau final à 0

  _map_test_results_to_level

  level=$( _calculate_final_level )
}

_print_test_result() {
  local -r result=$1
  local -r title=$2

  ECHO_FORMAT "${title}: "
	if [[ $result -eq 1 ]]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [[ $result -eq -1 ]]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
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

  results["Package Linter"]=$GLOBAL_LINTER
  results["Installation"]=$GLOBAL_CHECK_SETUP
  results["Removal"]=$GLOBAL_CHECK_REMOVE
  results["Installation on sub-path"]=$GLOBAL_CHECK_SUB_DIR
  results["Removal from sub-path"]=$GLOBAL_CHECK_REMOVE_SUBDIR
  results["Installation on root-path"]=$GLOBAL_CHECK_ROOT
  results["Removal from root-path"]=$GLOBAL_CHECK_REMOVE_ROOT
  results["Upgrade"]=$GLOBAL_CHECK_UPGRADE
  results["Private installation"]=$GLOBAL_CHECK_PRIVATE
  results["Public installation"]=$GLOBAL_CHECK_PUBLIC
  results["Multi-instance installation"]=$GLOBAL_CHECK_MULTI_INSTANCE
  results["Bad user"]=$GLOBAL_CHECK_ADMIN
  results["Wrong domain"]=$GLOBAL_CHECK_DOMAIN
  results["Wrong path"]=$GLOBAL_CHECK_PATH
  results["Port already in use"]=$GLOBAL_CHECK_PORT
  results["Backup"]=$GLOBAL_CHECK_BACKUP
  results["Restore"]=$GLOBAL_CHECK_RESTORE

  ECHO_FORMAT "\n\n"

  for title in "${!results[@]}"; do
    result=${results["${title}"]}
    _print_test_result "$result" "$title"
  done
}

# Depends on global variables: $note, $tnote, $level, $level[]
_print_test_results_summary() {
  local color_note=""
  local typo_note=""
  local smiley=""

	ECHO_FORMAT "\t\t    Results: $note/$tnote - " "white" "bold"

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
	ECHO_FORMAT "\t   Test set: $tnote/21\n\n" "white" "bold"

	ECHO_FORMAT "Quality level of application: $level\n" "white" "bold"
	for i in {1..10}
	do
		ECHO_FORMAT "\t   Level $i: "
		if [[ ${level[i]} == "na" ]]; then
			ECHO_FORMAT "N/A\n"
		elif [[ ${level[i]} -ge 1 ]]; then
			ECHO_FORMAT "1\n" "white" "bold"
		else
			ECHO_FORMAT "0\n"
		fi
	done
}

TEST_RESULTS() {
  APP_LEVEL

  _print_test_results
  _print_test_results_summary
}

INIT_VAR() {
	GLOBAL_LINTER=0
	GLOBAL_CHECK_SETUP=0
	GLOBAL_CHECK_SUB_DIR=0
	GLOBAL_CHECK_ROOT=0
	GLOBAL_CHECK_REMOVE=0
	GLOBAL_CHECK_REMOVE_SUBDIR=0
	GLOBAL_CHECK_REMOVE_ROOT=0
	GLOBAL_CHECK_UPGRADE=0
	GLOBAL_CHECK_BACKUP=0
	GLOBAL_CHECK_RESTORE=0
	GLOBAL_CHECK_PRIVATE=0
	GLOBAL_CHECK_PUBLIC=0
	GLOBAL_CHECK_MULTI_INSTANCE=0
	GLOBAL_CHECK_ADMIN=0
	GLOBAL_CHECK_DOMAIN=0
	GLOBAL_CHECK_PATH=0
	GLOBAL_CHECK_CORRUPT=0
	GLOBAL_CHECK_DL=0
	GLOBAL_CHECK_PORT=0
	GLOBAL_CHECK_FINALPATH=0
	IN_PROCESS=0
	MANIFEST=0
	CHECKS=0
	auto_remove=1
	install_pass=0
	note=0
	tnote=0
	all_test=0
	use_curl=0

	MANIFEST_DOMAIN="null"
	MANIFEST_PATH="null"
	MANIFEST_USER="null"
	MANIFEST_PUBLIC="null"
	MANIFEST_PUBLIC_public="null"
	MANIFEST_PUBLIC_private="null"
	MANIFEST_PASSWORD="null"
	MANIFEST_PORT="null"

	pkg_linter=0
	setup_sub_dir=0
	setup_root=0
	setup_nourl=0
	setup_private=0
	setup_public=0
	upgrade=0
	backup_restore=0
	multi_instance=0
	wrong_user=0
	wrong_path=0
	incorrect_path=0
	corrupt_source=0
	fail_download_source=0
	port_already_use=0
	final_path_already_use=0
}

initialize_log_files() {
  local -r complete_log_file=$( _complete_log_file )
  local -r test_results_log_file=$( _test_results_log_file )
  local -r lxc_boot_log_file=$( _lxc_boot_log_file )

  echo -n "" > $complete_log_file
  echo -n "" > $test_results_log_file
  echo -n "" | sudo tee $lxc_boot_log_file
}

main() {
  parse_options_and_arguments
  set_script_dir
  ensure_user_can_execute_sript

  source "$script_dir/sub_scripts/lxc_launcher.sh"
  source "$script_dir/sub_scripts/testing_process.sh"
  source /usr/share/yunohost/helpers

  ensure_internet_connection_is_working "yunohost.org" "framasoft.org"
  ensure_no_other_process_is_executing_script $bash_mode
  ensure_package_check_is_up_to_date
  ensure_package_linter_is_up_to_date

  PLAGE_IP=$( find_and_store_config_value "PLAGE_IP" "Public IP of LXC container" )
  LXC_NAME=$( find_and_store_config_value "LXC_NAME" "LXC container name" )
  LXC_BRIDGE=$( find_and_store_config_value "LXC_BRIDGE" "The LXC bridge name" )

  YUNO_PWD=$( find_and_store_config_value "YUNO_PWD" "The Yunohost admin password" )
  
  # FIXME: DOMAIN is updated in lcx block further below. Do we still need this?
  DOMAIN=$( find_and_store_config_value "DOMAIN" "Domain to be tested" )

  main_iface=$( find_and_store_iface_config_value "iface" "The name of the network interface" )

  if lxc_container_is_used; then
	  DOMAIN=$( _lxc_container_domain $LXC_NAME )
    SOUS_DOMAIN="sous.$DOMAIN"

    ensure_lxc_container_setup $LXC_NAME $BUILD_LXC

    # Stops any eventual activity of the container, in the event of a previously incorrect shutdown
    LXC_STOP
    LXC_TURNOFF
  else
	  DOMAIN=$( _ynh_domain )
    SOUS_DOMAIN="sous.$DOMAIN"
    # FIXME: do we really need this global variable?
    USER_TEST_CLEAN=$( find_or_create_test_user $USER_TEST $DOMAIN $PASSWORD_TEST )
    ensure_subdomain_exists $SOUS_DOMAIN
  fi

  local -r test_app_dir=$( _test_app_dir )
  duplicate_app_for_test "${arg_app}" "${gitbranch}" $test_app_dir "${script_dir}/*_check"

  if _is_url $arg_app; then
    GIT_PACKAGE=1
  fi
  APP_CHECK=$test_app_dir

  if lxc_container_is_used; then
	  APP_PATH_YUNO="$(basename "$arg_app")_check"
  else
	  APP_PATH_YUNO="$APP_CHECK"
  fi

  ensure_test_app_dir_exists
  if ensure_test_app_has_check_process_file; then
    echo "" #nothing to do
  else
    check_file=0
  fi

  INIT_VAR
  INIT_LEVEL

  initialize_log_files
}

main

### REFACTORED END ###

if [ "$no_lxc" -eq 0 ]; then
	LXC_INIT
fi

if [ "$check_file" -eq 1 ]
then # Si le fichier check_process est trouvé
	## Parsing du fichier check_process de manière séquentielle.
	echo "Parsing du fichier check_process"
	IN_LEVELS=0
	while read <&4 LIGNE
	do	# Parse les indications de niveaux d'app avant de parser les tests
		LIGNE=$(echo $LIGNE | sed 's/^ *"//g')	# Efface les espaces en début de ligne
		if [ "${LIGNE:0:1}" == "#" ]; then
			continue	# Ligne de commentaire, ignorée.
		fi
		if echo "$LIGNE" | grep -q "^;;; Levels"; then	# Définition des variables de niveaux
			IN_LEVELS=1
		fi
		if [ "$IN_LEVELS" -eq 1 ]
		then
			if echo "$LIGNE" | grep -q "Level "; then	# Définition d'un niveau
				level[$(echo "$LIGNE" | cut -d '=' -f1 | cut -d ' ' -f2)]=$(echo "$LIGNE" | cut -d '=' -f2)
			fi
		fi
	done 4< "$APP_CHECK/check_process"
	while read <&4 LIGNE
	do
		LIGNE=$(echo $LIGNE | sed 's/^ *"//g')	# Efface les espaces en début de ligne
		if [ "${LIGNE:0:1}" == "#" ]; then
			# Ligne de commentaire, ignorée.
			continue
		fi
		if echo "$LIGNE" | grep -q "^auto_remove="; then	# Indication d'auto remove
			auto_remove=$(echo "$LIGNE" | cut -d '=' -f2)
		fi
		if echo "$LIGNE" | grep -q "^;;" && ! echo "$LIGNE" | grep -q "^;;;"; then	# Début d'un scénario de test
			if [ "$IN_PROCESS" -eq 1 ]; then	# Un scénario est déjà en cours. Donc on a atteind la fin du scénario.
				TESTING_PROCESS
				TEST_RESULTS
				INIT_VAR
				if [ "$bash_mode" -ne 1 ]; then
					read -p "Appuyer sur une touche pour démarrer le scénario de test suivant..." < /dev/tty
				fi
			fi
			PROCESS_NAME=${LIGNE#;; }
			IN_PROCESS=1
			MANIFEST=0
			CHECKS=0
			IN_LEVELS=0
		fi
		if [ "$IN_PROCESS" -eq 1 ]
		then	# Analyse des arguments du scenario de test
			if echo "$LIGNE" | grep -q "^; Manifest"; then	# Arguments du manifest
				MANIFEST=1
				MANIFEST_ARGS=""	# Initialise la chaine des arguments d'installation
			fi
			if echo "$LIGNE" | grep -q "^; Checks"; then	# Tests à effectuer
				MANIFEST=0
				CHECKS=1
			fi
			if [ "$MANIFEST" -eq 1 ]
			then	# Analyse des arguments du manifest
				if echo "$LIGNE" | grep -q "="; then
					if echo "$LIGNE" | grep -q "(DOMAIN)"; then	# Domaine dans le manifest
						MANIFEST_DOMAIN=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant au domaine
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
					if echo "$LIGNE" | grep -q "(PATH)"; then	# Path dans le manifest
						MANIFEST_PATH=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant au path
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
					if echo "$LIGNE" | grep -q "(USER)"; then	# User dans le manifest
						MANIFEST_USER=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant à l'utilisateur
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
					if echo "$LIGNE" | grep -q "(PUBLIC"; then	# Accès public/privé dans le manifest
						MANIFEST_PUBLIC=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant à l'accès public ou privé
						MANIFEST_PUBLIC_public=$(echo "$LIGNE" | grep -o "|public=[[:alnum:]]*" | cut -d "=" -f2)	# Récupère la valeur pour un accès public.
						MANIFEST_PUBLIC_private=$(echo "$LIGNE" | grep -o "|private=[[:alnum:]]*" | cut -d "=" -f2)	# Récupère la valeur pour un accès privé.
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
					if echo "$LIGNE" | grep -q "(PASSWORD)"; then	# Password dans le manifest
						MANIFEST_PASSWORD=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant au mot de passe
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
					if echo "$LIGNE" | grep -q "(PORT)"; then	# Port dans le manifest
						MANIFEST_PORT=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant au port
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
# 					if [ "${#MANIFEST_ARGS}" -gt 0 ]; then	# Si il y a déjà des arguments
# 						MANIFEST_ARGS="$MANIFEST_ARGS&"	#, précède de &
# 					fi
					MANIFEST_ARGS="$MANIFEST_ARGS$(echo $LIGNE | sed 's/^ *\| *$\|\"//g')&"	# Ajoute l'argument du manifest, en retirant les espaces de début et de fin ainsi que les guillemets.
				fi
			fi
			if [ "$CHECKS" -eq 1 ]
			then	# Analyse des tests à effectuer sur ce scenario.
				if echo "$LIGNE" | grep -q "^pkg_linter="; then	# Test d'installation en sous-dossier
					pkg_linter=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$pkg_linter" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^setup_sub_dir="; then	# Test d'installation en sous-dossier
					setup_sub_dir=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$setup_sub_dir" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^setup_root="; then	# Test d'installation à la racine
					setup_root=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$setup_root" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^setup_nourl="; then	# Test d'installation sans accès par url
					setup_nourl=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$setup_nourl" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^setup_private="; then	# Test d'installation en privé
					setup_private=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$setup_private" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^setup_public="; then	# Test d'installation en public
					setup_public=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$setup_public" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^upgrade="; then	# Test d'upgrade
					upgrade=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$upgrade" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^backup_restore="; then	# Test de backup et restore
					backup_restore=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$backup_restore" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^multi_instance="; then	# Test d'installation multiple
					multi_instance=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$multi_instance" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^wrong_user="; then	# Test d'erreur d'utilisateur
					wrong_user=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$wrong_user" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^wrong_path="; then	# Test d'erreur de path ou de domaine
					wrong_path=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$wrong_path" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^incorrect_path="; then	# Test d'erreur de forme de path
					incorrect_path=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$incorrect_path" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^corrupt_source="; then	# Test d'erreur sur source corrompue
					corrupt_source=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$corrupt_source" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^fail_download_source="; then	# Test d'erreur de téléchargement de la source
					fail_download_source=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$fail_download_source" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^port_already_use="; then	# Test d'erreur de port
					port_already_use=$(echo "$LIGNE" | cut -d '=' -f2)
					if echo "$LIGNE" | grep -q "([0-9]*)"
					then	# Le port est mentionné ici.
						MANIFEST_PORT="$(echo "$LIGNE" | cut -d '(' -f2 | cut -d ')' -f1)"	# Récupère le numéro du port; Le numéro de port est précédé de # pour indiquer son absence du manifest.
						port_already_use=${port_already_use:0:1}	# Garde uniquement la valeur de port_already_use
					fi
					if [ "$port_already_use" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^final_path_already_use="; then	# Test sur final path déjà utilisé.
					final_path_already_use=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$final_path_already_use" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
			fi
		fi
	done 4< "$APP_CHECK/check_process"	# Utilise le descripteur de fichier 4. Car le descripteur 1 est utilisé par d'autres boucles while read dans ces scripts.
else	# Si le fichier check_process n'a pas été trouvé, fonctionne en mode dégradé.
	python "$script_dir/sub_scripts/ci/maniackc.py" "$APP_CHECK/manifest.json" > "$script_dir/manifest_extract" # Extrait les infos du manifest avec le script de Bram
	pkg_linter=1
	setup_sub_dir=1
	setup_root=1
	upgrade=1
	backup_restore=1
	multi_instance=1
	wrong_user=1
	wrong_path=1
	incorrect_path=1
	all_test=$((all_test+9))
	while read LIGNE
	do
		if echo "$LIGNE" | grep -q ":ynh.local"; then
			MANIFEST_DOMAIN=$(echo "$LIGNE" | grep ":ynh.local" | cut -d ':' -f1)	# Garde uniquement le nom de la clé.
		fi
		if echo "$LIGNE" | grep -q "path:"; then
			MANIFEST_PATH=$(echo "$LIGNE" | grep "path:" | cut -d ':' -f1)	# Garde uniquement le nom de la clé.
		fi
		if echo "$LIGNE" | grep -q "user:\|admin:"; then
			MANIFEST_USER=$(echo "$LIGNE" | grep "user:\|admin:" | cut -d ':' -f1)	# Garde uniquement le nom de la clé.
		fi
		MANIFEST_ARGS="$MANIFEST_ARGS$(echo "$LIGNE" | cut -d ':' -f1,2 | sed s/:/=/)&"	# Ajoute l'argument du manifest
	done < "$script_dir/manifest_extract"
	if [ "$MANIFEST_DOMAIN" == "null" ]
	then
		ECHO_FORMAT "La clé de manifest du domaine n'a pas été trouvée.\n" "lyellow"
		setup_sub_dir=0
		setup_root=0
		multi_instance=0
		wrong_user=0
		incorrect_path=0
		all_test=$((all_test-5))
	fi
	if [ "$MANIFEST_PATH" == "null" ]
	then
		ECHO_FORMAT "La clé de manifest du path n'a pas été trouvée.\n" "lyellow"
		setup_root=0
		multi_instance=0
		incorrect_path=0
		all_test=$((all_test-3))
	fi
	if [ "$MANIFEST_USER" == "null" ]
	then
		ECHO_FORMAT "La clé de manifest de l'user admin n'a pas été trouvée.\n" "lyellow"
		wrong_user=0
		all_test=$((all_test-1))
	fi
	if grep multi_instance "$APP_CHECK/manifest.json" | grep -q false
	then	# Retire le test multi instance si la clé du manifest est à false
		multi_instance=0
	fi
fi

TESTING_PROCESS
if [ "$no_lxc" -eq 0 ]; then
	LXC_TURNOFF
fi
TEST_RESULTS

# Mail et bot xmpp pour le niveau de l'app
if [ "$level" -eq 0 ]
then
	message="L'application $(basename "$arg_app") vient d'échouer aux tests d'intégration continue"
else
	message="L'application $(basename "$arg_app") vient d'atteindre le niveau $level"
fi

if [ -e "$script_dir/../auto_build/auto.conf" ]
then
	ci_path=$(grep "DOMAIN=" "$script_dir/../auto_build/auto.conf" | cut -d= -f2)/$(grep "CI_PATH=" "$script_dir/../auto_build/auto.conf" | cut -d= -f2)
	message="$message sur https://$ci_path"
	"$script_dir/../auto_build/xmpp_bot/xmpp_post.sh" "$message"	# Notifie sur le salon apps
fi

if [ "$level" -eq 0 ] && [ -e "$script_dir/../config" ]
then	# Si l'app est au niveau 0, et que le test tourne en CI, envoi un mail d'avertissement.
	dest=$(cat "$APP_CHECK/manifest.json" | grep '\"email\": ' | cut -d '"' -f 4)	# Utilise l'adresse du mainteneur de l'application
	ci_path=$(grep "CI_URL=" "$script_dir/../config" | cut -d= -f2)
	if [ -n "$ci_path" ]; then
		message="$message sur $ci_path"
	fi
	mail -s "[YunoHost] Échec d'installation d'une application dans le CI" "$dest" <<< "$message"	# Envoi un avertissement par mail.
fi

echo "Le log complet des installations et suppressions est disponible dans le fichier $COMPLETE_LOG"
# Clean
rm -f "$OUTPUTD" "$temp_RESULT" "$script_dir/url_output" "$script_dir/curl_print" "$script_dir/manifest_extract"

if [ -n "$APP_CHECK" ]; then
	sudo rm -rf "$APP_CHECK"
fi
sudo rm "$script_dir/pcheck.lock" # Retire le lock
