# Redirect Cron Output to Log Files

1. Edit the crontab to stop email spam:
   sudo nano /etc/crontab
2. Modify the cron.daily line to redirect output:
   Change this line:

   ```bash
   25 6    * * *   root    test -x /usr/sbin/anacron || { cd / && run-parts --report /etc/cron.daily; }
   ```

   To this:

   ```bash
   25 6    * * *   root    test -x /usr/sbin/anacron || { cd / && run-parts --report /etc/cron.daily; } >> /var/log/cron-daily.log 2>&1
   ```

3. While you're there, fix the other cron lines too:
   The weekly and monthly lines seem to be cut off. Fix them:

   ```bash
   47 6    * * 7   root    test -x /usr/sbin/anacron || { cd / && run-parts --report /etc/cron.weekly; } >> /var/log/cron-weekly.log 2>&1

   52 6    1 * *   root    test -x /usr/sbin/anacron || { cd / && run-parts --report /etc/cron.monthly; } >> /var/log/cron-monthly.log 2>&1

   ```

4. Create the log files with proper permissions:

   ```bash
    sudo touch /var/log/cron-daily.log /var/log/cron-weekly.log /var/log/cron-monthly.log
    sudo chmod 640 /var/log/cron-*.log
    sudo chown root:adm /var/log/cron-*.log
   ```

5. Set up log rotation for these new log files:

    ```bash
        sudo nano /etc/logrotate.d/cron-logs
    ```

    Add this content:

    ```bash
        /var/log/cron-*.log {
            daily
            missingok
            rotate 7
            compress
            delaycompress
            notifempty
            create 640 root adm
        }
    ```

6. Verify the changes:

   ```bash
    sudo cat /etc/crontab
    sudo ls -la /var/log/cron-*.log
   ```
