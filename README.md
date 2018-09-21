# sudofox/Loadstalker
_by sudofox aka aburk_

Loadstalker is an information collecting utility for troubleshooting overloaded servers. Put it on a cron, pick your threshold, and call it a day - it's tailored for both cPanel and Plesk. It's non-invasive and can be added or removed easily as needed.

A little configuration is necessary when first setting it up.

### THRESH
The threshold for running is based upon load average - that is the THRESH variable at the top of the file. By default the threshold is for a load average of 4.

### EMAIL
If you want to receive email notifications, add your email address into the EMAIL variable at the top.

### ENTRIES
If you want to adjust how many entries you get per section, you can adjust the ENTRIES variable.

### DEVMODE
See "Dev Mode" below.

## Adding to crontab

If you want to run every 3 minutes, do this:

```
*/3 * * * * /path/to/Loadstalker.sh
```

Consider putting it in /root/bin as follows:

```
/root/bin/Loadstalker.sh
```

Make sure you give it the correct permissions:

```
chmod +x Loadstalker.sh
```

If you want to remove it, it's easy!

```
# rm /path/to/Loadstalker.sh # remove the script
# crontab -e # remove the cronjob
# rm -rf /root/loadstalker # remove the logs folder
```

## Dev mode:

### With dev mode off (normal):  

Loadstalker will put its logs in /root/loadstalker and only do so when it's triggered via cron and the load average is above the configured value (THRESH, near the top of the script).

### With dev mode on:

Loadstalker will put its logs in /root/loadstalker_dev and do so every time it's run, regardless of load average.

