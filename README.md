# backup_and_transfer.sh

### Sender Machine Cronjob:
m h  dom mon dow   command </br>
```bash
0 */8 * * * /path/to/backup_and_transfer.sh/sender.sh    (run each 8 hours)
0 */12 * * * /path/to/backup_and_transfer.sh/cleaner.sh    (run each 12 hours)
```

### Receiver Machine Cronjob:
m h  dom mon dow   command </br>
```bash
0 */12 * * * /path/to/backup_and_transfer.sh/cleaner.sh
```
