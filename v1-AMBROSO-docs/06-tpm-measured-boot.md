# TPM Measurement Logging (v1)

v1 includes a simple systemd oneshot service:
- `sentinelos-tpm-log.service`

Behavior:
- Runs at boot (multi-user target)
- If `/dev/tpm0` exists and `tpm2_pcrread` exists, it appends PCR values (0-7, sha256) to:
  - `/var/log/tpm-pcr.log`

Verify:
```bash
systemctl status sentinelos-tpm-log.service
sudo cat /var/log/tpm-pcr.log
```
