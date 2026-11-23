# Phase A spread lab helper for Windows PowerShell 5.1.
# 教学模拟双池价差路径。只读 starter\.env，绝不打印 PRIVATE_KEY，不读 starter\cache。
# 只写 SPREAD_* 行。不改 D5_*，也不改 ORIGIN_ADDR / REACTIVE_ADDR / CALLBACK_ADDR。
#
#   powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage preflight
#   powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage deployAmm
#   powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage deployReactive
#   powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage deployLedger
#   powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage bind
#   powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage nudge
#   powershell -ExecutionPolicy Bypass -File .\script\spread-lab.ps1 -Stage verify
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('preflight', 'prepareRerun', 'deployAmm', 'deployReactive', 'deployLedger', 'bind', 'nudge', 'verify')]
    [string]$Stage
)

$ErrorActionPreference = 'Stop'
$Starter = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$EnvPath = Join-Path $Starter '.env'
$FoundryBin = 'C:\Users\laven\.foundry\bin'
$Wallet = '0x5576d42Fe13888b7f084190934abD07F061225fe'
# 官方 D3/D4 示例，以及 D5 Cron 实验（成功的一对和 out of gas 的一对）。这条路径不能用它们。
$OldAddresses = @(
    '0x6cfe6d08F328b5f067B9ba7F10dc08ca515De950',
    '0x9a30c9bc9c6dC4101679A735e121e3856cC12FB6',
    '0x9bebaFE458DaF45faB88Abd42A2Efc36B38A7A32',
    '0xC436b8445cBf6ce233ce83873B3Ac19F5ace04fD',
    '0x245FBD3aC14Eb117F6587E7E5e64A8d79AA684a2',
    '0x0F3441F4a1302965AeA144885A8242b57350A3d5',
    '0x7665c61e81d98576Cf6eec70Ba9A76961C650e69'
)
$ProxyDefault = '0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4'
$System = '0x8888888888888888888888888888888888888888'
$DefaultReactiveFund = [decimal]'100000000000000000'   # 0.10 ether, wei
$DefaultLedgerFund = [decimal]'2000000000000000'       # 0.002 ether, wei
$OneEther = [decimal]'1000000000000000000'
# CREATE gas measured 2026-11-23 on Cancun, plus 21000, plus 16 gas per init-code byte,
# then forge's 130% estimate multiplier. The cap is the balance check, not a lower fee.
# SimDualAmm create ~325919 / 1149 bytes. Ledger create ~521211 / 2543 bytes.
# SpreadReactive create ~1443684 / 7042 bytes. Two nudges share one cap.
$SepoliaAmmGasCap = [decimal]500000
$SepoliaLedgerGasCap = [decimal]800000
$SepoliaNudgeGasCap = [decimal]200000
$LasnaReactiveGasCap = [decimal]2300000
$Script:PrivateKey = ''
$Script:EnvForbidden = @()

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
        Fail "$Name was not found. Install Foundry so $FoundryBin\$Name.exe exists, then open a new terminal."
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
    if (-not $env:ORIGIN_CHAIN_ID) { $env:ORIGIN_CHAIN_ID = '11155111' }
    if (-not $env:DEST_CHAIN_ID) { $env:DEST_CHAIN_ID = '11155111' }
    if (-not $env:CALLBACK_PROXY) { $env:CALLBACK_PROXY = $ProxyDefault }
    if (-not $env:SPREAD_REACTIVE_FUND) { $env:SPREAD_REACTIVE_FUND = [string]$DefaultReactiveFund }
    if (-not $env:SPREAD_LEDGER_FUND) { $env:SPREAD_LEDGER_FUND = [string]$DefaultLedgerFund }
    if (-not $env:SPREAD_THRESHOLD_BPS) { $env:SPREAD_THRESHOLD_BPS = '100' }
    if (-not $env:SPREAD_MAX_RECORDS) { $env:SPREAD_MAX_RECORDS = '5' }
    $env:SPREAD_REACTIVE_FUND = [string](Convert-ToWei 'SPREAD_REACTIVE_FUND' $env:SPREAD_REACTIVE_FUND)
    $env:SPREAD_LEDGER_FUND = [string](Convert-ToWei 'SPREAD_LEDGER_FUND' $env:SPREAD_LEDGER_FUND)
    foreach ($name in @('SPREAD_REACTIVE_FUND', 'SPREAD_LEDGER_FUND')) {
        if ($Parsed.Map.ContainsKey($name) -and $Parsed.Map[$name] -ne (Get-Item "Env:$name").Value) {
            # Foundry 读到 "0.002 ether" 这种带空格的值会把整份 .env 丢掉。这里只改这两行。
            Write-LabEnvLine -Name $name -Value (Get-Item "Env:$name").Value
        }
    }
    foreach ($name in @('SPREAD_AMM_ADDR', 'SPREAD_REACTIVE_ADDR', 'SPREAD_LEDGER_ADDR')) {
        $fromFile = ''
        if ($Parsed.Map.ContainsKey($name)) { $fromFile = $Parsed.Map[$name].Trim() }
        if ([string]::IsNullOrWhiteSpace($fromFile)) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
    }
    $Script:EnvForbidden = @()
    foreach ($name in @('ORIGIN_ADDR', 'REACTIVE_ADDR', 'CALLBACK_ADDR', 'D5_REACTIVE_ADDR', 'D5_CALLBACK_ADDR', 'D5_FAILED_REACTIVE_ADDR', 'D5_FAILED_CALLBACK_ADDR')) {
        if ($Parsed.Map.ContainsKey($name) -and -not [string]::IsNullOrWhiteSpace($Parsed.Map[$name])) {
            $Script:EnvForbidden += $Parsed.Map[$name].Trim()
        }
    }
}

function Get-Address([string]$Name) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ($null -eq $value) { return '' }
    return $value.Trim()
}

function Assert-NotOld([string]$Addr, [string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Addr)) { return }
    foreach ($old in $OldAddresses) {
        if ($Addr.Equals($old, [System.StringComparison]::OrdinalIgnoreCase)) {
            Fail "$Name points at an official example or a D5 contract. This path does not send transactions to it."
        }
    }
    foreach ($old in $Script:EnvForbidden) {
        if ($Addr.Equals($old, [System.StringComparison]::OrdinalIgnoreCase)) {
            Fail "$Name matches ORIGIN_ADDR, REACTIVE_ADDR, CALLBACK_ADDR, or a D5_ address already in .env. This path does not reuse those contracts."
        }
    }
}

function Assert-EmptyAddress([string]$Name) {
    $addr = Get-Address $Name
    if (-not [string]::IsNullOrWhiteSpace($addr)) {
        Fail "$Name is already $addr. This stage stopped and did not send a transaction. Delete only that SPREAD_ line if you really intend to deploy again."
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
        'SPREAD_AMM_ADDR', 'SPREAD_REACTIVE_ADDR', 'SPREAD_LEDGER_ADDR',
        'SPREAD_REACTIVE_FUND', 'SPREAD_LEDGER_FUND',
        'SPREAD_THRESHOLD_BPS', 'SPREAD_MAX_RECORDS'
    )
    if ($allowed -notcontains $Name) {
        Fail 'Refusing to write any .env key other than the SPREAD_ lines.'
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

function Get-BroadcastDir([string]$ChainId) {
    $path = Join-Path $Starter "broadcast\DeploySpread.s.sol\$ChainId"
    if ($path -match 'cache') { Fail 'Refusing to read cache.' }
    return $path
}

function Read-BroadcastFiles([string]$ChainId) {
    $dir = Get-BroadcastDir $ChainId
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter 'run-*.json' -File)) {
        $json = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        # pscustomobject，避免 PowerShell 5.1 把 hashtable 拆成键值对。
        [pscustomobject]@{ Path = $file.FullName; Json = $json }
    }
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
    foreach ($found in @(Read-BroadcastFiles $ChainId)) {
        foreach ($tx in @($found.Json.transactions)) {
            $name = [string]$tx.contractName
            $type = [string]$tx.transactionType
            if ($type -eq 'CREATE' -and ($name -eq $ContractName -or [string]::IsNullOrWhiteSpace($name))) {
                $hash = [string]$tx.hash
                $receipt = Get-ReceiptForHash $found.Json $hash
                $addr = [string]$tx.contractAddress
                Write-Host "Found existing CREATE receipt. address=$addr tx=$hash statusOk=$(Test-ReceiptOk $receipt)"
                Fail "deploy did not start. Existing broadcast was not ignored and .env was not changed. If this receipt is the contract you want, copy the address into the SPREAD_ line yourself. If it failed, run -Stage prepareRerun or move broadcast\DeploySpread.s.sol\$ChainId aside."
            }
        }
    }
}

function Get-LatestBroadcast([string]$ChainId) {
    $latest = $null
    foreach ($found in @(Read-BroadcastFiles $ChainId)) {
        if ($found.Path -match 'run-latest\.json$') { $latest = $found }
    }
    return $latest
}

function Save-CreateFromBroadcast {
    param([string]$ChainId, [string]$ContractName, [string]$EnvName)
    $found = Get-LatestBroadcast $ChainId
    if ($null -eq $found) { Fail "forge finished but broadcast receipt was not found. .env was not changed." }
    $chosen = $null
    foreach ($tx in @($found.Json.transactions)) {
        if ([string]$tx.transactionType -eq 'CREATE' -and [string]$tx.contractName -eq $ContractName) { $chosen = $tx }
    }
    if ($null -eq $chosen) { Fail "No CREATE receipt for $ContractName. .env was not changed." }
    $chosenJson = $found.Json
    $hash = [string]$chosen.hash
    $receipt = Get-ReceiptForHash $chosenJson $hash
    if (-not (Test-ReceiptOk $receipt)) { Fail "CREATE transaction $hash did not succeed. .env was not changed." }
    $addr = [string]$chosen.contractAddress
    if ([string]::IsNullOrWhiteSpace($addr)) { $addr = [string]$receipt.contractAddress }
    if ($addr -notmatch '^0x[0-9a-fA-F]{40}$') { Fail "Receipt address is missing. .env was not changed." }
    Write-LabEnvLine -Name $EnvName -Value $addr
    Write-Host "tx=$hash"
    $explorer = "https://lasna.reactscan.net/tx/$hash"
    if ($ChainId -eq '11155111') { $explorer = "https://sepolia.etherscan.io/tx/$hash" }
    Write-Host $explorer
}

function Get-MaxFee([decimal]$BaseFee) {
    return ($BaseFee * 2) + 1
}

function Get-LiveNeed {
    $sepoliaBase = Get-FirstInteger (Invoke-Tool 'cast' @('base-fee', '--rpc-url', $env:SEPOLIA_RPC_URL))
    $lasnaBase = Get-FirstInteger (Invoke-Tool 'cast' @('base-fee', '--rpc-url', $env:LASNA_RPC_URL))
    $sepoliaBal = Get-FirstInteger (Invoke-Tool 'cast' @('balance', $Wallet, '--rpc-url', $env:SEPOLIA_RPC_URL))
    $lasnaBal = Get-FirstInteger (Invoke-Tool 'cast' @('balance', $Wallet, '--rpc-url', $env:LASNA_RPC_URL))
    $ledgerFund = [decimal]$env:SPREAD_LEDGER_FUND
    $reactiveFund = [decimal]$env:SPREAD_REACTIVE_FUND
    $sepoliaPrice = $sepoliaBase * 2
    $oneGwei = [decimal]'1000000000'
    # Sepolia base fee 在 2026-11-23 只有十几 wei。下限 1 gwei，避免检查被尘埃 gas 骗过，
    # 也让 base fee 涨到 1 gwei 时预检仍然盖得住。不要拿这个下限去 Lasna。
    if ($sepoliaPrice -lt $oneGwei) { $sepoliaPrice = $oneGwei }
    $sepoliaGasUnits = $SepoliaAmmGasCap + $SepoliaLedgerGasCap + $SepoliaNudgeGasCap
    $sepoliaGasCap = $sepoliaGasUnits * $sepoliaPrice
    $sepoliaNeed = $ledgerFund + $sepoliaGasCap
    $lasnaMaxFee = Get-MaxFee $lasnaBase
    $lasnaGasCap = $LasnaReactiveGasCap * $lasnaMaxFee
    $lasnaNeed = $reactiveFund + $lasnaGasCap
    Write-Host "Wallet $Wallet"
    Write-Host "SPREAD_LEDGER_FUND wei=$ledgerFund"
    Write-Host "SPREAD_REACTIVE_FUND wei=$reactiveFund"
    Write-Host "Sepolia balance wei=$sepoliaBal baseFee wei=$sepoliaBase gasCap wei=$sepoliaGasCap need wei=$sepoliaNeed"
    Write-Host "Lasna balance wei=$lasnaBal baseFee wei=$lasnaBase gasCap wei=$lasnaGasCap need wei=$lasnaNeed"
    Write-Host "Lasna gas cap does not include the lREACT stored in the new contract. Fee cap stays at 2x base fee."
    return @{
        SepoliaBalance = $sepoliaBal
        LasnaBalance   = $lasnaBal
        SepoliaNeed    = $sepoliaNeed
        LasnaNeed      = $lasnaNeed
        SepoliaBase    = $sepoliaBase
        LasnaBase      = $lasnaBase
    }
}

function Assert-SepoliaBalance($Live) {
    if ($Live.SepoliaBalance -lt $Live.SepoliaNeed) {
        Fail 'Sepolia balance is below the ledger fund plus deploy headroom. No transaction was sent.'
    }
}

function Assert-LasnaBalance($Live) {
    if ($Live.LasnaBalance -lt $Live.LasnaNeed) {
        $short = $Live.LasnaNeed - $Live.LasnaBalance
        Fail "Lasna balance is short by wei=$short. Need SPREAD_REACTIVE_FUND plus $LasnaReactiveGasCap gas at 2x base fee. No transaction was sent. Do not lower the fee cap below 2x base fee, and do not reuse the D5 contracts. The faucet 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 pays 100 lREACT per 1 Sepolia ETH."
    }
}

function Assert-Proxy {
    if (-not $env:CALLBACK_PROXY) { Fail 'CALLBACK_PROXY is empty.' }
    if (-not $env:CALLBACK_PROXY.Equals($ProxyDefault, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "CALLBACK_PROXY must be the Sepolia Omni proxy $ProxyDefault. An older proxy still has code but does not deliver."
    }
}

function Invoke-Preflight {
    Assert-Tool 'forge' | Out-Null
    Assert-Tool 'cast' | Out-Null
    if ([string]::IsNullOrWhiteSpace($Script:PrivateKey)) { Fail 'PRIVATE_KEY is missing from .env. The value was not printed.' }
    Write-Host 'PRIVATE_KEY: present'
    Assert-Proxy
    foreach ($name in @('SPREAD_AMM_ADDR', 'SPREAD_REACTIVE_ADDR', 'SPREAD_LEDGER_ADDR')) {
        $addr = Get-Address $name
        if ([string]::IsNullOrWhiteSpace($addr)) { Write-Host "${name}: empty" }
        else {
            Assert-NotOld $addr $name
            Write-Host "${name}: $addr"
        }
    }
    Write-Host 'Compiling and testing on cancun. This does not broadcast.'
    Invoke-Tool 'forge' @('test', '--match-path', 'test/SpreadPath.t.sol', '--evm-version', 'cancun', '-vv') | Out-Null
    Write-Host 'Running the callback gas test under Amsterdam. This does not broadcast and is not the deploy bytecode.'
    Invoke-Tool 'forge' @('test', '--match-path', 'test/SpreadPath.t.sol', '--evm-version', 'amsterdam', '--match-test', 'test_record_oneSlotAndUnderStipend', '-vv') | Out-Null
    Write-Host 'Rebuilding production artifacts with cancun.'
    Invoke-Tool 'forge' @('build', '--evm-version', 'cancun') | Out-Null
    $live = Get-LiveNeed
    Assert-SepoliaBalance $live
    Assert-LasnaBalance $live
    Write-Host 'preflight finished. No transaction was sent.'
}

function Invoke-DeployAmm {
    Assert-Proxy
    Assert-EmptyAddress 'SPREAD_AMM_ADDR'
    Assert-NoCreateReceipt '11155111' 'SimDualAmm'
    $live = Get-LiveNeed
    Assert-SepoliaBalance $live
    Invoke-Tool 'forge' @(
        'script', 'script/DeploySpread.s.sol:DeployAmm',
        '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
    ) | Out-Null
    Save-CreateFromBroadcast -ChainId '11155111' -ContractName 'SimDualAmm' -EnvName 'SPREAD_AMM_ADDR'
}

function Invoke-DeployReactive {
    Assert-SetAddress 'SPREAD_AMM_ADDR' | Out-Null
    Assert-EmptyAddress 'SPREAD_REACTIVE_ADDR'
    Assert-NoCreateReceipt '5318007' 'SpreadReactive'
    $live = Get-LiveNeed
    Assert-LasnaBalance $live
    Invoke-Tool 'forge' @(
        'script', 'script/DeploySpread.s.sol:DeployReactive',
        '--rpc-url', $env:LASNA_RPC_URL, '--broadcast', '--chain', '5318007', '--evm-version', 'cancun'
    ) | Out-Null
    Save-CreateFromBroadcast -ChainId '5318007' -ContractName 'SpreadReactive' -EnvName 'SPREAD_REACTIVE_ADDR'
}

function Invoke-DeployLedger {
    Assert-Proxy
    Assert-SetAddress 'SPREAD_REACTIVE_ADDR' | Out-Null
    Assert-EmptyAddress 'SPREAD_LEDGER_ADDR'
    Assert-NoCreateReceipt '11155111' 'OpportunityLedger'
    $live = Get-LiveNeed
    Assert-SepoliaBalance $live
    Invoke-Tool 'forge' @(
        'script', 'script/DeploySpread.s.sol:DeployLedger',
        '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
    ) | Out-Null
    Save-CreateFromBroadcast -ChainId '11155111' -ContractName 'OpportunityLedger' -EnvName 'SPREAD_LEDGER_ADDR'
}

function Invoke-Bind {
    $reactive = Assert-SetAddress 'SPREAD_REACTIVE_ADDR'
    $ledger = Assert-SetAddress 'SPREAD_LEDGER_ADDR'
    Assert-SetAddress 'SPREAD_AMM_ADDR' | Out-Null
    $recipient = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, 'recipient()(address)'))
    $subscribed = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, 'subscribed()(bool)'))
    if ($subscribed -eq 'true' -and $recipient.Equals($ledger, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "Already bound. recipient=$recipient subscribed=true. No transaction was sent."
    }
    Invoke-Tool 'forge' @(
        'script', 'script/DeploySpread.s.sol:SetRecipient',
        '--rpc-url', $env:LASNA_RPC_URL, '--broadcast', '--chain', '5318007', '--evm-version', 'cancun'
    ) | Out-Null
    $hash = Get-LastBroadcastHash '5318007'
    Write-Host "bind tx=$hash"
    Write-Host "https://lasna.reactscan.net/tx/$hash"
    Write-Host 'ReservesUpdated is now subscribed. Next: -Stage nudge. Do not nudge before this step.'
}

function Invoke-Nudge {
    $amm = Assert-SetAddress 'SPREAD_AMM_ADDR'
    $reactive = Assert-SetAddress 'SPREAD_REACTIVE_ADDR'
    Assert-SetAddress 'SPREAD_LEDGER_ADDR' | Out-Null
    $subscribed = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, 'subscribed()(bool)'))
    if ($subscribed -ne 'true') { Fail 'SpreadReactive is not subscribed. Run -Stage bind first. No nudge was sent.' }
    $teaching = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $amm, 'TEACHING_SIM()(bool)'))
    if ($teaching -ne 'true') { Fail 'SPREAD_AMM_ADDR is not the teaching-sim AMM. No nudge was sent.' }
    Invoke-Tool 'forge' @(
        'script', 'script/DeploySpread.s.sol:NudgeSpread',
        '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
    ) | Out-Null
    Write-Host 'Nudge transactions:'
    $printed = 0
    $latestNudge = Get-LatestBroadcast '11155111'
    if ($null -eq $latestNudge) { Fail 'nudge broadcast receipt was not found. .env was not changed.' }
    foreach ($found in @($latestNudge)) {
        foreach ($tx in @($found.Json.transactions)) {
            $hash = [string]$tx.hash
            $receipt = Get-ReceiptForHash $found.Json $hash
            if (-not (Test-ReceiptOk $receipt)) { Fail "nudge transaction $hash did not succeed." }
            Write-Host "tx=$hash"
            Write-Host "https://sepolia.etherscan.io/tx/$hash"
            $printed += 1
        }
    }
    if ($printed -lt 1) { Fail 'nudge broadcast receipt was not found. .env was not changed.' }
    Write-Host 'The second nudge is the source transaction for the homework path. Wait 10-60 seconds, then run -Stage verify.'
    Write-Host 'This script does not invent the Lasna react hash or the Sepolia callback hash. verify only reads chain state.'
}

function Get-LastBroadcastHash([string]$ChainId) {
    $latest = Get-LatestBroadcast $ChainId
    if ($null -eq $latest) { Fail 'broadcast receipt was not found.' }
    $tx = $null
    foreach ($item in @($latest.Json.transactions)) { $tx = $item }
    if ($null -eq $tx) { Fail 'broadcast receipt has no transaction.' }
    $hash = [string]$tx.hash
    $receipt = Get-ReceiptForHash $latest.Json $hash
    if (-not (Test-ReceiptOk $receipt)) { Fail "transaction $hash did not succeed." }
    return $hash
}

function Invoke-Verify {
    $amm = Assert-SetAddress 'SPREAD_AMM_ADDR'
    $reactive = Assert-SetAddress 'SPREAD_REACTIVE_ADDR'
    $ledger = Assert-SetAddress 'SPREAD_LEDGER_ADDR'
    Write-Host "Sepolia teaching-sim AMM $amm"
    foreach ($pool in @('1', '2')) {
        $value = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $amm, 'reserves(uint8)(uint112,uint112)', $pool))
        Write-Host "pool $pool reserves $value"
    }
    Write-Host "Lasna $reactive"
    foreach ($sig in @(
        'subscribed()(bool)', 'stopped()(bool)', 'remaining()(uint256)', 'requested()(uint256)',
        'recipient()(address)', 'lastSpreadBps()(uint256)', 'lastReactBlock()(uint256)',
        'quote1()(uint112,uint112,bool)', 'quote2()(uint112,uint112,bool)'
    )) {
        $value = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, $sig))
        Write-Host "$sig $value"
    }
    Write-Host ("balance lREACT " + (Get-CastValue (Invoke-Tool 'cast' @('balance', '--rpc-url', $env:LASNA_RPC_URL, $reactive, '-e'))))
    Write-Host ("debt " + (Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $System, 'debt(address)(uint256)', $reactive))))
    Write-Host "Sepolia ledger $ledger"
    foreach ($sig in @(
        'count()(uint256)', 'spreadBps()(uint256)', 'srcBlock()(uint256)',
        'price0E6()(uint256)', 'price1E6()(uint256)', 'cheapPoolId()(uint8)'
    )) {
        $value = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $ledger, $sig))
        Write-Host "$sig $value"
    }
    Write-Host ("balance ETH " + (Get-CastValue (Invoke-Tool 'cast' @('balance', '--rpc-url', $env:SEPOLIA_RPC_URL, $ledger, '-e'))))
    Write-Host ("proxy debt " + (Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $env:CALLBACK_PROXY, 'debt(address)(uint256)', $ledger))))
    $bn = Get-FirstInteger (Invoke-Tool 'cast' @('block-number', '--rpc-url', $env:SEPOLIA_RPC_URL))
    $from = $bn - 5000
    if ($from -lt 0) { $from = 0 }
    Invoke-Tool 'cast' @(
        'logs', '--rpc-url', $env:SEPOLIA_RPC_URL, '--from-block', ([string]$from),
        '--address', $ledger,
        'OpportunityRecorded(address indexed reactive, uint256 spreadBps, uint256 price0, uint256 price1, uint256 srcBlock, uint8 cheapPoolId, uint256 count)'
    ) | Out-Null
    Write-Host 'verify finished. No transaction was sent. Copy the three live hashes from the explorers after they exist. Do not invent them.'
}

function Invoke-PrepareRerun {
    $amm = Get-Address 'SPREAD_AMM_ADDR'
    $reactive = Get-Address 'SPREAD_REACTIVE_ADDR'
    $ledger = Get-Address 'SPREAD_LEDGER_ADDR'
    if ([string]::IsNullOrWhiteSpace($amm) -and [string]::IsNullOrWhiteSpace($reactive) -and [string]::IsNullOrWhiteSpace($ledger)) {
        Fail 'SPREAD_AMM_ADDR, SPREAD_REACTIVE_ADDR, and SPREAD_LEDGER_ADDR are already empty. Nothing was moved.'
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $src = Join-Path $Starter 'broadcast\DeploySpread.s.sol'
    if (Test-Path -LiteralPath $src) {
        $destRoot = Join-Path $Starter "broadcast\spread-archive\$stamp"
        if (Test-Path -LiteralPath $destRoot) { Fail "Archive folder already exists: $destRoot" }
        New-Item -ItemType Directory -Path $destRoot | Out-Null
        Move-Item -LiteralPath $src -Destination (Join-Path $destRoot 'DeploySpread.s.sol')
        Write-Host "Moved public receipts to broadcast\spread-archive\$stamp\DeploySpread.s.sol"
    } else {
        Write-Host 'No broadcast\DeploySpread.s.sol directory was present.'
    }
    foreach ($name in @('SPREAD_AMM_ADDR', 'SPREAD_REACTIVE_ADDR', 'SPREAD_LEDGER_ADDR')) {
        Write-LabEnvLine -Name $name -Value ''
    }
    Write-Host 'Cleared only the three SPREAD_ address lines. D5_ and ORIGIN/REACTIVE/CALLBACK lines were kept. cache was not read.'
}

Add-FoundryPath
Set-Location -LiteralPath $Starter
$parsedEnv = Read-DotEnv
Import-LabEnv $parsedEnv

switch ($Stage) {
    'preflight' { Invoke-Preflight }
    'prepareRerun' { Invoke-PrepareRerun }
    'deployAmm' { Invoke-DeployAmm }
    'deployReactive' { Invoke-DeployReactive }
    'deployLedger' { Invoke-DeployLedger }
    'bind' { Invoke-Bind }
    'nudge' { Invoke-Nudge }
    'verify' { Invoke-Verify }
}
