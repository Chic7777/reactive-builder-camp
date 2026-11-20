# Read-only check for the D5 Cron100 lab.
# Does not print PRIVATE_KEY, does not send a transaction.
# Usage, from the starter directory:
#   powershell -ExecutionPolicy Bypass -File .\script\verify-d5.ps1

$ErrorActionPreference = "Stop"
Set-Location -LiteralPath (Join-Path $PSScriptRoot "..")

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing .env. Copy .env.example to .env and fill it locally. Do not paste .env into chat."
    }
    $loaded = 0
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) { continue }
        $eq = $line.IndexOf("=")
        if ($eq -lt 1) { continue }
        $name = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
        Set-Item -Path "Env:$name" -Value $value
        $loaded++
    }
    Write-Host "Loaded $loaded .env entries. Values were not printed."
}

function Assert-Cast {
    if (-not (Get-Command cast -ErrorAction SilentlyContinue)) {
        throw "cast is not on PATH. Open a new terminal after installing Foundry 1.9.0."
    }
}

Assert-Cast
Import-DotEnv -Path ".\.env"

$old = @(
    "0x6cfe6d08F328b5f067B9ba7F10dc08ca515De950",
    "0x9a30c9bc9c6dC4101679A735e121e3856cC12FB6",
    "0x9bebaFE458DaF45faB88Abd42A2Efc36B38A7A32"
)
foreach ($name in @("D5_REACTIVE_ADDR", "D5_CALLBACK_ADDR")) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "$name is empty. Deploy first, then add the address with Add-Content. Do not overwrite .env."
    }
    foreach ($blocked in $old) {
        if ($value.Equals($blocked, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "$name points at an existing D3/D4 contract. This lab uses new addresses only."
        }
    }
}

$lasna = $env:LASNA_RPC_URL
if ([string]::IsNullOrWhiteSpace($lasna)) { $lasna = "https://lasna-rpc.rnk.dev/" }
$sepolia = $env:SEPOLIA_RPC_URL
if ([string]::IsNullOrWhiteSpace($sepolia)) { $sepolia = "https://ethereum-sepolia-rpc.publicnode.com" }
$proxy = $env:CALLBACK_PROXY
if ([string]::IsNullOrWhiteSpace($proxy)) { $proxy = "0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4" }
$sys = "0x8888888888888888888888888888888888888888"

Write-Host ""
Write-Host "== Lasna D5CronReactive $($env:D5_REACTIVE_ADDR)"
Write-Host "subscribed      $(cast call --rpc-url $lasna $env:D5_REACTIVE_ADDR 'subscribed()(bool)')"
Write-Host "stopped         $(cast call --rpc-url $lasna $env:D5_REACTIVE_ADDR 'stopped()(bool)')"
Write-Host "remaining       $(cast call --rpc-url $lasna $env:D5_REACTIVE_ADDR 'remaining()(uint256)')"
Write-Host "executed        $(cast call --rpc-url $lasna $env:D5_REACTIVE_ADDR 'executed()(uint256)')"
Write-Host "recipient       $(cast call --rpc-url $lasna $env:D5_REACTIVE_ADDR 'recipient()(address)')"
Write-Host "lastCronNumber  $(cast call --rpc-url $lasna $env:D5_REACTIVE_ADDR 'lastCronNumber()(uint256)')"
Write-Host "lastReactBlock  $(cast call --rpc-url $lasna $env:D5_REACTIVE_ADDR 'lastReactBlock()(uint256)')"
Write-Host "balance lREACT  $(cast balance --rpc-url $lasna $env:D5_REACTIVE_ADDR -e)"
Write-Host "debt            $(cast call --rpc-url $lasna $sys 'debt(address)(uint256)' $env:D5_REACTIVE_ADDR)"
Write-Host "explorer        https://lasna.reactscan.net/address/$($env:D5_REACTIVE_ADDR)"

Write-Host ""
Write-Host "== Sepolia D5CronCallback $($env:D5_CALLBACK_ADDR)"
Write-Host "count           $(cast call --rpc-url $sepolia $env:D5_CALLBACK_ADDR 'count()(uint256)')"
Write-Host "lastCronNumber  $(cast call --rpc-url $sepolia $env:D5_CALLBACK_ADDR 'lastCronNumber()(uint256)')"
Write-Host "lastTickIndex   $(cast call --rpc-url $sepolia $env:D5_CALLBACK_ADDR 'lastTickIndex()(uint256)')"
Write-Host "balance ETH     $(cast balance --rpc-url $sepolia $env:D5_CALLBACK_ADDR -e)"
Write-Host "proxy debt      $(cast call --rpc-url $sepolia $proxy 'debt(address)(uint256)' $env:D5_CALLBACK_ADDR)"
Write-Host "explorer        https://sepolia.etherscan.io/address/$($env:D5_CALLBACK_ADDR)"

$bn = [int](cast block-number --rpc-url $sepolia)
$from = [Math]::Max(0, $bn - 5000)
Write-Host ""
Write-Host "== recent Ticked logs from block $from"
cast logs --rpc-url $sepolia --from-block $from --address $env:D5_CALLBACK_ADDR "Ticked(address indexed reactive, uint256 indexed tickIndex, uint256 cronNumber, uint256 count)"

Write-Host ""
Write-Host "Done. Copy the Sepolia transaction hashes and the Lasna react transactions into the lab notes yourself."
Write-Host "This script did not send a transaction."
