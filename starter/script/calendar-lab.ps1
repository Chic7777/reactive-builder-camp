# Love-Brain Clarity Calendar lab helper for Windows PowerShell 5.1.
# 恋爱脑清醒日历。只读 starter\.env，绝不打印 PRIVATE_KEY，不读 starter\cache。
# 只写 CALENDAR_* 行。不改 D5_*、SPREAD_*、SIGNAL_*，也不改 ORIGIN_ADDR / REACTIVE_ADDR / CALLBACK_ADDR。
# 本项目只需要一个钱包。
#
#   powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage preflight
#   powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage deployCalendar
#   powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage deployReactive
#   powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage bind
#   powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage demoPledge
#   powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage demoTouch
#   powershell -ExecutionPolicy Bypass -File .\script\calendar-lab.ps1 -Stage verify
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('preflight', 'prepareRerun', 'deployCalendar', 'deployReactive', 'bind', 'demoPledge', 'demoTouch', 'verify')]
    [string]$Stage
)

$ErrorActionPreference = 'Stop'
$Starter = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$EnvPath = Join-Path $Starter '.env'
$FoundryBin = 'C:\Users\laven\.foundry\bin'
$KnownTightWallet = '0x5576d42Fe13888b7f084190934abD07F061225fe'
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
$DefaultReactiveFund = [decimal]'50000000000000000'    # 0.05 ether
$DefaultCalendarFund = [decimal]'1000000000000000'     # 0.001 ether
$OneEther = [decimal]'1000000000000000000'
# CREATE gas ceilings for balance checks (Cancun + headroom). Not fee quotes.
$SepoliaCalendarGasCap = [decimal]1600000
$SepoliaBindGasCap = [decimal]200000
$SepoliaDemoGasCap = [decimal]400000
$LasnaReactiveGasCap = [decimal]2500000
$LasnaBindGasCap = [decimal]800000
$Script:PrivateKey = ''
$Script:EnvForbidden = @()
$Script:Sender = ''

function Fail([string]$Message) {
    Write-Host $Message
    exit 1
}

function Redact([string]$Text) {
    if ($null -eq $Text) { return '' }
    $safe = $Text
    if (-not [string]::IsNullOrWhiteSpace($Script:PrivateKey)) {
        $safe = $safe.Replace($Script:PrivateKey, '[redacted]')
        $bare = $Script:PrivateKey
        if ($bare.StartsWith('0x') -or $bare.StartsWith('0X')) { $bare = $bare.Substring(2) }
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
    Fail "$Name must be an integer wei value, or a decimal followed by ' ether'. Example: 1000000000000000 or 0.001 ether."
}

function Test-KeyShape([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $bare = $Value.Trim()
    if ($bare.StartsWith('0x') -or $bare.StartsWith('0X')) { $bare = $bare.Substring(2) }
    return $bare -match '^[0-9a-fA-F]{64}$'
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

function Write-LabEnvLine {
    param([string]$Name, [string]$Value)
    $allowed = @(
        'CALENDAR_ADDR', 'CALENDAR_REACTIVE_ADDR',
        'CALENDAR_FUND', 'CALENDAR_REACTIVE_FUND',
        'CALENDAR_WINDOW', 'CALENDAR_CRON_CAP', 'CALENDAR_DEMO_THREAD_ID'
    )
    if ($allowed -notcontains $Name) {
        Fail 'Refusing to write any .env key other than the CALENDAR_ lines.'
    }
    if ($Name -like '*ADDR' -and -not [string]::IsNullOrWhiteSpace($Value)) { Assert-NotOld $Value $Name }
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
    if (-not $env:CALENDAR_REACTIVE_FUND) { $env:CALENDAR_REACTIVE_FUND = [string]$DefaultReactiveFund }
    if (-not $env:CALENDAR_FUND) { $env:CALENDAR_FUND = [string]$DefaultCalendarFund }
    if (-not $env:CALENDAR_WINDOW) { $env:CALENDAR_WINDOW = '300' }
    if (-not $env:CALENDAR_CRON_CAP) { $env:CALENDAR_CRON_CAP = '8' }
    $env:CALENDAR_REACTIVE_FUND = [string](Convert-ToWei 'CALENDAR_REACTIVE_FUND' $env:CALENDAR_REACTIVE_FUND)
    $env:CALENDAR_FUND = [string](Convert-ToWei 'CALENDAR_FUND' $env:CALENDAR_FUND)
    foreach ($name in @('CALENDAR_REACTIVE_FUND', 'CALENDAR_FUND', 'CALENDAR_WINDOW', 'CALENDAR_CRON_CAP')) {
        $fromFile = ''
        if ($Parsed.Map.ContainsKey($name)) { $fromFile = $Parsed.Map[$name].Trim() }
        $current = (Get-Item "Env:$name").Value
        if ($fromFile -ne $current) {
            Write-LabEnvLine -Name $name -Value $current
        }
    }
    foreach ($name in @('CALENDAR_ADDR', 'CALENDAR_REACTIVE_ADDR', 'CALENDAR_DEMO_THREAD_ID')) {
        $fromFile = ''
        if ($Parsed.Map.ContainsKey($name)) { $fromFile = $Parsed.Map[$name].Trim() }
        if ([string]::IsNullOrWhiteSpace($fromFile)) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
    }
    $otherLabs = @(
        'ORIGIN_ADDR', 'REACTIVE_ADDR', 'CALLBACK_ADDR',
        'D5_REACTIVE_ADDR', 'D5_CALLBACK_ADDR', 'D5_FAILED_REACTIVE_ADDR', 'D5_FAILED_CALLBACK_ADDR',
        'SPREAD_AMM_ADDR', 'SPREAD_REACTIVE_ADDR', 'SPREAD_LEDGER_ADDR',
        'SIGNAL_BOARD_ADDR', 'SIGNAL_REACTIVE_ADDR', 'SIGNAL_LEDGER_ADDR'
    )
    $Script:EnvForbidden = @()
    foreach ($name in $otherLabs) {
        if ($Parsed.Map.ContainsKey($name) -and -not [string]::IsNullOrWhiteSpace($Parsed.Map[$name])) {
            $Script:EnvForbidden += $Parsed.Map[$name].Trim()
        } else {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
    }
    Assert-CalendarConfig
}

function Assert-CalendarConfig {
    $window = [decimal]$env:CALENDAR_WINDOW
    $cap = [decimal]$env:CALENDAR_CRON_CAP
    if ($window -ne [decimal]::Floor($window) -or $window -lt 1) {
        Fail 'CALENDAR_WINDOW must be a positive whole number of seconds. Demo recording default is 300 (5 minutes). Real-life docs suggest about 3 days (259200).'
    }
    if ($cap -ne [decimal]::Floor($cap) -or $cap -lt 1 -or $cap -gt 32) {
        Fail 'CALENDAR_CRON_CAP must be a whole number from 1 to 32.'
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
            Fail "$Name matches a SIGNAL_/SPREAD_/D5_/ORIGIN_ADDR/REACTIVE_ADDR/CALLBACK_ADDR already in .env. This path does not reuse those contracts."
        }
    }
}

function Assert-EmptyAddress([string]$Name) {
    $addr = Get-Address $Name
    if (-not [string]::IsNullOrWhiteSpace($addr)) {
        Fail "$Name is already $addr. This stage stopped and did not send a transaction. Delete only that CALENDAR_ line if you really intend to deploy again."
    }
}

function Assert-SetAddress([string]$Name) {
    $addr = Get-Address $Name
    if ([string]::IsNullOrWhiteSpace($addr)) { Fail "$Name is empty. Run the previous stage first." }
    if ($addr -notmatch '^0x[0-9a-fA-F]{40}$') { Fail "$Name is not a 20-byte address." }
    Assert-NotOld $addr $Name
    return $addr
}

function Get-BroadcastDir([string]$ChainId) {
    $path = Join-Path $Starter "broadcast\DeployCalendar.s.sol\$ChainId"
    if ($path -match 'cache') { Fail 'Refusing to read cache.' }
    return $path
}

function Read-BroadcastFiles([string]$ChainId) {
    $dir = Get-BroadcastDir $ChainId
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter 'run-*.json' -File)) {
        $json = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
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
            if ($type -eq 'CREATE' -and $name -eq $ContractName) {
                $hash = [string]$tx.hash
                $receipt = Get-ReceiptForHash $found.Json $hash
                $addr = [string]$tx.contractAddress
                Write-Host "Found existing CREATE receipt. address=$addr tx=$hash statusOk=$(Test-ReceiptOk $receipt)"
                Fail "deploy did not start. Existing broadcast was not ignored and .env was not changed. If this receipt is the contract you want, copy the address into the CALENDAR_ line yourself. If it failed, run -Stage prepareRerun or move broadcast\DeployCalendar.s.sol\$ChainId aside."
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
    $hash = [string]$chosen.hash
    $receipt = Get-ReceiptForHash $found.Json $hash
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

function Get-MaxFee([decimal]$BaseFee) {
    return ($BaseFee * 2) + 1
}

function Get-Sender {
    $output = Invoke-Tool 'forge' @('script', 'script/DeployCalendar.s.sol:ShowSender', '--evm-version', 'cancun')
    $first = [regex]::Match($output, 'sender:?\s*(0x[0-9a-fA-F]{40})')
    if (-not $first.Success) { Fail 'Could not derive sender. The private key was not printed. No transaction was sent.' }
    $Script:Sender = $first.Groups[1].Value
}

function Get-LiveNeed {
    $sepoliaBase = Get-FirstInteger (Invoke-Tool 'cast' @('base-fee', '--rpc-url', $env:SEPOLIA_RPC_URL))
    $lasnaBase = Get-FirstInteger (Invoke-Tool 'cast' @('base-fee', '--rpc-url', $env:LASNA_RPC_URL))
    $sepoliaBal = Get-FirstInteger (Invoke-Tool 'cast' @('balance', $Script:Sender, '--rpc-url', $env:SEPOLIA_RPC_URL))
    $lasnaBal = Get-FirstInteger (Invoke-Tool 'cast' @('balance', $Script:Sender, '--rpc-url', $env:LASNA_RPC_URL))
    $calendarFund = [decimal]$env:CALENDAR_FUND
    $reactiveFund = [decimal]$env:CALENDAR_REACTIVE_FUND
    $sepoliaPrice = $sepoliaBase * 2
    $oneGwei = [decimal]'1000000000'
    if ($sepoliaPrice -lt $oneGwei) { $sepoliaPrice = $oneGwei }
    $sepoliaGasUnits = $SepoliaCalendarGasCap + $SepoliaBindGasCap + $SepoliaDemoGasCap
    $sepoliaGasCap = $sepoliaGasUnits * $sepoliaPrice
    $sepoliaNeed = $calendarFund + $sepoliaGasCap
    $lasnaMaxFee = Get-MaxFee $lasnaBase
    $lasnaGasUnits = $LasnaReactiveGasCap + $LasnaBindGasCap
    $lasnaGasCap = $lasnaGasUnits * $lasnaMaxFee
    $lasnaNeed = $reactiveFund + $lasnaGasCap
    Write-Host "Wallet $Script:Sender"
    if ($Script:Sender.Equals($KnownTightWallet, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host 'This is the known test wallet. Keep CALENDAR_REACTIVE_FUND low (default 0.05 lREACT) and CALENDAR_FUND at 0.001 ETH.'
    }
    Write-Host "CALENDAR_FUND wei=$calendarFund"
    Write-Host "CALENDAR_REACTIVE_FUND wei=$reactiveFund"
    Write-Host "CALENDAR_WINDOW seconds=$($env:CALENDAR_WINDOW)"
    Write-Host "CALENDAR_CRON_CAP=$($env:CALENDAR_CRON_CAP)"
    Write-Host "Sepolia balance wei=$sepoliaBal baseFee wei=$sepoliaBase gasCap wei=$sepoliaGasCap need wei=$sepoliaNeed"
    Write-Host "Lasna balance wei=$lasnaBal baseFee wei=$lasnaBase gasCap wei=$lasnaGasCap need wei=$lasnaNeed"
    Write-Host 'One wallet is enough for this project. Diary text never leaves the browser.'
    return @{
        SepoliaBalance = $sepoliaBal
        LasnaBalance   = $lasnaBal
        SepoliaNeed    = $sepoliaNeed
        LasnaNeed      = $lasnaNeed
    }
}

function Assert-SepoliaBalance($Live) {
    if ($Live.SepoliaBalance -lt $Live.SepoliaNeed) {
        Fail 'Sepolia balance is below the calendar fund plus deploy/demo headroom. No transaction was sent.'
    }
}

function Assert-LasnaBalance($Live) {
    if ($Live.LasnaBalance -lt $Live.LasnaNeed) {
        $short = $Live.LasnaNeed - $Live.LasnaBalance
        Fail "Lasna balance is short by wei=$short. Need CALENDAR_REACTIVE_FUND plus deploy and bind gas at 2x base fee. No transaction was sent. Do not take lREACT out of D5/SIGNAL/SPREAD contracts. Faucet 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 pays 100 lREACT per 1 Sepolia ETH. See docs/cheatsheet.md."
    }
}

function Assert-Proxy {
    if (-not $env:CALLBACK_PROXY) { Fail 'CALLBACK_PROXY is empty.' }
    if (-not $env:CALLBACK_PROXY.Equals($ProxyDefault, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "CALLBACK_PROXY must be the Sepolia Omni proxy $ProxyDefault."
    }
}

function Assert-Chains {
    if ($env:ORIGIN_CHAIN_ID -ne '11155111' -or $env:DEST_CHAIN_ID -ne '11155111') {
        Fail 'This path uses Ethereum Sepolia 11155111 for both source and destination. Reactive stays on Lasna 5318007.'
    }
}

function Assert-Key {
    if ([string]::IsNullOrWhiteSpace($Script:PrivateKey)) { Fail 'PRIVATE_KEY is missing from .env. The value was not printed.' }
    if (-not (Test-KeyShape $Script:PrivateKey)) { Fail 'PRIVATE_KEY is not a 32-byte hex key. The value was not printed.' }
    Write-Host 'PRIVATE_KEY: present (one wallet is enough)'
}

function Invoke-Preflight {
    Assert-Tool 'forge' | Out-Null
    Assert-Tool 'cast' | Out-Null
    Assert-Key
    Assert-Chains
    Assert-Proxy
    foreach ($name in @('CALENDAR_ADDR', 'CALENDAR_REACTIVE_ADDR')) {
        $addr = Get-Address $name
        if ([string]::IsNullOrWhiteSpace($addr)) { Write-Host "${name}: empty" }
        else {
            Assert-NotOld $addr $name
            Write-Host "${name}: $addr"
        }
    }
    Get-Sender
    Write-Host 'Compiling and testing on cancun. This does not broadcast.'
    Invoke-Tool 'forge' @('test', '--match-path', 'test/CalendarPath.t.sol', '--evm-version', 'cancun', '-vv') | Out-Null
    Write-Host 'Running markReleased gas check under Amsterdam (not deploy bytecode).'
    Invoke-Tool 'forge' @('test', '--match-path', 'test/CalendarPath.t.sol', '--evm-version', 'amsterdam', '--match-test', 'test_markReleased_oneSlotAndUnderStipend', '-vv') | Out-Null
    Write-Host 'Rebuilding production artifacts with cancun.'
    Invoke-Tool 'forge' @('build', '--evm-version', 'cancun') | Out-Null
    $live = Get-LiveNeed
    Assert-SepoliaBalance $live
    Assert-LasnaBalance $live
    Write-Host 'Homework txs after deploy: Sepolia pledge/touch (source), Lasna react, Sepolia ThreadReleased callback. Do not invent hashes.'
    Write-Host 'preflight finished. No transaction was sent.'
}

function Invoke-DeployCalendar {
    Assert-Proxy
    Assert-Chains
    Assert-EmptyAddress 'CALENDAR_ADDR'
    Assert-NoCreateReceipt '11155111' 'ClarityCalendar'
    Get-Sender
    $live = Get-LiveNeed
    Assert-SepoliaBalance $live
    Assert-LasnaBalance $live
    Invoke-Tool 'forge' @(
        'script', 'script/DeployCalendar.s.sol:DeployCalendar',
        '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
    ) | Out-Null
    Save-CreateFromBroadcast -ChainId '11155111' -ContractName 'ClarityCalendar' -EnvName 'CALENDAR_ADDR'
}

function Invoke-DeployReactive {
    Assert-Chains
    Assert-SetAddress 'CALENDAR_ADDR' | Out-Null
    Assert-EmptyAddress 'CALENDAR_REACTIVE_ADDR'
    Assert-NoCreateReceipt '5318007' 'ClarityReactive'
    Get-Sender
    $live = Get-LiveNeed
    Assert-LasnaBalance $live
    Invoke-Tool 'forge' @(
        'script', 'script/DeployCalendar.s.sol:DeployCalendarReactive',
        '--rpc-url', $env:LASNA_RPC_URL, '--broadcast', '--chain', '5318007', '--evm-version', 'cancun'
    ) | Out-Null
    Save-CreateFromBroadcast -ChainId '5318007' -ContractName 'ClarityReactive' -EnvName 'CALENDAR_REACTIVE_ADDR'
}

function Invoke-Bind {
    $calendar = Assert-SetAddress 'CALENDAR_ADDR'
    $reactive = Assert-SetAddress 'CALENDAR_REACTIVE_ADDR'
    Get-Sender
    $live = Get-LiveNeed
    Assert-SepoliaBalance $live
    Assert-LasnaBalance $live
    $bound = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $calendar, 'reactive()(address)'))
    if ($bound.Equals($reactive, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host 'Sepolia calendar already bound to this reactive.'
    } else {
        Invoke-Tool 'forge' @(
            'script', 'script/DeployCalendar.s.sol:BindCalendarOnSepolia',
            '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
        ) | Out-Null
        Write-Host ("sepolia bind tx=" + (Get-LastBroadcastHash '11155111'))
    }
    $subscribed = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, 'subscribedEvents()(bool)'))
    $recipient = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, 'recipient()(address)'))
    if ($subscribed -eq 'true' -and $recipient.Equals($calendar, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host 'Lasna reactive already subscribed to this calendar.'
    } else {
        Invoke-Tool 'forge' @(
            'script', 'script/DeployCalendar.s.sol:BindCalendarOnLasna',
            '--rpc-url', $env:LASNA_RPC_URL, '--broadcast', '--chain', '5318007', '--evm-version', 'cancun'
        ) | Out-Null
        Write-Host ("lasna bind tx=" + (Get-LastBroadcastHash '5318007'))
    }
    Write-Host 'Bound. Next: -Stage demoPledge (source tx), wait for window, then -Stage verify for ThreadReleased.'
}

function Invoke-DemoPledge {
    $calendar = Assert-SetAddress 'CALENDAR_ADDR'
    Assert-SetAddress 'CALENDAR_REACTIVE_ADDR' | Out-Null
    $demo = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $calendar, 'CLARITY_DEMO()(bool)'))
    if ($demo -ne 'true') { Fail 'CALENDAR_ADDR is not the clarity calendar. No transaction was sent.' }
    $bound = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $calendar, 'reactive()(address)'))
    if ($bound -match '^0x0{40}$') { Fail 'Reactive is not bound. Run -Stage bind first.' }
    Get-Sender
    Invoke-Tool 'forge' @(
        'script', 'script/DeployCalendar.s.sol:DemoPledge',
        '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
    ) | Out-Null
    $hash = Get-LastBroadcastHash '11155111'
    Write-Host "demoPledge tx=$hash"
    Write-Host "https://sepolia.etherscan.io/tx/$hash"
    Write-Host 'This open+pledge is a homework source transaction. Copy CALENDAR_DEMO_THREAD_ID from the forge log (threadId) if you want demoTouch later.'
    Write-Host 'This script does not invent the Lasna react hash or the Sepolia callback hash.'
}

function Invoke-DemoTouch {
    Assert-SetAddress 'CALENDAR_ADDR' | Out-Null
    $tid = Get-Address 'CALENDAR_DEMO_THREAD_ID'
    if ([string]::IsNullOrWhiteSpace($tid)) { Fail 'CALENDAR_DEMO_THREAD_ID is empty. Set it to the threadId from demoPledge.' }
    Get-Sender
    Invoke-Tool 'forge' @(
        'script', 'script/DeployCalendar.s.sol:DemoTouch',
        '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
    ) | Out-Null
    $hash = Get-LastBroadcastHash '11155111'
    Write-Host "demoTouch tx=$hash"
    Write-Host "https://sepolia.etherscan.io/tx/$hash"
    Write-Host 'Touch resets the waiting window for that thread.'
}

function Invoke-Verify {
    $calendar = Assert-SetAddress 'CALENDAR_ADDR'
    $reactive = Assert-SetAddress 'CALENDAR_REACTIVE_ADDR'
    Write-Host "Sepolia calendar $calendar"
    Write-Host ("CLARITY_DEMO " + (Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $calendar, 'CLARITY_DEMO()(bool)'))))
    Write-Host ("reactive bound " + (Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $calendar, 'reactive()(address)'))))
    Write-Host "Lasna $reactive"
    foreach ($sig in @(
        'subscribedEvents()(bool)', 'subscribedCron()(bool)', 'stopped()(bool)',
        'recipient()(address)', 'WINDOW()(uint256)', 'CRON_CAP()(uint256)',
        'pendingCount()(uint256)', 'lastReactBlock()(uint256)', 'lastCronNumber()(uint256)'
    )) {
        $value = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, $sig))
        Write-Host "$sig $value"
    }
    Write-Host ("balance lREACT " + (Get-CastValue (Invoke-Tool 'cast' @('balance', '--rpc-url', $env:LASNA_RPC_URL, $reactive, '-e'))))
    Write-Host ("debt " + (Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $System, 'debt(address)(uint256)', $reactive))))
    Write-Host ("calendar ETH " + (Get-CastValue (Invoke-Tool 'cast' @('balance', '--rpc-url', $env:SEPOLIA_RPC_URL, $calendar, '-e'))))
    Write-Host ("proxy debt " + (Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $env:CALLBACK_PROXY, 'debt(address)(uint256)', $calendar))))
    $bn = Get-FirstInteger (Invoke-Tool 'cast' @('block-number', '--rpc-url', $env:SEPOLIA_RPC_URL))
    $from = $bn - 50000
    if ($from -lt 0) { $from = 0 }
    Invoke-Tool 'cast' @(
        'logs', '--rpc-url', $env:SEPOLIA_RPC_URL, '--from-block', ([string]$from),
        '--address', $calendar,
        'ThreadReleased(address indexed reactive, address indexed user, uint256 indexed threadId, uint256 timestamp)'
    ) | Out-Null
    Write-Host 'verify finished. No transaction was sent.'
    Write-Host 'Copy three live hashes after they exist: Sepolia pledge/touch, Lasna react, Sepolia ThreadReleased. Do not invent them.'
    Write-Host 'Diary text stays in app/ localStorage only.'
}

function Invoke-PrepareRerun {
    $calendar = Get-Address 'CALENDAR_ADDR'
    $reactive = Get-Address 'CALENDAR_REACTIVE_ADDR'
    if ([string]::IsNullOrWhiteSpace($calendar) -and [string]::IsNullOrWhiteSpace($reactive)) {
        Fail 'CALENDAR_ADDR and CALENDAR_REACTIVE_ADDR are already empty. Nothing was moved.'
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $src = Join-Path $Starter 'broadcast\DeployCalendar.s.sol'
    if (Test-Path -LiteralPath $src) {
        $destRoot = Join-Path $Starter "broadcast\calendar-archive\$stamp"
        if (Test-Path -LiteralPath $destRoot) { Fail "Archive folder already exists: $destRoot" }
        New-Item -ItemType Directory -Path $destRoot | Out-Null
        Move-Item -LiteralPath $src -Destination (Join-Path $destRoot 'DeployCalendar.s.sol')
        Write-Host "Moved public receipts to broadcast\calendar-archive\$stamp\DeployCalendar.s.sol"
    } else {
        Write-Host 'No broadcast\DeployCalendar.s.sol directory was present.'
    }
    foreach ($name in @('CALENDAR_ADDR', 'CALENDAR_REACTIVE_ADDR', 'CALENDAR_DEMO_THREAD_ID')) {
        Write-LabEnvLine -Name $name -Value ''
    }
    Write-Host 'Cleared only the CALENDAR_ address lines. Other lab lines were kept. cache was not read.'
}

Add-FoundryPath
Set-Location -LiteralPath $Starter
$parsedEnv = Read-DotEnv
Import-LabEnv $parsedEnv

switch ($Stage) {
    'preflight' { Invoke-Preflight }
    'prepareRerun' { Invoke-PrepareRerun }
    'deployCalendar' { Invoke-DeployCalendar }
    'deployReactive' { Invoke-DeployReactive }
    'bind' { Invoke-Bind }
    'demoPledge' { Invoke-DemoPledge }
    'demoTouch' { Invoke-DemoTouch }
    'verify' { Invoke-Verify }
}
