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

  It also cost backups. Of the 8 Velero backups on record at 2026-09-26, three
  had failed - all of them starting roughly 3h after their 01:00 schedule,
  i.e. cron firing late on resume while MinIO and Longhorn were still
  unavailable. Nothing alerted, because Prometheus was Pending at the time.

  These settings stop the host sleeping and stop the disk spinning down. They
  do NOT replace the rule: shut the VMs down before closing the lid. Disabling
  sleep protects you from forgetting; it is not a substitute for the staged
  shutdown in docs/runbooks/lab-startup-shutdown.md

  Trade-off: on battery the laptop will now stay awake and drain.

  HIDDEN SETTINGS. "Lid close action" and "Unattended sleep timeout" carry
  ATTRIB_HIDE on this hardware, so powercfg /query will not display them - it
  prints the scheme header and nothing else. The first version of this script
  wrote LIDACTION and then verified only STANDBYIDLE, so it reported success
  while saying nothing about the setting that matters most on a laptop.
  Unhide first, then write, then read back.

  WHEN THE HOST BECOMES UBUNTU (1TB SSD rebuild) this script is dead weight.
  The equivalent belongs in the Ansible host role:
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
    HandleLidSwitch=ignore + HandleLidSwitchExternalPower=ignore in logind.conf
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$SUB_SLEEP     = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
$SUB_BUTTONS   = '4f971e89-eebd-4455-a8de-9e59040e7347'
$SUB_DISK      = '0012ee47-9041-4b5d-9b77-535fba8b1442'

$STANDBYIDLE   = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
$HIBERNATEIDLE = '9d7815a6-7ee4-497e-8888-515a05f02364'
$UNATTENDSLEEP = '7bc4a2f9-d8fc-4469-b07b-33eb785aaca0'
$LIDACTION     = '5ca83367-6e45-459f-a27b-476b1d01c936'
$DISKIDLE      = '6738e2c4-e8a5-4a42-b16a-e040e769756e'

# 1. reveal the hidden settings so they can be written AND read back
powercfg /attributes $SUB_BUTTONS $LIDACTION     -ATTRIB_HIDE
powercfg /attributes $SUB_SLEEP   $UNATTENDSLEEP -ATTRIB_HIDE

# 2. never sleep, never hibernate
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0

# 3. never spin the disk down. A sleeping disk under a running guest is the
#    same I/O stall as a sleeping host, and D: holds all three VMs.
powercfg /change disk-timeout-ac 0
powercfg /change disk-timeout-dc 0

# 4. closing the lid does nothing
powercfg /setacvalueindex SCHEME_CURRENT $SUB_BUTTONS $LIDACTION 0
powercfg /setdcvalueindex SCHEME_CURRENT $SUB_BUTTONS $LIDACTION 0

# 5. do not re-sleep after a maintenance wake (Windows default is 2 minutes)
powercfg /setacvalueindex SCHEME_CURRENT $SUB_SLEEP $UNATTENDSLEEP 0
powercfg /setdcvalueindex SCHEME_CURRENT $SUB_SLEEP $UNATTENDSLEEP 0

# 6. the screen may still blank - that does not suspend the machine
powercfg /change monitor-timeout-ac 15

powercfg /setactive SCHEME_CURRENT

# --- verification: every setting, by GUID, read back ---
$checks = @(
  @{ n = 'sleep after';      sub = $SUB_SLEEP;   s = $STANDBYIDLE },
  @{ n = 'hibernate after';  sub = $SUB_SLEEP;   s = $HIBERNATEIDLE },
  @{ n = 'unattended sleep'; sub = $SUB_SLEEP;   s = $UNATTENDSLEEP },
  @{ n = 'lid close action'; sub = $SUB_BUTTONS; s = $LIDACTION },
  @{ n = 'disk spindown';    sub = $SUB_DISK;    s = $DISKIDLE }
)

Write-Host "`nVerification - every value must read 0x00000000:" -ForegroundColor Cyan
$bad = 0
foreach ($c in $checks) {
    $out = powercfg /q SCHEME_CURRENT $c.sub $c.s
    $acm = $out | Select-String 'Current AC Power Setting Index'
    $dcm = $out | Select-String 'Current DC Power Setting Index'
    $ac = if ($acm) { $acm.ToString().Split(':')[-1].Trim() } else { 'NOT FOUND' }
    $dc = if ($dcm) { $dcm.ToString().Split(':')[-1].Trim() } else { 'NOT FOUND' }
    if ($ac -ne '0x00000000' -or $dc -ne '0x00000000') { $bad++ }
    '{0,-17} AC={1}  DC={2}' -f $c.n, $ac, $dc
}

if ($bad -gt 0) {
    Write-Host "`n$bad setting(s) NOT locked down." -ForegroundColor Red
    exit 1
}

Write-Host "`nAll five locked. Note that S3 remains available (powercfg /a): the" -ForegroundColor Green
Write-Host "host can still be suspended deliberately. Shut the VMs down first." -ForegroundColor Green
