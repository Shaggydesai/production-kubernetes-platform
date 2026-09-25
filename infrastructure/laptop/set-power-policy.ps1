<#
.SYNOPSIS
  Host power policy for the VMware lab. Run as Administrator.

.DESCRIPTION
  On 2026-09-24 the host entered S3 sleep at 23:41 with all three cluster VMs
  running. Ten hours later it resumed; VMware could not complete the guests'
  pending disk I/O, so the guests saw hard SCSI errors, ext4 aborted its
  journals and remounted the Longhorn volumes read-only, and the emulated NIC
  on the control plane wedged. Recovery took two hours.

  See docs/incidents/2026-09-25-host-sleep.md

  These settings stop the host sleeping. They do NOT replace the rule:
  shut the VMs down before closing the lid. Disabling sleep protects you from
  forgetting; it is not a substitute for the staged shutdown in
  docs/runbooks/lab-startup-shutdown.md

  Trade-off: on battery the laptop will now stay awake and drain.
#>

#Requires -RunAsAdministrator

# never sleep or hibernate, on AC or battery
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0

# screen may still blank - that does not suspend the machine
powercfg /change monitor-timeout-ac 15

# closing the lid does nothing (0 = No action)
$SUB_BUTTONS = '4f971e89-eebd-4455-a8de-9e59040e7347'
$LIDACTION   = '5ca83367-6e45-459f-a27b-476b1d01c936'
powercfg /setacvalueindex SCHEME_CURRENT $SUB_BUTTONS $LIDACTION 0
powercfg /setdcvalueindex SCHEME_CURRENT $SUB_BUTTONS $LIDACTION 0
powercfg /setactive SCHEME_CURRENT

Write-Host "`nVerification - both should read 0x00000000:" -ForegroundColor Cyan
powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE |
  Select-String 'Current AC Power Setting Index|Current DC Power Setting Index'
