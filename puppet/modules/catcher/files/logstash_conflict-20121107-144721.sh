#! /bin/sh
#
#	/etc/rc.d/init.d/logstash
#
#	Starts Logstash as a daemon
#
# chkconfig: 2345 20 80
# description: Starts Logstash as a daemon
# pidfile: /var/run/logstash-agent.pid

### BEGIN INIT INFO
# Provides: logstash
# Required-Start: $local_fs $remote_fs
# Required-Stop: $local_fs $remote_fs
# Default-Start: 2 3 4 5
# Default-Stop: S 0 1 6
# Short-Description: Logstash
# Description: Starts Logstash as a daemon.
# Author: christian.paredes@sbri.org, modified by https://github.com/paul-at

### END INIT INFO

# Amount of memory for Java
JAVAMinMem=256M
JAVAMaxMem=1024M

# Location of logstash files
LOCATION=/opt/logstash

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
DESC="Logstash Daemon"
NAME=java
DAEMON=`which java`
CONFIG_DIR=/etc/logstash.conf
LOGFILE="/var/log/logstash.log"
PATTERNSPATH="/opt/logstash/patterns"
PLUGINSPATH="/opt/logstash/plugins"
JARNAME=logstash-monolithic.jar
ARGS="-Xmx$JAVAMaxMem -Xms$JAVAMinMem -jar ${JARNAME} agent --config ${CONFIG_DIR} --log ${LOGFILE} --grok-patterns-path ${PATTERNSPATH} --pluginpath ${PLUGINSPATH}"
SCRIPTNAME=/etc/init.d/logstash
PID_FILE="/var/run/logstash-agent.pid"
base=logstash

# Exit if the package is not installed
if [ ! -x "$DAEMON" ]; then
{
  echo "Couldn't find $DAEMON"
  exit 99
}
fi

. /etc/init.d/functions

#
# Function that starts the daemon/service
#

find_logstash_process () {
    if [ -f $PID_FILE ]; then
	PID=`cat $PID_FILE`
    else
    	PIDTEMP=`ps ux | grep logstash | grep java | grep agent | awk '{ print $2 }'`
    	# Pid not found
    	if [ "x$PIDTEMP" = "x" ]; then
    	    PID=-1
    	else
     	   PID=$PIDTEMP
	   echo "Warning: no PID file found, replacing"
	   # Recompose PID file, not sure if there's a better way of handling this
	   echo $PID > $PID_FILE
    	fi
    fi
}

do_start()
{
  cd $LOCATION && \
  ($DAEMON $ARGS &) \
  && success || failure
  PID=`ps auxww | grep 'logstash.*monolithic' | grep java | awk '{print $2}'`
    if [ "x$PID" = "x" ]; then
	PID=-1
    fi

    if [ $PID -eq -1 ]; then
	echo "Logstash failed to start."
	exit 1
    else
	echo $PID > $PID_FILE
	echo "Started successfully, PID $PID"
	touch /var/lock/subsys/$JARNAME
	exit 0
    fi
}

#
# Function that stops the daemon/service
#
do_stop()
{
  pid=`ps auxww | grep 'logstash.*monolithic' | grep java | awk '{print $2}'`
                       if checkpid $pid 2>&1; then
                           # TERM first, then KILL if not dead
                           kill -TERM $pid >/dev/null 2>&1
                           usleep 100000
                           if checkpid $pid && sleep 1 &&
                              checkpid $pid && sleep $delay &&
                              checkpid $pid ; then
                                kill -KILL $pid >/dev/null 2>&1
                                usleep 100000
                           fi
                        fi
                        checkpid $pid
                        RC=$?
                        [ "$RC" -eq 0 ] && failure $"$base shutdown" || success $"$base shutdown"

}

case "$1" in
  start)
    echo -n "Starting $DESC: "
    do_start
    touch /var/lock/subsys/$JARNAME
    ;;
  stop)
    echo -n "Stopping $DESC: "
    do_stop
    rm /var/lock/subsys/$JARNAME
    ;;
  restart|reload)
    echo -n "Restarting $DESC: "
    do_stop
    do_start
    ;;
  status)
     find_logstash_process
	if [ $PID -gt 0 ]; then
	    if [ -d /proc/$PID ]; then
		echo "Running, PID $PID"
            	exit 0
	    else
		echo "Found PID file, but process does not exist.  Removing stale PID."
		rm -f $PID_FILE
	    fi
        else
	    echo "Not running."
            exit 1
	fi 
        ;;
  *)
    echo "Usage: $SCRIPTNAME {start|stop|status|restart}" >&2
    exit 3
    ;;
esac

echo
exit 0