# D5 Cron100 lab helper for Windows PowerShell 5.1.
# Reads starter\.env. Never prints PRIVATE_KEY. Never reads starter\cache.
# Updates only D5_REACTIVE_ADDR and D5_CALLBACK_ADDR, UTF-8 without BOM.
#
#   powershell -ExecutionPolicy Bypass -File .\script\d5-lab.ps1 -Stage preflight
#   powershell -ExecutionPolicy Bypass -File .\script\d5-lab.ps1 -Stage deployReactive
#   powershell -ExecutionPolicy Bypass -File .\script\d5-lab.ps1 -Stage deployCallback
#   powershell -ExecutionPolicy Bypass -File .\script\d5-lab.ps1 -Stage bind
#   powershell -ExecutionPolicy Bypass -File .\script\d5-lab.ps1 -Stage verify
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('preflight', 'prepareRerun', 'deployReactive', 'deployCallback', 'bind', 'verify')]
    [string]$Stage
)

$ErrorActionPreference = 'Stop'
$Starter = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$EnvPath = Join-Path $Starter '.env'
$FoundryBin = 'C:\Users\laven\.foundry\bin'
$Wallet = '0x5576d42Fe13888b7f084190934abD07F061225fe'
$OldAddresses = @(
    '0x6cfe6d08F328b5f067B9ba7F10dc08ca515De950',
    '0x9a30c9bc9c6dC4101679A735e121e3856cC12FB6',
    '0x9bebaFE458DaF45faB88Abd42A2Efc36B38A7A32'
)
$ProxyDefault = '0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4'
$System = '0x8888888888888888888888888888888888888888'
$DefaultReactiveFund = [decimal]'100000000000000000'   # 0.10 ether, wei
$DefaultCallbackFund = [decimal]'2000000000000000'     # 0.002 ether, wei
$OneEther = [decimal]'1000000000000000000'
$Script:PrivateKey = ''

function Fail([string]$Message) {
    Write-Host $Message
    exit 1
}

function Redact([string]$Text) {
    if ($null -eq $Text) { return '' }
    $safe = $Text
    if ($Script:PrivateKey.Length -gt 0) {
        $safe = $safe.Replace($Script:PrivateKey, '[redacted]')
        $bare = $Script:PrivateKey
        if ($bare.StartsWith('0x')) { $bare = $bare.Substring(2) }
        if ($bare.Length -gt 0) { $safe = $safe.Replace($bare, '[redacted]') }
    }
    return $safe
}

function Add-FoundryPath {
    if (Test-Path -LiteralPath $FoundryBin) {
        $env:PATH = $FoundryBin + ';' + $env:PATH
    }
}

function Assert-Tool([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Fail "$Name was not found. Install Foundry 1.9.0 so $FoundryBin\$Name.exe exists, then open a new terminal."
    }
    return $cmd.Source
}

function Invoke-Tool {
    param([string]$Name, [string[]]$ToolArgs)
    $exe = Assert-Tool $Name
    $output = & $exe @ToolArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host (Redact $output)
    if ($code -ne 0) {
        Fail "$Name exited $code. This stage stopped. .env was not changed."
    }
    return $output
}

function Get-CastValue([string]$Text) {
    $lines = @($Text -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 -and $_ -notmatch '^\s*Warning:' })
    if ($lines.Count -eq 0) { return '' }
    return $lines[$lines.Count - 1].Trim()
}

function Get-FirstInteger([string]$Text) {
    $match = [regex]::Match((Get-CastValue $Text), '\d+')
    if (-not $match.Success) { Fail 'Could not parse an integer from cast output.' }
    return [decimal]$match.Value
}

function Convert-ToWei([string]$Name, [string]$Raw) {
    $text = $Raw.Trim()
    if ($text -match '^[0-9]+$') { return [decimal]$text }
    if ($text -match '^([0-9]+)(?:\.([0-9]+))?\s*ether$') {
        $whole = [decimal]$Matches[1]
        $frac = $Matches[2]
        $wei = $whole * $OneEther
        if ($frac) {
            $scale = [decimal]1
            foreach ($ch in $frac.ToCharArray()) { $scale = $scale * 10 }
            $wei = $wei + ([decimal]$frac * $OneEther / $scale)
        }
        return [decimal]::Round($wei, 0)
    }
    Fail "$Name must be an integer wei value, or a decimal followed by ' ether'. Example: 2000000000000000 or 0.002 ether. Do not leave a bare decimal."
}

function Read-DotEnv {
    if (-not (Test-Path -LiteralPath $EnvPath)) {
        Fail "Missing $EnvPath. Keep the existing file. This script does not create a new .env."
    }
    $text = [System.IO.File]::ReadAllText($EnvPath)
    $lines = $text.Split([string[]]@("`r`n", "`n"), [System.StringSplitOptions]::None)
    $map = @{}
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if ($trim.Length -eq 0 -or $trim.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $name = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
        $map[$name] = $value
    }
    return @{ Lines = $lines; Map = $map; Text = $text }
}

function Import-LabEnv($Parsed) {
    foreach ($name in $Parsed.Map.Keys) {
        Set-Item -Path "Env:$name" -Value $Parsed.Map[$name]
    }
    if ($Parsed.Map.ContainsKey('PRIVATE_KEY')) { $Script:PrivateKey = $Parsed.Map['PRIVATE_KEY'] }
    if (-not $env:SEPOLIA_RPC_URL) { $env:SEPOLIA_RPC_URL = 'https://ethereum-sepolia-rpc.publicnode.com' }
    if (-not $env:LASNA_RPC_URL) { $env:LASNA_RPC_URL = 'https://lasna-rpc.rnk.dev/' }
    if (-not $env:DEST_CHAIN_ID) { $env:DEST_CHAIN_ID = '11155111' }
    if (-not $env:CALLBACK_PROXY) { $env:CALLBACK_PROXY = $ProxyDefault }
    if (-not $env:D5_REACTIVE_FUND) { $env:D5_REACTIVE_FUND = [string]$DefaultReactiveFund }
    if (-not $env:D5_CALLBACK_FUND) { $env:D5_CALLBACK_FUND = [string]$DefaultCallbackFund }
    $env:D5_REACTIVE_FUND = [string](Convert-ToWei 'D5_REACTIVE_FUND' $env:D5_REACTIVE_FUND)
    $env:D5_CALLBACK_FUND = [string](Convert-ToWei 'D5_CALLBACK_FUND' $env:D5_CALLBACK_FUND)
    foreach ($name in @('D5_REACTIVE_FUND', 'D5_CALLBACK_FUND')) {
        if ($Parsed.Map.ContainsKey($name) -and $Parsed.Map[$name] -ne (Get-Item "Env:$name").Value) {
            # Foundry rejects "0.002 ether" in .env and then skips the rest of the file.
            Write-LabEnvLine -Name $name -Value (Get-Item "Env:$name").Value
        }
    }
    foreach ($name in @('D5_REACTIVE_ADDR', 'D5_CALLBACK_ADDR')) {
        $fromFile = ''
        if ($Parsed.Map.ContainsKey($name)) { $fromFile = $Parsed.Map[$name].Trim() }
        if ([string]::IsNullOrWhiteSpace($fromFile)) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
    }
}

function Get-Address([string]$Name) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ($null -eq $value) { return '' }
    return $value.Trim()
}

function Assert-NotOld([string]$Addr, [string]$Name) {
    foreach ($old in $OldAddresses) {
        if ($Addr -and $Addr.Equals($old, [System.StringComparison]::OrdinalIgnoreCase)) {
            Fail "$Name points at an existing D3/D4 contract. This lab does not send transactions to it."
        }
    }
}

function Assert-EmptyAddress([string]$Name) {
    $addr = Get-Address $Name
    if (-not [string]::IsNullOrWhiteSpace($addr)) {
        Fail "$Name is already $addr. This stage stopped and did not send a transaction. It also did not skip ahead. Delete only that line if you really intend to deploy again."
    }
}

function Assert-SetAddress([string]$Name) {
    $addr = Get-Address $Name
    if ([string]::IsNullOrWhiteSpace($addr)) { Fail "$Name is empty. Run the previous stage first." }
    if ($addr -notmatch '^0x[0-9a-fA-F]{40}$') { Fail "$Name is not a 20-byte address." }
    Assert-NotOld $addr $Name
    return $addr
}

function Write-LabEnvLine {
    param([string]$Name, [string]$Value)
    $allowed = @(
        'D5_REACTIVE_ADDR', 'D5_CALLBACK_ADDR',
        'D5_FAILED_REACTIVE_ADDR', 'D5_FAILED_CALLBACK_ADDR',
        'D5_REACTIVE_FUND', 'D5_CALLBACK_FUND'
    )
    if ($allowed -notcontains $Name) {
        Fail 'Refusing to write any .env key other than the D5 address and fund lines.'
    }
    if ($Name -like '*ADDR') { Assert-NotOld $Value $Name }
    $parsed = Read-DotEnv
    $newline = "`n"
    if ($parsed.Text.Contains("`r`n")) { $newline = "`r`n" }
    $found = $false
    $updated = @(foreach ($line in @($parsed.Lines)) {
        if ($line -match ('^\s*' + [regex]::Escape($Name) + '\s*=')) {
            $found = $true
            "$Name=$Value"
        } else {
            $line
        }
    })
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $updated) { $list.Add($line) }
    if (-not $found) {
        if ($list.Count -gt 0 -and $list[$list.Count - 1] -eq '') { $list.RemoveAt($list.Count - 1) }
        $list.Add("$Name=$Value")
        $list.Add('')
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($EnvPath, ($list -join $newline), $utf8)
    Set-Item -Path "Env:$Name" -Value $Value
    if ($Name -like '*ADDR') { Write-Host "Updated only $Name. Other .env lines were left in place." }
}

function Write-AddressOnly {
    param([string]$Name, [string]$Address)
    Write-LabEnvLine -Name $Name -Value $Address
}

function Get-BroadcastPath([string]$ChainId) {
    return Join-Path $Starter "broadcast\DeployD5Cron.s.sol\$ChainId\run-latest.json"
}

function Read-Broadcast {
    param([string]$ChainId)
    $path = Get-BroadcastPath $ChainId
    if ($path -match 'cache') { Fail 'Refusing to read cache.' }
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    return @{ Path = $path; Json = $json }
}

function Test-ReceiptOk($Receipt) {
    if ($null -eq $Receipt) { return $false }
    $status = [string]$Receipt.status
    return $status -eq '0x1' -or $status -eq '0x01' -or $status -eq '1'
}

function Get-ReceiptForHash($Json, [string]$Hash) {
    foreach ($receipt in @($Json.receipts)) {
        if ([string]$receipt.transactionHash -eq $Hash) { return $receipt }
    }
    return $null
}

function Assert-NoCreateReceipt([string]$ChainId, [string]$ContractName) {
    $found = Read-Broadcast $ChainId
    if ($null -eq $found) { return }
    foreach ($tx in @($found.Json.transactions)) {
        $name = [string]$tx.contractName
        $type = [string]$tx.transactionType
        if ($type -eq 'CREATE' -and ($name -eq $ContractName -or [string]::IsNullOrWhiteSpace($name))) {
            $hash = [string]$tx.hash
            $receipt = Get-ReceiptForHash $found.Json $hash
            $addr = [string]$tx.contractAddress
            Write-Host "Found existing CREATE receipt. address=$addr tx=$hash statusOk=$(Test-ReceiptOk $receipt)"
            Fail "deploy did not start. Existing broadcast was not ignored and .env was not changed. If this receipt is the contract you want, copy the address into .env yourself. If it failed, move broadcast\DeployD5Cron.s.sol\$ChainId aside and run the stage again."
        }
    }
}

function Save-CreateFromBroadcast {
    param([string]$ChainId, [string]$ContractName, [string]$EnvName)
    $found = Read-Broadcast $ChainId
    if ($null -eq $found) { Fail "forge finished but broadcast receipt was not found. .env was not changed." }
    $chosen = $null
    foreach ($tx in @($found.Json.transactions)) {
        if ([string]$tx.transactionType -eq 'CREATE' -and [string]$tx.contractName -eq $ContractName) { $chosen = $tx }
    }
    if ($null -eq $chosen) { Fail "No CREATE receipt for $ContractName. .env was not changed." }
    $hash = [string]$chosen.hash
    $receipt = Get-ReceiptForHash $found.Json $hash
    if (-not (Test-ReceiptOk $receipt)) { Fail "CREATE transaction $hash did not succeed. .env was not changed." }
    $addr = [string]$chosen.contractAddress
    if ([string]::IsNullOrWhiteSpace($addr)) { $addr = [string]$receipt.contractAddress }
    if ($addr -notmatch '^0x[0-9a-fA-F]{40}$') { Fail "Receipt address is missing. .env was not changed." }
    Write-AddressOnly -Name $EnvName -Address $addr
    Write-Host "tx=$hash"
    $explorer = "https://lasna.reactscan.net/tx/$hash"
    if ($ChainId -eq '11155111') { $explorer = "https://sepolia.etherscan.io/tx/$hash" }
    Write-Host $explorer
}

function Get-LiveNeed {
    $sepoliaBase = Get-FirstInteger (Invoke-Tool 'cast' @('base-fee', '--rpc-url', $env:SEPOLIA_RPC_URL))
    $lasnaBase = Get-FirstInteger (Invoke-Tool 'cast' @('base-fee', '--rpc-url', $env:LASNA_RPC_URL))
    $sepoliaBal = Get-FirstInteger (Invoke-Tool 'cast' @('balance', $Wallet, '--rpc-url', $env:SEPOLIA_RPC_URL))
    $lasnaBal = Get-FirstInteger (Invoke-Tool 'cast' @('balance', $Wallet, '--rpc-url', $env:LASNA_RPC_URL))
    $callbackFund = [decimal]$env:D5_CALLBACK_FUND
    $reactiveFund = [decimal]$env:D5_REACTIVE_FUND
    $sepoliaPrice = $sepoliaBase * 2
    # forge prints "Estimated amount required" for gas only. The value sent into the
    # contract is extra. Deploy sim gas is 852894 * 130 / 100 = 1108762. Max fee is
    # 2 * baseFee + 1 wei, which is forge's own estimate. Do not use a lower multiplier.
    $oneGwei = [decimal]'1000000000'
    if ($sepoliaPrice -lt $oneGwei) { $sepoliaPrice = $oneGwei }
    $sepoliaGasCap = [decimal]3160356 * $sepoliaPrice
    $sepoliaNeed = $callbackFund + $sepoliaGasCap
    $lasnaMaxFee = ($lasnaBase * 2) + 1
    $lasnaGasCap = [decimal]1108762 * $lasnaMaxFee
    $lasnaNeed = $reactiveFund + $lasnaGasCap
    Write-Host "Wallet $Wallet"
    Write-Host "D5_CALLBACK_FUND wei=$callbackFund"
    Write-Host "D5_REACTIVE_FUND wei=$reactiveFund"
    Write-Host "Sepolia balance wei=$sepoliaBal baseFee wei=$sepoliaBase gasCap wei=$sepoliaGasCap need wei=$sepoliaNeed"
    Write-Host "Lasna balance wei=$lasnaBal baseFee wei=$lasnaBase gasCap wei=$lasnaGasCap need wei=$lasnaNeed"
    Write-Host "Lasna gas cap does not include the lREACT stored in the new contract."
    return @{
        SepoliaBalance = $sepoliaBal
        LasnaBalance   = $lasnaBal
        SepoliaNeed    = $sepoliaNeed
        LasnaNeed      = $lasnaNeed
        SepoliaBase    = $sepoliaBase
        LasnaBase      = $lasnaBase
    }
}

function Show-FeeEstimate($Live) {
    $coeffText = Invoke-Tool 'cast' @('call', $env:CALLBACK_PROXY, '_gasPriceCoeffPer1000()(uint256)', '--rpc-url', $env:SEPOLIA_RPC_URL)
    $extraText = Invoke-Tool 'cast' @('call', $env:CALLBACK_PROXY, '_extraGas()(uint256)', '--rpc-url', $env:SEPOLIA_RPC_URL)
    $kText = Invoke-Tool 'cast' @('call', $System, '_extraGas()(uint256)', '--rpc-url', $env:LASNA_RPC_URL)
    $coeff = Get-FirstInteger $coeffText
    $extra = Get-FirstInteger $extraText
    $k = Get-FirstInteger $kText
    $twoCallbacks = 2 * (80000 + $extra) * $coeff / 1000 * $Live.SepoliaBase
    $twoReacts = 2 * (200000 + $k) * $Live.LasnaBase
    Write-Host "Two Sepolia callbacks at the current base fee, assuming 80000 gas plus proxy extra gas: $twoCallbacks wei"
    Write-Host "Two Lasna reacts at the current base fee, assuming 200000 gas plus system extra gas: $twoReacts wei"
    Write-Host "0.001 ether = 1000000000000000 wei. 0.002 ether = 2000000000000000 wei."
    Write-Host "0.10 ether = 100000000000000000 wei. 0.15 ether = 150000000000000000 wei."
}

function Invoke-Preflight {
    Assert-Tool 'forge' | Out-Null
    Assert-Tool 'cast' | Out-Null
    if ([string]::IsNullOrWhiteSpace($Script:PrivateKey)) { Fail 'PRIVATE_KEY is missing from .env. The value was not printed.' }
    Write-Host 'PRIVATE_KEY: present'
    foreach ($name in @('D5_REACTIVE_ADDR', 'D5_CALLBACK_ADDR')) {
        $addr = Get-Address $name
        if ([string]::IsNullOrWhiteSpace($addr)) { Write-Host "${name}: empty" }
        else { Write-Host "${name}: $addr" }
    }
    $live = Get-LiveNeed
    Show-FeeEstimate $live
    if ($live.SepoliaBalance -lt $live.SepoliaNeed) {
        Fail 'Sepolia balance is below the callback fund plus deploy headroom. No transaction was sent.'
    }
    if ($live.LasnaBalance -lt $live.LasnaNeed) {
        Fail 'Lasna balance is below D5_REACTIVE_FUND plus forge gas cap (1108762 gas at 2x base fee). That cap does not include the value stored in the contract. No transaction was sent. Two reacts cost about 0.034 lREACT, so 50000000000000000 wei (0.05 ether) still leaves about 0.016 lREACT in the contract. 60000000000000000 wei plus the gas cap is above the current wallet. Do not lower the fee cap below 2x base fee.'
    }
    Write-Host 'Balance check passed. Compiling and testing. This does not broadcast.'
    Invoke-Tool 'forge' @('test', '--match-path', 'test/D5Cron.t.sol', '--evm-version', 'cancun', '-vv') | Out-Null
    Write-Host 'Running the Sepolia proxy gas test under Amsterdam. This does not broadcast.'
    Invoke-Tool 'forge' @('test', '--match-path', 'test/D5CallbackGas.t.sol', '--evm-version', 'amsterdam', '-vv') | Out-Null
    Write-Host 'preflight finished. No transaction was sent.'
}

function Invoke-DeployReactive {
    Assert-EmptyAddress 'D5_REACTIVE_ADDR'
    Assert-NoCreateReceipt '5318007' 'D5CronReactive'
    $live = Get-LiveNeed
    if ($live.LasnaBalance -lt $live.LasnaNeed) { Fail 'Lasna balance check failed. No transaction was sent.' }
    Invoke-Tool 'forge' @(
        'script', 'script/DeployD5Cron.s.sol:DeployD5Reactive',
        '--rpc-url', $env:LASNA_RPC_URL, '--broadcast', '--chain', '5318007', '--evm-version', 'cancun'
    ) | Out-Null
    Save-CreateFromBroadcast -ChainId '5318007' -ContractName 'D5CronReactive' -EnvName 'D5_REACTIVE_ADDR'
}

function Invoke-DeployCallback {
    Assert-SetAddress 'D5_REACTIVE_ADDR' | Out-Null
    Assert-EmptyAddress 'D5_CALLBACK_ADDR'
    Assert-NoCreateReceipt '11155111' 'D5CronCallback'
    $live = Get-LiveNeed
    if ($live.SepoliaBalance -lt $live.SepoliaNeed) { Fail 'Sepolia balance check failed. No transaction was sent.' }
    Invoke-Tool 'forge' @(
        'script', 'script/DeployD5Cron.s.sol:DeployD5Callback',
        '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
    ) | Out-Null
    Save-CreateFromBroadcast -ChainId '11155111' -ContractName 'D5CronCallback' -EnvName 'D5_CALLBACK_ADDR'
}

function Invoke-Bind {
    $reactive = Assert-SetAddress 'D5_REACTIVE_ADDR'
    $callback = Assert-SetAddress 'D5_CALLBACK_ADDR'
    $recipient = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, 'recipient()(address)'))
    $subscribed = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, 'subscribed()(bool)'))
    if ($subscribed -eq 'true' -and $recipient.Equals($callback, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "Already bound. recipient=$recipient subscribed=true. No transaction was sent."
    }
    Invoke-Tool 'forge' @(
        'script', 'script/DeployD5Cron.s.sol:SetD5Recipient',
        '--rpc-url', $env:LASNA_RPC_URL, '--broadcast', '--chain', '5318007', '--evm-version', 'cancun'
    ) | Out-Null
    $found = Read-Broadcast '5318007'
    if ($null -eq $found) { Fail 'bind broadcast receipt was not found.' }
    $tx = $null
    foreach ($item in @($found.Json.transactions)) { $tx = $item }
    $hash = [string]$tx.hash
    $receipt = Get-ReceiptForHash $found.Json $hash
    if (-not (Test-ReceiptOk $receipt)) { Fail "bind transaction $hash did not succeed." }
    Write-Host "bind tx=$hash"
    Write-Host "https://lasna.reactscan.net/tx/$hash"
    Write-Host 'Cron100 is now subscribed. Wait about 5 minutes, then run -Stage verify.'
}

function Invoke-Verify {
    $reactive = Assert-SetAddress 'D5_REACTIVE_ADDR'
    $callback = Assert-SetAddress 'D5_CALLBACK_ADDR'
    Write-Host "Lasna $reactive"
    foreach ($sig in @('subscribed()(bool)', 'stopped()(bool)', 'remaining()(uint256)', 'executed()(uint256)', 'recipient()(address)', 'lastCronNumber()(uint256)', 'lastReactBlock()(uint256)')) {
        $value = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, $sig))
        Write-Host "$sig $value"
    }
    Write-Host ("balance lREACT " + (Get-CastValue (Invoke-Tool 'cast' @('balance', '--rpc-url', $env:LASNA_RPC_URL, $reactive, '-e'))))
    Write-Host ("debt " + (Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $System, 'debt(address)(uint256)', $reactive))))
    Write-Host "Sepolia $callback"
    foreach ($sig in @('count()(uint256)', 'lastCronNumber()(uint256)', 'lastTickIndex()(uint256)')) {
        $value = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $callback, $sig))
        Write-Host "$sig $value"
    }
    Write-Host ("balance ETH " + (Get-CastValue (Invoke-Tool 'cast' @('balance', '--rpc-url', $env:SEPOLIA_RPC_URL, $callback, '-e'))))
    Write-Host ("proxy debt " + (Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $env:CALLBACK_PROXY, 'debt(address)(uint256)', $callback))))
    $bn = Get-FirstInteger (Invoke-Tool 'cast' @('block-number', '--rpc-url', $env:SEPOLIA_RPC_URL))
    $from = $bn - 5000
    if ($from -lt 0) { $from = 0 }
    Invoke-Tool 'cast' @(
        'logs', '--rpc-url', $env:SEPOLIA_RPC_URL, '--from-block', ([string]$from),
        '--address', $callback,
        'Ticked(address indexed reactive, uint256 indexed tickIndex, uint256 cronNumber, uint256 count)'
    ) | Out-Null
    Write-Host 'verify finished. No transaction was sent.'
}

Add-FoundryPath
Set-Location -LiteralPath $Starter
$parsedEnv = Read-DotEnv
Import-LabEnv $parsedEnv

function Clear-LabEnvLine([string]$Name) {
    Write-LabEnvLine -Name $Name -Value ''
}

function Invoke-PrepareRerun {
    $reactive = Get-Address 'D5_REACTIVE_ADDR'
    $callback = Get-Address 'D5_CALLBACK_ADDR'
    if ([string]::IsNullOrWhiteSpace($reactive) -and [string]::IsNullOrWhiteSpace($callback)) {
        Fail 'D5_REACTIVE_ADDR and D5_CALLBACK_ADDR are already empty. Nothing was moved.'
    }
    if (-not [string]::IsNullOrWhiteSpace((Get-Address 'D5_FAILED_REACTIVE_ADDR')) -or -not [string]::IsNullOrWhiteSpace((Get-Address 'D5_FAILED_CALLBACK_ADDR'))) {
        Fail 'D5_FAILED_REACTIVE_ADDR or D5_FAILED_CALLBACK_ADDR already has a value. This script will not overwrite the saved failed deployment.'
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $src = Join-Path $Starter 'broadcast\DeployD5Cron.s.sol'
    if (Test-Path -LiteralPath $src) {
        $destRoot = Join-Path $Starter "broadcast\d5-archive\$stamp"
        if (Test-Path -LiteralPath $destRoot) { Fail "Archive folder already exists: $destRoot" }
        New-Item -ItemType Directory -Path $destRoot | Out-Null
        Move-Item -LiteralPath $src -Destination (Join-Path $destRoot 'DeployD5Cron.s.sol')
        Write-Host "Moved public receipts to broadcast\d5-archive\$stamp\DeployD5Cron.s.sol"
    } else {
        Write-Host 'No broadcast\DeployD5Cron.s.sol directory was present.'
    }
    if (-not [string]::IsNullOrWhiteSpace($reactive)) { Write-LabEnvLine -Name 'D5_FAILED_REACTIVE_ADDR' -Value $reactive }
    if (-not [string]::IsNullOrWhiteSpace($callback)) { Write-LabEnvLine -Name 'D5_FAILED_CALLBACK_ADDR' -Value $callback }
    Clear-LabEnvLine 'D5_REACTIVE_ADDR'
    Clear-LabEnvLine 'D5_CALLBACK_ADDR'
    Write-Host 'Cleared only D5_REACTIVE_ADDR and D5_CALLBACK_ADDR. Other .env keys were kept. cache was not read.'
    Write-Host 'The failed callback cannot be reused: its reactive address is immutable. Deploy both contracts again.'
}

switch ($Stage) {
    'preflight' { Invoke-Preflight }
    'prepareRerun' { Invoke-PrepareRerun }
    'deployReactive' { Invoke-DeployReactive }
    'deployCallback' { Invoke-DeployCallback }
    'bind' { Invoke-Bind }
    'verify' { Invoke-Verify }
}
