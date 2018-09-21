#!/bin/bash
# sudofox/Loadstalker
# by sudofox aka aburk

# Load average threshold

THRESH=4

# If an email address is placed here, we will send an email to it with the Loadstalker info after we finish (leave as blank to disable)

EMAIL=""
# Development mode: always trigger, regardless of load average

DEVMODE=false

if [ "$DEVMODE" = true ]; then

	# Check for log directory; mkdir if needed.

	if [ ! -d /root/loadstalker_dev ]; then
    		mkdir -p /root/loadstalker_dev
	fi
	# Output file
	DIR=/root/loadstalker_dev
	FILE=loadstalker.`date +%F.%H.%M`

else

	# Check for log directory; mkdir if needed.
	if [ ! -d /root/loadstalker ]; then
	    mkdir -p /root/loadstalker
	fi

	# Output file
	FILE=loadstalker.`date +%F.%H.%M`
	DIR=/root/loadstalker
fi

COLUMNS=512

#detect system information needed to process
# TODO: Look into CloudLinux servers to make loadstalker compatible
REDHATVERSION=$(grep -Poi "release.*" /etc/redhat-release|awk '{print int($2)}');

# Test if cPanel is installed

if [ -n "$(/usr/local/cpanel/cpanel -V 2>/dev/null)" ]; then
        PANELTYPE="cPanel"
elif [ -n "$(/usr/sbin/plesk -v 2>/dev/null)" ]; then
        PANELTYPE="Plesk"
else
	PANELTYPE="none"
fi



LOAD=`awk '{print int($1)}' /proc/loadavg`
echo `date +%F.%X` - Load: $LOAD >> $DIR/checklog


# As the systems differ greatly depending on the panel type, we'll split it up by the entire check rather than checking if cPanel, Plesk or other ('none') each time



# We can get rid of this huge if then condition by simply inversing what we test for.
#if [ $LOAD -ge $THRESH ] || $DEVMODE

if [ $LOAD -lt $THRESH ] && ! $DEVMODE; then
	exit;
fi

# Run loadstalker

# Function defs

do_disk () {
	printf "\n=== Disk ===\n\n"
	df -h --output
}

do_exim () { # cPanel Only
	printf "\n=== Exim ===\n\n"
	exiwhat
	printf "\nExim Queue size: $(exim -bpc)\n" 
}

do_swap_check () {

	SWAPCHECK=`swapon -s|wc -c`
	printf "\n=== Top Swap Users ===\n"
	if [ $SWAPCHECK -gt 0 ]; then
		echo "$(echo Process Swap; for file in /proc/*/status; do awk '/Name|VmSwap/ {printf $2 " " $3}END {print ""}' $file; done|sort -k2 -nr|head -n20|awk '{print $1 " " int($2/1024) "MB"}')"|column -t|grep -v 0MB
		echo Total: $(free -m|awk '$1=="Swap:"{print $3 "MB"}')
	else
		echo "Swap is disabled."
	fi
}

do_top_cpu () {

	printf "\n=== Top CPU Users ===\n"
	echo "$TOP_SBN1"|head -n26|tail -n20|awk '$9 !~/0.0/'
}

do_mysql () {

	printf "\n=== MySQL Info ===\n"

	if [ "$PANELTYPE" == "Plesk" ]; then
		mysqladmin -uadmin -p$(cat /etc/psa/.psa.shadow) stat|awk -F"  " '{for (i=1;i<NF;i=i+1) print $i}'|column -t -s":"
		mysqladmin -uadmin -p$(cat /etc/psa/.psa.shadow) proc
	elif [ "$PANELTYPE" == "cPanel" ] || [ "$PANELTYPE" == "none" ]; then
		mysqladmin stat|awk -F"  " '{for (i=1;i<NF;i=i+1) print $i}'|column -t -s":"
		mysqladmin proc
	fi
}

do_resmem () {

	printf "=== Processes with highest resident memory usage ===\n\nRSS\tVSZ\tPID\tCMD\n"
	ps h -Ao rss,vsz,pid,cmd |sort -rn|head -n20|awk '{print int($1/1000)"M\t"int($2/1000)"M\t"$3"\t"$4}'
	printf "\nTotal resident memory usage: "
	ps h -Ao rsz,vsz,cmd | sort -rn | awk '{total = total + $1 }END{print int(total/1000) "M"}'
}

do_system_info () {

	printf "= System Information =\n\n"
	printf "Hostname:|$(hostname)
OS Version:|$(cat /etc/redhat-release)
Kernel:|$(uname -r)
CPU:|$CPUCORES core(s), $CPUMODEL
RAM:|$INSTALLEDRAM MB"|column -t -s'|' 

}

do_full_proclist () {
	printf "\nFull Process list (ps auxf) \n"
	echo "$PS_FAUX"
}

do_list_apacheconns () {

        for port in $APACHEPORTS; do

                printf "\n=== Top open connections to port $port ===\n"
                lsof -nP -i:$port|grep ESTABLISHED|awk -F "->" '{print $2}'|awk -F: '{print $1}'|sort|egrep -v "^$"|uniq -c|sort -nr|head
        done

}
populate_vars () {

	# System information...

	# HOSTNAME	|	Server's hostname		|	string
	# KERNELRELEASE	|	uname -r			|	string

	# Amount/Number of..
	# NUMHTTPD	|	Number of httpd procs		|	integer
	# NUMNGINX	|	Number of nginx worker procs	|	integer
	# CPUCORES	|	Number of CPU cores		|	integer
	# INSTALLEDRAM	|	Amount of installed RAM in MB	|	integer
	# NUMPHP	|	Number of php procs		|	integer

	# CPU usage...
	# HTTPDCPU	|	CPU usage of HTTPD (%)		|	double, will be displayed with a percent sign later
	# MYSQLCPU	|	CPU usage of MySQLd (%) 	|	double, will be displayed with a percent sign later
	# PHPCPU	|	CPU usage of PHP (%)		|	double, will be displayed with a percent sign later

	# Memory usage...
	# HTTPDMEM	|	HTTP res. mem usage (kb)	|	integer, will be displayed as int(value/1000) MB later
	# PHPMEM	|       PHP res. mem usage (kb)		|       integer, will be displayed as int(value/1000) MB later
	# MYSQLMEM	|	MySQL res. mem usage (kb)	|	integer, will be displayed as int(value/1000) MB later


	PS_FAUX=`ps faux`
	PS_AUX=`ps aux`
	TOP_SBN1=`top -Sbn1`

	NUMHTTPD=`echo "$PS_AUX"|grep '[h]ttpd'|wc -l`

	CPUCORES=`grep -c processor /proc/cpuinfo`
	INSTALLEDRAM=`free -m|awk '$1=="Mem:" {print int($2)}'`
	CPUMODEL=`awk -F": " '/model name/{if(!seen[$2]++)print$2}' /proc/cpuinfo`

	HTTPDCPU=`echo "$TOP_SBN1"|awk '$12 == "httpd" {cpu+=$9}END{printf"%.2f",cpu}'`
	MYSQLCPU=`echo "$TOP_SBN1"|awk '$12~/mysqld/ {cpu+=$9}END{printf"%.2f",cpu}'`

	HTTPDMEM=`echo "$PS_AUX"|awk '$11~/[h]ttpd$/ {sum+=$6} END {print int(sum)}'`
	MYSQLMEM=`echo "$PS_AUX"|awk '$11~/[m]ysqld$/ {sum+=$6} END {print int(sum)}'`

# these may change between cPanel and Plesk (especially PHP binary names...)

# TODO: Updated Plesk PHP binary names to not include things that only cPanel has like lsphp, etc

if [ "$PANELTYPE" == "cPanel" ]; then

	NUMPHP=`echo "$PS_AUX"|awk '$11~/(ls|)[p]hp+(-cgi|5|)$/'|wc -l`
	PHPCPU=`echo "$TOP_SBN1"|awk '$12~/(ls|)[p]hp+(-cgi|5|$)/ {cpu+=$9}END{printf"%.2f",cpu}'`
	PHPMEM=`echo "$PS_AUX"|awk '$11~/(ls|)[p]hp+(-cgi|5|)$/ {sum+=$6} END {print int(sum)}'`

	APACHEPORTS=$(awk -F: '/^([[:space:]]{1,}|)Listen [0-9]/ {print int($2)}' /etc/httpd/conf/httpd.conf|sort|uniq)

elif [ "$PANELTYPE" == "Plesk" ]; then

	NUMNGINX=`echo "$PS_AUX"|grep '[n]ginx: worker process'|wc -l`
	NUMPHP=`echo "$PS_AUX"|awk '$11~/(ls|)[p]hp+(-cgi|5|)$/'|wc -l`
	PHPCPU=`echo "$TOP_SBN1"|awk '$12~/(ls|)[p]hp+(-cgi|5|$)/ {cpu+=$9}END{printf"%.2f",cpu}'`

	PHPMEM=`echo "$PS_AUX"|awk '$11~/(ls|)[p]hp+(-cgi|5|)$/ {sum+=$6} END {print int(sum)}'`

	# TODO: Create APACHEPORTS regex that works for both "Listen <port>" and "Listen <interface>:<port>" so this can be the same as the one for cPanel.
	# plesk has the SSL 'Listen' directive in conf.d/ssl.conf
	APACHEPORTS=$(awk '/^([[:space:]]{1,}|)Listen [0-9]/ {print int($2)}' /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/*.conf |sort|uniq)

fi

}

echo loadstalker tripped, dumping info to $DIR/$FILE >> $DIR/checklog
echo `date +%F.%H.%M` > $DIR/$FILE
chmod 600 $DIR/$FILE

	############## If cPanel ##############


if [ "$PANELTYPE" == "cPanel" ]; then
	if [ -e "/etc/cpanel/ea4/is_ea4" ]; then
		IS_EA4=true;
	else
		IS_EA4=false;
	fi

	#summary

	printf "===== System Summary =====\n\n" >> $DIR/$FILE
	printf "Time:\n$HOSTNAME:\t$(date)\nAmerica/Detroit:\t$(TZ='America/Detroit' date)\n" >> $DIR/$FILE

	populate_vars

	do_system_info >> $DIR/$FILE

	echo >> $DIR/$FILE #blank line
	w >> $DIR/$FILE
	echo >> $DIR/$FILE #blank line
	printf "= Apache and PHP = \n\n" >> $DIR/$FILE
printf "Apache Processes:|$NUMHTTPD
Apache CPU Usage:|$HTTPDCPU%%
Apache Memory Usage:|$(awk -v ram="$HTTPDMEM" 'BEGIN{print int(ram/1000)"M"}')"|column -t -s'|' >> $DIR/$FILE

	# PHP Processes
	if  $IS_EA4 ; then
		# EA4 - Breaks down by version
		printf "EasyApache version: 4\n\n" >> $DIR/$FILE
		printf "PHP Versions: \n" >> $DIR/$FILE
		printf "Version \tHandler\n" >> $DIR/$FILE

		for version in $(whmapi1 php_get_installed_versions |awk '$1=="-"{print$2}'); do
		printf "$version\t"; whmapi1 php_get_handlers version=$version |awk '$1=="current_handler:"{print$2}';done >> $DIR/$FILE

		printf "\nNumber of PHP Processes: $NUMPHP\n" >> $DIR/$FILE
		if [ $NUMPHP -gt 0 ]; then
			printf "\n# User Version\n$(echo "$PS_AUX"|awk '$11~/\/opt\/cpanel\/ea-php/ {cmd="sort|uniq -c|sort -n"; split($11,path,"/"); print $1 " " path[4]|cmd}')"|sort -r |column -t >> $DIR/$FILE
#			printf "#\tVersion\t\n" >> $DIR/$FILE
#			echo "$PS_AUX"|awk '$11~/\/opt\/cpanel\/ea-php/ {cmd="sort|uniq -c|sort -n"; split($11,path,"/"); print path[4]|cmd}'|awk '{print $1 "\t"$2}' >> $DIR/$FILE
			echo >> $DIR/$FILE
		fi

		printf "PHP CPU Usage: $PHPCPU%%\n" >> $DIR/$FILE
	else
		# EA3
                printf "EasyApache version: 3\n" >> $DIR/$FILE
		printf "Installed PHP Version: \n" >> $DIR/$FILE
		echo $(cat /usr/local/apache/conf/php.version ; awk '/php5/ {print "\t"$2}' /usr/local/apache/conf/php.conf.yaml) >> $DIR/$FILE
		printf "Number of PHP Processes: $NUMPHP\n" >> $DIR/$FILE
		printf "\n# User Process\n$(echo "$PS_AUX"|grep -v "/usr/local/cpanel/3rdparty"| awk '$11~/(ls|)[p]hp+(-cgi|5|)$/ {split($11,path,"/"); print $1 " " path[length(path)]}'|uniq -c|sort -r -k1,1)"|column -t >> $DIR/$FILE
		printf "\nPHP CPU Usage: $PHPCPU%%\n" >> $DIR/$FILE
	fi

        echo $PHPMEM|awk '{print "PHP Memory Usage: " int($1/1000) " MB"}' >> $DIR/$FILE

        echo >> $DIR/$FILE #blank line

	do_resmem >> $DIR/$FILE

	do_swap_check >> $DIR/$FILE

	do_top_cpu >> $DIR/$FILE

	do_mysql >> $DIR/$FILE

	printf "\n=== Apache Info ===\n" >> $DIR/$FILE

	# The method of obtaining the server status page varies depending on OS version, Apache version, cPanel/Plesk version, etc
	# Also, we won't be printing information about requests that have already finished - this will cause confusion
	# Machine readable mod_status output for easier parsing: http://127.0.0.1/whm-server-status?auto or /server-status?auto
	# TODO: Add cPanel on CentOS 5 compatibility

	if [ -d /var/cpanel ]; then
		SERVERSTATUS=$(lynx -dump -width 500 http://127.0.0.1/whm-server-status);
		BARESTATUS=$(curl -s http://127.0.0.1/whm-server-status?auto);
		echo >> $DIR/$FILE #empty line

		APACHEINFO=$(echo "$BARESTATUS" |awk -F": " '$1~/^(ServerVersion|ServerMPM|Server\ Built|CurrentTime|RestartTime|ServerUptime|Total\ Accesses|Total\ kBytes|ReqPerSec|BusyWorkers|IdleWorkers)$/ {print $1"|"$2}'|column -t -s"|")
		echo "$APACHEINFO" >> $DIR/$FILE
		printf "NOTE: ReqPerSec = (Total Accesses/ServerUptime), not a real-time statistic\n" >> $DIR/$FILE
		printf "NOTE: BusyWorkers = Requests currently being processed\n\n" >> $DIR/$FILE

		echo "Apache Scoreboard:" >> $DIR/$FILE
		echo >> $DIR/$FILE #empty line
		echo "$BARESTATUS" | awk '$1=="Scoreboard:" {print $2}'|fold -w50 >> $DIR/$FILE

		printf '

Scoreboard Key:
   "_" Waiting for Connection, "S" Starting up, "R" Reading Request,
   "W" Sending Reply, "K" Keepalive (read), "D" DNS Lookup,
   "C" Closing connection, "L" Logging, "G" Gracefully finishing,
   "I" Idle cleanup of worker, "." Open slot with no current process

' >> $DIR/$FILE


		# this shows active requests
		echo "Requests:" >> $DIR/$FILE
		echo "$SERVERSTATUS"|awk '(($12 ~ /http|Protocol/) && ($4 !~/_|\./))'|column -t >> $DIR/$FILE

	else
		# TODO: Expand this:
		SERVERSTATUS=$(httpd fullstatus);

	fi

	do_list_apacheconns >> $DIR/$FILE

	do_disk >> $DIR/$FILE

	# exim, last since this can sometimes take really long to return

	do_exim >> $DIR/$FILE

	do_full_proclist >> $DIR/$FILE

	################### If Plesk ###################
	elif [ "$PANELTYPE" == "Plesk" ]; then

		#summary
		printf "===== System Summary =====\n\n" >> $DIR/$FILE
		printf "Time:\n$HOSTNAME:\t$(date)\nAmerica/Detroit:\t$(TZ='America/Detroit' date)\n" >> $HOST/$FILE

	populate_vars

	do_system_info >> $DIR/$FILE

	echo >> $DIR/$FILE #blank line
	w >> $DIR/$FILE
	echo >> $DIR/$FILE #blank line

# TODO: Add useful NGINX statistics and metrics -- our kicks need nginx configured with stub_status enabled first though
	printf "= Apache, PHP, and NGINX = \n\n" >> $DIR/$FILE
printf "Apache Processes:|$NUMHTTPD
NGINX worker processes:|$NUMNGINX
Apache CPU Usage:|$HTTPDCPU%%
Apache Memory Usage:|$(awk -v ram="$HTTPDMEM" 'BEGIN{print int(ram/1000)"M"}')"|column -t -s'|' >> $DIR/$FILE


# Plesk does not have Apache server status configured by default

        echo >> $DIR/$FILE #blank line

	do_resmem >> $DIR/$FILE

	do_swap_check >> $DIR/$FILE

	do_top_cpu >> $DIR/$FILE

	do_mysql >> $DIR/$FILE

	printf "\n=== Apache Info ===\n" >> $DIR/$FILE

	# The method of obtaining the server status page varies depending on OS version, Apache version, cPanel/Plesk version, etc
	# Also, we won't be printing information about requests that have already finished - this will cause confusion
	# Machine readable mod_status output for easier parsing: http://127.0.0.1/whm-server-status?auto or /server-status?auto
	# TODO: Add cPanel on CentOS 5 compatibility

	if [ true ]; then #TODO: Use this to check if mod_status is enabled
		SERVERSTATUS=$(lynx -dump -width 500 http://127.0.0.1/server-status);
		BARESTATUS=$(curl -s http://127.0.0.1/server-status?auto);
		echo >> $DIR/$FILE #empty line

		APACHEINFO=$(echo "$BARESTATUS" |awk -F": " '$1~/^(ServerVersion|ServerMPM|Server\ Built|CurrentTime|RestartTime|ServerUptime|Total\ Accesses|Total\ kBytes|ReqPerSec|BusyWorkers|IdleWorkers)$/ {print $1"|"$2}'|column -t -s"|")
		echo "$APACHEINFO" >> $DIR/$FILE
		printf "NOTE: ReqPerSec = (Total Accesses/ServerUptime), not a real-time statistic\n" >> $DIR/$FILE
		printf "NOTE: BusyWorkers = Requests currently being processed\n\n" >> $DIR/$FILE

		echo "Apache Scoreboard:" >> $DIR/$FILE
		echo >> $DIR/$FILE #empty line
		echo "$BARESTATUS" | awk '$1=="Scoreboard:" {print $2}'|fold -w50 >> $DIR/$FILE

		printf '

Scoreboard Key:
   "_" Waiting for Connection, "S" Starting up, "R" Reading Request,
   "W" Sending Reply, "K" Keepalive (read), "D" DNS Lookup,
   "C" Closing connection, "L" Logging, "G" Gracefully finishing,
   "I" Idle cleanup of worker, "." Open slot with no current process

' >> $DIR/$FILE


		# this shows active requests
		echo "Requests:" >> $DIR/$FILE
		echo "$SERVERSTATUS"|awk '(($13 ~ /GET|POST|HEAD|OPTIONS|Request/) && ($4 !~/_|\./))'| column -t >> $DIR/$FILE # Works with Plesk mod_status

	else
		# TODO: Expand this:
		SERVERSTATUS=$(httpd fullstatus);

	fi

	do_list_apacheconns >> $DIR/$FILE

	do_disk >> $DIR/$FILE

	do_full_proclist >> $DIR/$FILE


	fi

# Email Notification
# If EMAIL is not an empty string, then send an email to the listed address.

if [[ ! -z $EMAIL ]]; then
	SUBJECT="Loadstalker on $(hostname) -  $(uptime|grep -Po "load.+?(?=,)")"
        /usr/bin/env mail -s "$SUBJECT" "$EMAIL" < $DIR/$FILE
fi

