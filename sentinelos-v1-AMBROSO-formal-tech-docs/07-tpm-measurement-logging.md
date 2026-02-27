# TPM Measurement Logging (v1)

Service: `sentinelos-tpm-log.service`

Behavior:
- Condition: `/dev/tpm0` exists
- Reads PCRs 0-7 (sha256) with `tpm2_pcrread`
- Appends to `/var/log/tpm-pcr.log`

Validation:
```bash
systemctl status sentinelos-tpm-log.service
sudo cat /var/log/tpm-pcr.log
```
