# Read-only wrapper. Does not print PRIVATE_KEY and does not send a transaction.
& "$PSScriptRoot\spread-lab.ps1" -Stage verify
exit $LASTEXITCODE
