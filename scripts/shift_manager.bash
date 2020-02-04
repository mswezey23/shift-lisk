#!/usr/bin/env bash
PATH="/usr/local/bin:/usr/bin:/bin"
version="1.0.0"

cd "$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
root_path=$(pwd)

mkdir -p $root_path/logs
logfile=$root_path/logs/shift_manager.log

set_network() {
  if [ "$(grep "7337a324ef27e1e234d1e9018cacff7d4f299a09c2df9be460543b8f7ef652f1" $SHIFT_CONFIG )" ];then
    NETWORK="main"
  elif [ "$(grep "cba57b868c8571599ad594c6607a77cad60cf0372ecde803004d87e679117c12" $SHIFT_CONFIG )" ];then
    NETWORK="test"
  else
    NETWORK="unknown"
  fi
}

SHIFT_CONFIG="config.json"
DB_URL=DATABASE_URL
DB_HOST="db"
DB_NAME="$(grep "database" $SHIFT_CONFIG | cut -f 4 -d '"' | head -1)"
DB_UNAME="$(grep "user" $SHIFT_CONFIG | cut -f 4 -d '"' | head -1)"
DB_PASSWD="$(grep "password" $SHIFT_CONFIG | cut -f 4 -d '"' | head -1)"
DB_SNAPSHOT="blockchain.db.gz"
NETWORK=""
set_network
BLOCKCHAIN_URL="https://downloads.shiftnrg.org/snapshot/$NETWORK"
GIT_BRANCH="$(git branch | sed -n '/\* /s///p')"

ntp_checks() {
    # Install NTP or Chrony for Time Management - Physical Machines only
    if [[ ! -f "/proc/user_beancounters" ]]; then
      if ! sudo pgrep -x "ntpd" > /dev/null; then
        echo -n "Installing NTP... "
        sudo apt-get install ntp -yyq &>> $logfile
        sudo service ntp stop &>> $logfile
        sudo ntpdate pool.ntp.org &>> $logfile
        sudo service ntp start &>> $logfile
        if ! sudo pgrep -x "ntpd" > /dev/null; then
          echo -e "SHIFT requires NTP running. Please check /etc/ntp.conf and correct any issues. Exiting."
          exit 1
        echo -e "done.\n"
        fi # if sudo pgrep
      fi # if [[ ! -f "/proc/user_beancounters" ]]
    elif [[ -f "/proc/user_beancounters" ]]; then
      echo -e "Running OpenVZ or LXC VM, NTP is not required, done. \n"
    fi
}

download_blockchain() {
    echo -n "Download a recent, verified snapshot? ([y]/n): "
    read downloadornot

    if [ "$downloadornot" == "y" ] || [ -z "$downloadornot" ]; then
        rm -f $DB_SNAPSHOT
        if [ -z "$BLOCKCHAIN_URL" ]; then
            BLOCKCHAIN_URL="https://downloads.shiftnrg.org/snapshot/$NETWORK"
        fi
        echo "√ Downloading $DB_SNAPSHOT from $BLOCKCHAIN_URL"
        curl --progress-bar -o $DB_SNAPSHOT "$BLOCKCHAIN_URL/$DB_SNAPSHOT"
        if [ $? != 0 ]; then
            rm -f $DB_SNAPSHOT
            echo "X Failed to download blockchain snapshot."
            exit 1
        else
            echo "√ Blockchain snapshot downloaded successfully."
        fi
    else
        echo -e "√ Using Local Snapshot."
    fi
}

restore_blockchain() {
    export PGPASSWORD=$DB_PASSWD
    echo "Restoring blockchain with $DB_SNAPSHOT"
    gunzip -fcq "$DB_SNAPSHOT" | psql -q -h $DB_HOST -U "$DB_UNAME" -d "$DB_NAME" &> /dev/null
    if [ $? != 0 ]; then
        echo "X Failed to restore blockchain."
        exit 1
    else
        echo "√ Blockchain restored successfully."
    fi
}


update_manager() {

    echo -n "Updating Shift Manager ... "
    wget -q -O shift_manager.bash https://raw.githubusercontent.com/mswezey23/shift/$GIT_BRANCH/shift_manager.bash
    echo "done."

    return 0;
}


update_client() {

    if [[ -f config.json ]]; then
        cp config.json config.json.bak
    fi

    echo -n "Updating Shift client ... "

    git checkout . &>> $logfile || { echo "Failed to checkout last status of git repository. Run it manually with: 'git checkout .'. Exiting." && exit 1; }
    git pull &>> $logfile || { echo "Failed to fetch updates from git repository. Run it manually with: git pull. Exiting." && exit 1; }
    npm install --production &>> $logfile || { echo -e "\n\nCould not install node modules. Exiting." && exit 1; }
    echo "done."

    if [[ -f $root_path/config.json.bak ]]; then
      echo -n "Take over config.json entries from previous installation ... "
      node $root_path/updateConfig.js -o $root_path/config.json.bak -n $root_path/config.json
      echo "done."
    fi

    return 0;
}

update_wallet() {

    if [[ ! -d "public" ]]; then
      install_webui
      return 0;
    fi

    echo -n "Updating Shift wallet ... "

    cd public
    git checkout . &>> $logfile || { echo "Failed to checkout last status of git repository. Exiting." && exit 1; }
    git pull &>> $logfile || { echo "Failed to fetch updates from git repository. Exiting." && exit 1; }
    npm install &>> $logfile || { echo -n "Could not install web wallet node modules. Exiting." && exit 1; }

    # Bower config seems to have the wrong permissions. Make sure we change these before trying to use bower.
    if [[ -d /home/$USER/.config ]]; then
        sudo chown -R $USER:$USER /home/$USER/.config &> /dev/null
    fi

    bower --allow-root install &>> $logfile || { echo -e "\n\nCould not install bower components for the web wallet. Exiting." && exit 1; }
    grunt release &>> $logfile || { echo -e "\n\nCould not build web wallet release. Exiting." && exit 1; }

    echo "done."
    cd ..
    return 0;
}

stop_shift() {
    echo -n "Stopping Shift... "
    forever_exists=$(whereis forever | awk {'print $2'})
    if [[ ! -z $forever_exists ]]; then
        $forever_exists stop $root_path/app.js &>> $logfile
    fi

    sleep 2

    if ! running; then
        echo "OK"
        return 0
    fi
    echo
    return 1
}

start_shift() {
    echo -n "Starting Shift Core... "
    forever_exists=$(whereis forever | awk {'print $2'})
    if [[ ! -z $forever_exists ]]; then
        forever start -o $root_path/logs/shift_console.log -e $root_path/logs/shift_err.log app.js -c "$SHIFT_CONFIG" &>> $logfile || \
        { echo -e "\nCould not start Shift." && exit 1; }
    fi

    sleep 2

    if running; then
        echo "OK"
        return 0
    fi
    echo
    return 1
}

  start_snapshot() {
    echo -n "Starting Shift (snapshot mode) ... "
    forever_exists=$(whereis forever | awk {'print $2'})
    if [[ ! -z $forever_exists ]]; then
        $forever_exists start -o $root_path/logs/snapshot_console.log -e $root_path/logs/snapshot_err.log app.js -c "$SHIFT_CONFIG" -s highest &>> $logfile || \
        { echo -e "\nCould not start Shift." && exit 1; }
    fi

    sleep 2

    if running; then
        echo "OK"
        return 0
    fi
    echo
    return 1
}

running() {
    process=$(forever list |grep app.js |awk {'print $9'})
    if [[ -z $process ]] || [[ "$process" == "STOPPED" ]]; then
        return 1
    fi
    return 0
}

show_blockHeight(){
  export PGPASSWORD=$DB_PASSWD
  blockHeight=$(psql -d $DB_NAME -U $DB_UNAME -h $DB_HOST -p 5432 -t -c "select height from blocks order by height desc limit 1")
  echo "Block height = $blockHeight"
}

parse_option() {
  OPTIND=2
  while getopts c:x opt; do
    case "$opt" in
      c)
        if [ -f "$OPTARG" ]; then
          SHIFT_CONFIG="$OPTARG"
        fi ;;
    esac
  done
}

rebuild_shift() {
  # create_database TODO: purge DB
  download_blockchain
  restore_blockchain
}

start_log() {
  echo "Starting $0... " > $logfile
  echo -n "Date: " >> $logfile
  date >> $logfile
  echo "" >> $logfile
}

case $1 in
    "update_manager")
      update_manager
    ;;
    "update_client")
      start_log
      stop_shift
      sleep 2
      update_client
      sleep 2
      start_shift
      show_blockHeight
    ;;
    "update_wallet")
      start_log
      stop_shift
      sleep 2
      update_wallet
      sleep 2
      start_shift
      show_blockHeight
    ;;
    "reload")
      stop_shift
      sleep 2
      start_shift
      show_blockHeight
      ;;
    "rebuild")
      stop_shift
      sleep 2
      rebuild_shift
      start_shift
      show_blockHeight
      ;;
    "status")
      if running; then
        echo "√ SHIFT is running."
        show_blockHeight
      else
        echo "X SHIFT is NOT running."
      fi
    ;;
    "start")
      parse_option $@
      start_shift
      # show_blockHeight
    ;;
    "snapshot")
      parse_option $@
      start_snapshot
    ;;
    "stop")
      stop_shift
    ;;

*)
    echo 'Available options: install, reload (stop/start), rebuild (official snapshot), start, stop, update_manager, update_client, update_wallet'
    echo 'Usage: ./shift_installer.bash install'
    exit 1
;;
esac
exit 0;
