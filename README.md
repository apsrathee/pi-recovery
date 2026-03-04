\# Pi Infrastructure Recovery



\## Disaster Recovery Steps



1\. Flash Raspberry Pi OS

2\. Create user `piadmin`

3\. SSH into Pi

4\. Run:



curl -O https://raw.githubusercontent.com/apsrathee/pi-recovery/main/restore.sh

chmod +x restore.sh

bash restore.sh



5\. Configure rclone (gcrypt remote)

6\. Enter encryption password

7\. Wait for restore to complete

