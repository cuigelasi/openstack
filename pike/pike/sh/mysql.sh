#!/bin/bash
/usr/bin/expect <<EOF
spawn mysql_secure_installation
expect "Enter current password for root (enter for none):" {
send "\r";exp_continue
} "Set root password?" {
send "y\r";exp_continue
} "New password:" {
send "$DB_PASS\r";exp_continue
} "Re-enter new password:" {
send "$DB_PASS\r";exp_continue
} "Remove anonymous users?" {
send "y\r";exp_continue
} "Disallow root login remotely?" {
send "n\r";exp_continue
} "Remove test database and access to it?" {
send "y\r";exp_continue
} "Reload privilege tables now?" {
send "y\r";exp_continue
}
EOF

