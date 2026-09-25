$ErrorActionPreference = 'Stop'
$Key   = "$env:USERPROFILE\.ssh\etcd_pull"
$Log   = 'C:\Backups\pull-etcd.log'
$Batch = Join-Path $env:TEMP 'etcd-pull.sftp'
$Jobs  = @(
  @{ Remote = '/var/backups/etcd/*';            Local = 'C:\Backups\etcd';   KeepDays = 30 },
  @{ Remote = '/var/backups/velero-offsite/*';  Local = 'C:\Backups\velero'; KeepDays = 14 }
)

foreach ($j in $Jobs) { New-Item -ItemType Directory -Force -Path $j.Local | Out-Null }
$lines = foreach ($j in $Jobs) { "lcd $($j.Local -replace '\\','/')"; "get -a $($j.Remote)" }
$lines -join "`n" | Set-Content -Encoding ascii $Batch

& sftp -q -i $Key -o BatchMode=yes -b $Batch etcdpull@192.168.75.136 | Out-Null
if ($LASTEXITCODE -ne 0) { "$(Get-Date -Format s) FAILED sftp exit $LASTEXITCODE" | Add-Content $Log; exit 1 }

foreach ($j in $Jobs) {
  foreach ($s in Get-ChildItem $j.Local -Filter *.sha256) {
    $file = $s.FullName -replace '\.sha256$',''
    if (Test-Path $file) {
      $expected = (Get-Content $s.FullName).Split(' ')[0]
      $actual   = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
      if ($actual -ne $expected) { "$(Get-Date -Format s) FAILED checksum $file" | Add-Content $Log; exit 1 }
    }
  }
  Get-ChildItem $j.Local | Where-Object LastWriteTime -lt (Get-Date).AddDays(-$j.KeepDays) | Remove-Item
}

$n1 = (Get-ChildItem 'C:\Backups\etcd'   -Filter *.age).Count
$n2 = (Get-ChildItem 'C:\Backups\velero' -Filter *.age).Count
"$(Get-Date -Format s) OK etcd=$n1 velero=$n2" | Add-Content $Log
