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
force_install_ok=0
script_dir=""

USER_TEST=package_checker
PASSWORD_TEST=checker_pwd
PATH_TEST=/check

PLAGE_IP=""
LXC_NAME=""
LXC_BRIDGE=""
YUNO_PWD=""
DOMAIN=""

# HELPER FUNCTIONS

file_exists() {
  local file=$1

  [[ -e $file ]]
}

is_empty() {
  local var=$1

  [[ -z $var ]]
}

_setup_user_file() {
  echo "$script_dir/sub_scripts/setup_user"
}

_process_lock_file() { 
  echo "$script_dir/pcheck.lock"
}

_package_check_repo() {
	 echo "https://github.com/YunoHost/package_check"
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
  
  # FIXME: Do we need this? Domain is updated in lcx block further below? How come?
  #
  DOMAIN=$( find_and_store_config_value "DOMAIN" "Domain to be tested" )

}

main

### REFACTORED END ###

# Récupère les informations depuis le fichier de conf (Ou le complète le cas échéant)
pcheck_config="$script_dir/config"
# Tente de lire les informations depuis le fichier de config si il existe
if [ -e "$pcheck_config" ]
then
	main_iface=$(cat "$pcheck_config" | grep iface= | cut -d '=' -f2)
fi
# Utilise des valeurs par défaut si les variables sont vides, et génère le fichier de config

if [ -z "$main_iface" ]; then
	# Tente de définir l'interface réseau principale
	main_iface=$(sudo route | grep default | awk '{print $8;}')	# Prend l'interface réseau défini par default
	if [ -z $main_iface ]; then
		echo -e "\e[91mImpossible de déterminer le nom de l'interface réseau de l'hôte.\e[0m"
		exit 1
	fi
	# Enregistre le nom de l'interface réseau de l'hôte dans un fichier de config
	echo -e "# Interface réseau principale de l'hôte\niface=$main_iface\n" >> "$pcheck_config"
fi

if [ "$no_lxc" -eq 0 ]
then
	DOMAIN=$(sudo cat /var/lib/lxc/$LXC_NAME/rootfs/etc/yunohost/current_host)
else
	DOMAIN=$(sudo yunohost domain list -l 1 | cut -d" " -f 2)
fi
SOUS_DOMAIN="sous.$DOMAIN"

if [ "$no_lxc" -eq 0 ]
then	# Si le conteneur lxc est utilisé
	lxc_ok=0
	# Vérifie la présence du virtualisateur en conteneur LXC
	if dpkg-query -W -f '${Status}' "lxc" 2>/dev/null | grep -q "ok installed"; then
		if sudo lxc-ls | grep -q "$LXC_NAME"; then	# Si lxc est installé, vérifie la présence de la machine $LXC_NAME
			lxc_ok=1
		fi
	fi
	if [ "$lxc_ok" -eq 0 ]
	then
		if [ "$build_lxc" -eq 1 ]
		then
			"$script_dir/sub_scripts/lxc_build.sh"	# Lance la construction de la machine virtualisée.
		else
			ECHO_FORMAT "Lxc n'est pas installé, ou la machine $LXC_NAME n'est pas créée.\n" "red"
			ECHO_FORMAT "Utilisez le script 'lxc_build.sh' pour installer lxc et créer la machine.\n" "red"
			ECHO_FORMAT "Ou utilisez l'argument --no-lxc\n" "red"
			sudo rm "$script_dir/pcheck.lock" # Retire le lock
			exit 1
		fi
	fi
	# Stoppe toute activité éventuelle du conteneur, en cas d'arrêt incorrect précédemment
	LXC_STOP
	LXC_TURNOFF
else	# Vérifie l'utilisateur et le domain si lxc n'est pas utilisé.
	# Vérifie l'existence de l'utilisateur de test
	echo -e "\nVérification de l'existence de l'utilisateur de test..."
	if ! ynh_user_exists "$USER_TEST"
	then	# Si il n'existe pas, il faut le créer.
		USER_TEST_CLEAN=${USER_TEST//"_"/""}
		sudo yunohost user create --firstname "$USER_TEST_CLEAN" --mail "$USER_TEST_CLEAN@$DOMAIN" --lastname "$USER_TEST_CLEAN" --password "$PASSWORD_TEST" "$USER_TEST"
		if [ "$?" -ne 0 ]; then
			ECHO_FORMAT "La création de l'utilisateur de test a échoué. Impossible de continuer.\n" "red"
			sudo rm "$script_dir/pcheck.lock" # Retire le lock
			exit 1
		fi
	fi

	# Vérifie l'existence du sous-domaine de test
	echo "Vérification de l'existence du domaine de test..."
	if [ "$(sudo yunohost domain list | grep -c "$SOUS_DOMAIN")" -eq 0 ]; then	# Si il n'existe pas, il faut le créer.
		sudo yunohost domain add "$SOUS_DOMAIN"
		if [ "$?" -ne 0 ]; then
			ECHO_FORMAT "La création du sous-domain de test a échoué. Impossible de continuer.\n" "red"
			sudo rm "$script_dir/pcheck.lock" # Retire le lock
			exit 1
		fi
	fi
fi

# Vérifie le type d'emplacement du package à tester
echo "Récupération du package à tester."
rm -rf "$script_dir"/*_check
GIT_PACKAGE=0
if echo "$arg_app" | grep -Eq "https?:\/\/"
then
	GIT_PACKAGE=1
	git clone $arg_app $gitbranch "$script_dir/$(basename "$arg_app")_check"
else
	# Si c'est un dossier local, il est copié dans le dossier du script.
	sudo cp -a --remove-destination "$arg_app" "$script_dir/$(basename "$arg_app")_check"
fi
APP_CHECK="$script_dir/$(basename "$arg_app")_check"
if [ "$no_lxc" -eq 0 ]
then	# En cas d'exécution dans LXC, l'app sera dans le home de l'user LXC.
	APP_PATH_YUNO="$(basename "$arg_app")_check"
else
	APP_PATH_YUNO="$APP_CHECK"
fi

if [ ! -d "$APP_CHECK" ]; then
	ECHO_FORMAT "Le dossier de l'application a tester est introuvable...\n" "red"
	sudo rm "$script_dir/pcheck.lock" # Retire le lock
	exit 1
fi
sudo rm -rf "$APP_CHECK/.git"	# Purge des fichiers de git

# Vérifie l'existence du fichier check_process
check_file=1
if [ ! -e "$APP_CHECK/check_process" ]; then
	ECHO_FORMAT "\nImpossible de trouver le fichier check_process pour procéder aux tests.\n" "red"
	ECHO_FORMAT "Package check va être utilisé en mode dégradé.\n" "lyellow"
	check_file=0
fi



# Cette fonctionne détermine le niveau final de l'application, en prenant en compte d'éventuels forçages
APP_LEVEL () {
	level=0 	# Initialise le niveau final à 0
	# Niveau 1: L'application ne s'installe pas ou ne fonctionne pas après installation.
	if [ "${level[1]}" == "auto" ] || [ "${level[1]}" -eq 2 ]; then
		if [ "$GLOBAL_CHECK_SETUP" -eq 1 ] && [ "$GLOBAL_CHECK_REMOVE" -eq 1 ]
		then level[1]=2 ; else level[1]=0 ; fi
	fi

	# Niveau 2: L'application s'installe et se désinstalle dans toutes les configurations communes.
	if [ "${level[2]}" == "auto" ] || [ "${level[2]}" -eq 2 ]; then
		if 	[ "$GLOBAL_CHECK_SUB_DIR" -ne -1 ] && \
			[ "$GLOBAL_CHECK_REMOVE_SUBDIR" -ne -1 ] && \
			[ "$GLOBAL_CHECK_ROOT" -ne -1 ] && \
			[ "$GLOBAL_CHECK_REMOVE_ROOT" -ne -1 ] && \
			[ "$GLOBAL_CHECK_PRIVATE" -ne -1 ] && \
			[ "$GLOBAL_CHECK_PUBLIC" -ne -1 ] && \
			[ "$GLOBAL_CHECK_MULTI_INSTANCE" -ne -1 ]
		then level[2]=2 ; else level[2]=0 ; fi
	fi

	# Niveau 3: L'application supporte l'upgrade depuis une ancienne version du package.
	if [ "${level[3]}" == "auto" ] || [ "${level[3]}" == "2" ]; then
		if [ "$GLOBAL_CHECK_UPGRADE" -eq 1 ] || ( [ "${level[3]}" == "2" ] && [ "$GLOBAL_CHECK_UPGRADE" -ne -1 ] )
		then level[3]=2 ; else level[3]=0 ; fi
	fi

	# Niveau 4: L'application prend en charge de LDAP et/ou HTTP Auth. -- Doit être vérifié manuellement

	# Niveau 5: Aucune erreur dans package_linter.
	if [ "${level[5]}" == "auto" ] || [ "${level[5]}" == "2" ]; then
		if [ "$GLOBAL_LINTER" -eq 1 ] || ( [ "${level[5]}" == "2" ] && [ "$GLOBAL_LINTER" -ne -1 ] )
		then level[5]=2 ; else level[5]=0 ; fi
	fi

	# Niveau 6: L'application peut-être sauvegardée et restaurée sans erreurs sur la même machine ou une autre.
	if [ "${level[6]}" == "auto" ] || [ "${level[6]}" == "2" ]; then
		if [ "$GLOBAL_CHECK_BACKUP" -eq 1 ] && [ "$GLOBAL_CHECK_RESTORE" -eq 1 ] || ( [ "${level[6]}" == "2" ] && [ "$GLOBAL_CHECK_BACKUP" -ne -1 ] && [ "$GLOBAL_CHECK_RESTORE" -ne -1 ] )
		then level[6]=2 ; else level[6]=0 ; fi
	fi

	# Niveau 7: Aucune erreur dans package check.
	if [ "${level[7]}" == "auto" ] || [ "${level[7]}" == "2" ]; then
		if 	[ "$GLOBAL_CHECK_SETUP" -ne -1 ] && \
			[ "$GLOBAL_CHECK_REMOVE" -ne -1 ] && \
			[ "$GLOBAL_CHECK_SUB_DIR" -ne -1 ] && \
			[ "$GLOBAL_CHECK_REMOVE_SUBDIR" -ne -1 ] && \
			[ "$GLOBAL_CHECK_REMOVE_ROOT" -ne -1 ] && \
			[ "$GLOBAL_CHECK_UPGRADE" -ne -1 ] && \
			[ "$GLOBAL_CHECK_PRIVATE" -ne -1 ] && \
			[ "$GLOBAL_CHECK_PUBLIC" -ne -1 ] && \
			[ "$GLOBAL_CHECK_MULTI_INSTANCE" -ne -1 ] && \
			[ "$GLOBAL_CHECK_ADMIN" -ne -1 ] && \
			[ "$GLOBAL_CHECK_DOMAIN" -ne -1 ] && \
			[ "$GLOBAL_CHECK_PATH" -ne -1 ] && \
			[ "$GLOBAL_CHECK_PORT" -ne -1 ] && \
			[ "$GLOBAL_CHECK_BACKUP" -ne -1 ] && \
			[ "$GLOBAL_CHECK_RESTORE" -ne -1 ] && \
			[ "${level[5]}" -ge -1 ]	# Si tout les tests sont validés. Et si le level 5 est validé ou forcé.
		then level[7]=2 ; else level[7]=0 ; fi
	fi

	# Niveau 8: L'application respecte toutes les YEP recommandées. -- Doit être vérifié manuellement

	# Niveau 9: L'application respecte toutes les YEP optionnelles. -- Doit être vérifié manuellement

	# Niveau 10: L'application est jugée parfaite. -- Doit être vérifié manuellement

	# Calcule le niveau final
	for i in {1..10}; do
		if [ "${level[i]}" == "auto" ]; then
			level[i]=0	# Si des niveaux sont encore à auto, c'est une erreur de syntaxe dans le check_process, ils sont fixé à 0.
		elif [ "${level[i]}" == "na" ]; then
			continue	# Si le niveau est "non applicable" (na), il est ignoré dans le niveau final
		elif [ "${level[i]}" -ge 1 ]; then
			level=$i	# Si le niveau est validé, il est pris en compte dans le niveau final
		else
			break		# Dans les autres cas (niveau ni validé, ni ignoré), la boucle est stoppée. Le niveau final est donc le niveau précédemment validé
		fi
	done
}

TEST_RESULTS () {
	APP_LEVEL
	ECHO_FORMAT "\n\nPackage linter: "
	if [ "$GLOBAL_LINTER" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_LINTER" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi
	ECHO_FORMAT "Installation: "
	if [ "$GLOBAL_CHECK_SETUP" -eq 1 ]; then
		ECHO_FORMAT "\t\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_SETUP" -eq -1 ]; then
		ECHO_FORMAT "\t\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Suppression: "
	if [ "$GLOBAL_CHECK_REMOVE" -eq 1 ]; then
		ECHO_FORMAT "\t\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_REMOVE" -eq -1 ]; then
		ECHO_FORMAT "\t\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Installation en sous-dossier: "
	if [ "$GLOBAL_CHECK_SUB_DIR" -eq 1 ]; then
		ECHO_FORMAT "\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_SUB_DIR" -eq -1 ]; then
		ECHO_FORMAT "\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Suppression depuis sous-dossier: "
	if [ "$GLOBAL_CHECK_REMOVE_SUBDIR" -eq 1 ]; then
		ECHO_FORMAT "\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_REMOVE_SUBDIR" -eq -1 ]; then
		ECHO_FORMAT "\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Installation à la racine: "
	if [ "$GLOBAL_CHECK_ROOT" -eq 1 ]; then
		ECHO_FORMAT "\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_ROOT" -eq -1 ]; then
		ECHO_FORMAT "\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Suppression depuis racine: "
	if [ "$GLOBAL_CHECK_REMOVE_ROOT" -eq 1 ]; then
		ECHO_FORMAT "\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_REMOVE_ROOT" -eq -1 ]; then
		ECHO_FORMAT "\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Upgrade: "
	if [ "$GLOBAL_CHECK_UPGRADE" -eq 1 ]; then
		ECHO_FORMAT "\t\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_UPGRADE" -eq -1 ]; then
		ECHO_FORMAT "\t\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Installation privée: "
	if [ "$GLOBAL_CHECK_PRIVATE" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_PRIVATE" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Installation publique: "
	if [ "$GLOBAL_CHECK_PUBLIC" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_PUBLIC" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Installation multi-instance: "
	if [ "$GLOBAL_CHECK_MULTI_INSTANCE" -eq 1 ]; then
		ECHO_FORMAT "\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_MULTI_INSTANCE" -eq -1 ]; then
		ECHO_FORMAT "\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Mauvais utilisateur: "
	if [ "$GLOBAL_CHECK_ADMIN" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_ADMIN" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Erreur de domaine: "
	if [ "$GLOBAL_CHECK_DOMAIN" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_DOMAIN" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Correction de path: "
	if [ "$GLOBAL_CHECK_PATH" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_PATH" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Port déjà utilisé: "
	if [ "$GLOBAL_CHECK_PORT" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_PORT" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

# 	ECHO_FORMAT "Source corrompue: "
# 	if [ "$GLOBAL_CHECK_CORRUPT" -eq 1 ]; then
# 		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
# 	elif [ "$GLOBAL_CHECK_CORRUPT" -eq -1 ]; then
# 		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
# 	else
# 		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
# 	fi

# 	ECHO_FORMAT "Erreur de téléchargement de la source: "
# 	if [ "$GLOBAL_CHECK_DL" -eq 1 ]; then
# 		ECHO_FORMAT "\tSUCCESS\n" "lgreen"
# 	elif [ "$GLOBAL_CHECK_DL" -eq -1 ]; then
# 		ECHO_FORMAT "\tFAIL\n" "lred"
# 	else
# 		ECHO_FORMAT "\tNot evaluated.\n" "white"
# 	fi

# 	ECHO_FORMAT "Dossier déjà utilisé: "
# 	if [ "$GLOBAL_CHECK_FINALPATH" -eq 1 ]; then
# 		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
# 	elif [ "$GLOBAL_CHECK_FINALPATH" -eq -1 ]; then
# 		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
# 	else
# 		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
# 	fi

	ECHO_FORMAT "Backup: "
	if [ "$GLOBAL_CHECK_BACKUP" -eq 1 ]; then
		ECHO_FORMAT "\t\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_BACKUP" -eq -1 ]; then
		ECHO_FORMAT "\t\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Restore: "
	if [ "$GLOBAL_CHECK_RESTORE" -eq 1 ]; then
		ECHO_FORMAT "\t\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_RESTORE" -eq -1 ]; then
		ECHO_FORMAT "\t\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\t\tNot evaluated.\n" "white"
	fi
	ECHO_FORMAT "\t\t    Notes de résultats: $note/$tnote - " "white" "bold"
	if [ "$note" -gt 0 ]
	then
		note=$(( note * 20 / tnote ))
	fi
		if [ "$note" -le 5 ]; then
			color_note="red"
			typo_note="bold"
			smiley=":'("	# La contribution à Shasha. Qui m'a forcé à ajouté les smiley sous la contrainte ;)
		elif [ "$note" -le 10 ]; then
			color_note="red"
			typo_note=""
			smiley=":("
		elif [ "$note" -le 15 ]; then
			color_note="lyellow"
			typo_note=""
			smiley=":s"
		elif [ "$note" -gt 15 ]; then
			color_note="lgreen"
			typo_note=""
			smiley=":)"
		fi
		if [ "$note" -ge 20 ]; then
			color_note="lgreen"
			typo_note="bold"
			smiley="\o/"
		fi
	ECHO_FORMAT "$note/20 $smiley\n" "$color_note" "$typo_note"
	ECHO_FORMAT "\t   Ensemble de tests effectués: $tnote/21\n\n" "white" "bold"

	# Affiche le niveau final
	ECHO_FORMAT "Niveau de l'application: $level\n" "white" "bold"
	for i in {1..10}
	do
		ECHO_FORMAT "\t   Niveau $i: "
		if [ "${level[i]}" == "na" ]; then
			ECHO_FORMAT "N/A\n"
		elif [ "${level[i]}" -ge 1 ]; then
			ECHO_FORMAT "1\n" "white" "bold"
		else
			ECHO_FORMAT "0\n"
		fi
	done
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

INIT_LEVEL() {
	level[1]="auto"		# L'application s'installe et se désinstalle correctement. -- Peut être vérifié par package_check
	level[2]="auto"		# L'application s'installe et se désinstalle dans toutes les configurations communes. -- Peut être vérifié par package_check
	level[3]="auto"		# L'application supporte l'upgrade depuis une ancienne version du package. -- Peut être vérifié par package_check
	level[4]=0			# L'application prend en charge de LDAP et/ou HTTP Auth. -- Doit être vérifié manuellement
	level[5]="auto"		# Aucune erreur dans package_linter. -- Peut être vérifié par package_check
	level[6]="auto"		# L'application peut-être sauvegardée et restaurée sans erreurs sur la même machine ou une autre. -- Peut être vérifié par package_check
	level[7]="auto"		# Aucune erreur dans package check. -- Peut être vérifié par package_check
	level[8]=0			# L'application respecte toutes les YEP recommandées. -- Doit être vérifié manuellement
	level[9]=0			# L'application respecte toutes les YEP optionnelles. -- Doit être vérifié manuellement
	level[10]=0			# L'application est jugée parfaite. -- Doit être vérifié manuellement
}

INIT_VAR
INIT_LEVEL
echo -n "" > "$COMPLETE_LOG"	# Initialise le fichier de log
echo -n "" > "$RESULT"	# Initialise le fichier des résulats d'analyse
echo -n "" | sudo tee "$script_dir/lxc_boot.log"	# Initialise le fichier de log du boot du conteneur
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
