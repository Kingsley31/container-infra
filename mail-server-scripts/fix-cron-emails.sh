#!/bin/bash
# Auto-configure cron to stop email spam and enable proper logging
# Usage: sudo ./fix-cron-emails.sh

set -euo pipefail

# Check if running as root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔧 Configuring cron to stop email spam and enable logging...${NC}"

# Backup original crontab
echo -e "${YELLOW}📦 Creating backup of /etc/crontab...${NC}"
if [[ ! -f /etc/crontab.backup ]]; then
    cp /etc/crontab /etc/crontab.backup
    echo -e "${GREEN}✅ Backup created: /etc/crontab.backup${NC}"
else
    echo -e "${YELLOW}⚠️  Backup already exists, skipping...${NC}"
fi

# 1. Modify crontab to redirect output to log files
echo -e "${YELLOW}📝 Updating /etc/crontab to redirect output to log files...${NC}"

# Create temporary crontab file
TEMP_CRON=$(mktemp)

# Process the crontab file
sed -E '
# Fix daily cron
s|^(25 6    \* \* \*   root    test -x /usr/sbin/anacron \|\| { cd / && run-parts --report /etc/cron.daily; })$|\1 >> /var/log/cron-daily.log 2>\&1|

# Fix weekly cron (handle cut off line)
s|^(47 6    \* \* 7   root    test -x /usr/sbin/anacron \|\| { cd / && run-parts --report /etc/cron.weekly;>)$|\1 >> /var/log/cron-weekly.log 2>\&1|
s|^(47 6    \* \* 7   root    test -x /usr/sbin/anacron \|\| { cd / && run-parts --report /etc/cron.weekly; })$|\1 >> /var/log/cron-weekly.log 2>\&1|

# Fix monthly cron (handle cut off line)  
s|^(52 6    1 \* \*   root    test -x /usr/sbin/anacron \|\| { cd / && run-parts --report /etc/cron.monthly;>)$|\1 >> /var/log/cron-monthly.log 2>\&1|
s|^(52 6    1 \* \*   root    test -x /usr/sbin/anacron \|\| { cd / && run-parts --report /etc/cron.monthly; })$|\1 >> /var/log/cron-monthly.log 2>\&1|
' /etc/crontab > "$TEMP_CRON"

# Replace the original crontab
mv "$TEMP_CRON" /etc/crontab
echo -e "${GREEN}✅ Crontab updated successfully${NC}"

# 2. Create log files with proper permissions
echo -e "${YELLOW}📁 Creating log files...${NC}"
for logfile in cron-daily cron-weekly cron-monthly; do
    if [[ ! -f "/var/log/${logfile}.log" ]]; then
        touch "/var/log/${logfile}.log"
        chmod 640 "/var/log/${logfile}.log"
        chown root:adm "/var/log/${logfile}.log"
        echo -e "${GREEN}✅ Created /var/log/${logfile}.log${NC}"
    else
        echo -e "${YELLOW}⚠️  /var/log/${logfile}.log already exists, ensuring permissions...${NC}"
        chmod 640 "/var/log/${logfile}.log"
        chown root:adm "/var/log/${logfile}.log"
    fi
done

# 3. Create logrotate configuration
echo -e "${YELLOW}🔄 Creating logrotate configuration...${NC}"
cat > /etc/logrotate.d/cron-logs << 'EOF'
/var/log/cron-*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 root adm
}
EOF

echo -e "${GREEN}✅ Logrotate config created: /etc/logrotate.d/cron-logs${NC}"

# 4. Test logrotate configuration
echo -e "${YELLOW}🧪 Testing logrotate configuration...${NC}"
if logrotate -d /etc/logrotate.d/cron-logs > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Logrotate configuration is valid${NC}"
else
    echo -e "${RED}❌ Logrotate configuration test failed${NC}"
    echo "Checking for errors:"
    logrotate -d /etc/logrotate.d/cron-logs
fi

# 5. Verify the changes
echo -e "${YELLOW}🔍 Verifying changes...${NC}"
echo -e "${GREEN}=== Modified crontab entries ==="
grep -E "(cron.daily|cron.weekly|cron.monthly)" /etc/crontab

echo -e "\n${GREEN}=== Log files ==="
ls -la /var/log/cron-*.log

echo -e "\n${GREEN}=== Logrotate config ==="
cat /etc/logrotate.d/cron-logs

# 6. Optional: Install anacron
read -p "Do you want to install anacron for better missed job handling? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}📦 Installing anacron...${NC}"
    if apt update && apt install -y anacron; then
        echo -e "${GREEN}✅ Anacron installed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to install anacron${NC}"
    fi
fi

echo -e "\n${GREEN}🎉 Configuration complete!${NC}"
echo -e "${YELLOW}📋 Summary of changes:${NC}"
echo "1. ✅ Crontab modified to redirect output to log files"
echo "2. ✅ Log files created with proper permissions"
echo "3. ✅ Logrotate configuration set up"
echo "4. ✅ Backup created at /etc/crontab.backup"
echo ""
echo -e "${YELLOW}📝 Next cron runs will log to:${NC}"
echo "Daily:   /var/log/cron-daily.log"
echo "Weekly:  /var/log/cron-weekly.log"
echo "Monthly: /var/log/cron-monthly.log"
echo ""
echo -e "${YELLOW}🔧 To check logs:${NC}"
echo "sudo tail -f /var/log/cron-daily.log"
echo ""
echo -e "${YELLOW}⏰ Next daily cron run: 06:25 UTC${NC}"

# Cleanup
rm -f "$TEMP_CRON" 2>/dev/null || true