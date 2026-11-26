# Mutual Signal Record lab helper for Windows PowerShell 5.1.
# 双向小信号唱片。只读 starter\.env，绝不打印 PRIVATE_KEY 或 PRIVATE_KEY_2，不读 starter\cache。
# 只写 SIGNAL_* 行。不改 D5_*、SPREAD_*，也不改 ORIGIN_ADDR / REACTIVE_ADDR / CALLBACK_ADDR。
#
# 两个人必须是两个地址。同一个钱包挥两次不会相遇。
# 单元测试用 vm.prank 模拟两个地址。这条脚本不生成私钥。
# 第二下信号需要 starter\.env 里已有的 PRIVATE_KEY_2（gitignored）。没有它时，waveB 会停下来并说明该怎么做。
#
#   powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage preflight
#   powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage deployBoard
#   powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage deployReactive
#   powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage deployLedger
#   powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage bind
#   powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage waveA
#   powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage waveB
#   powershell -ExecutionPolicy Bypass -File .\script\signal-lab.ps1 -Stage verify
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('preflight', 'prepareRerun', 'deployBoard', 'deployReactive', 'deployLedger', 'bind', 'waveA', 'waveB', 'verify')]
    [string]$Stage
)

$ErrorActionPreference = 'Stop'
$Starter = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$EnvPath = Join-Path $Starter '.env'
$FoundryBin = 'C:\Users\laven\.foundry\bin'
# 2026-11-25 只读过的测试钱包。余额紧的是 Lasna，不是 Sepolia。脚本仍以 PRIVATE_KEY 推出的地址为准。
$KnownTightWallet = '0x5576d42Fe13888b7f084190934abD07F061225fe'
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
# keccak256("mutual-signal")。网页和这条脚本用同一个房间号。不是名字，也不是一句留言。
$DefaultPairId = '0x23365b7b7f9f4867a6d0a355957e84dec93920a11d04b48ab7789415b30b55b6'
$DefaultReactiveFund = [decimal]'100000000000000000'   # 0.10 ether, wei
$DefaultLedgerFund = [decimal]'2000000000000000'       # 0.002 ether, wei
$OneEther = [decimal]'1000000000000000000'
# CREATE gas measured 2026-11-25 on Cancun, plus 21000, plus 16 gas per init-code byte,
# then forge's 130% estimate multiplier. The cap is the balance check, not a lower fee.
# SignalBoard create 144555 / init 287 bytes -> about 221191, cap 400000.
# EncounterLedger create 498140 / init 2435 bytes -> about 725530, cap 900000.
# SignalReactive create 1422481 / init 6999 bytes -> about 2022105, cap 2200000.
# setRecipient calls SYSTEM.subscribe. 600000 is a ceiling for the balance check, not a measured Lasna trace.
# waveA is one sendSignal from the main wallet. waveB is paid by the second address.
$SepoliaBoardGasCap = [decimal]400000
$SepoliaLedgerGasCap = [decimal]900000
$SepoliaWaveGasCap = [decimal]200000
$LasnaReactiveGasCap = [decimal]2200000
$LasnaBindGasCap = [decimal]600000
$Script:PrivateKey = ''
$Script:PrivateKey2 = ''
$Script:EnvForbidden = @()
$Script:Sender1 = ''
$Script:Sender2 = ''

function Fail([string]$Message) {
    Write-Host $Message
    exit 1
}

function Redact([string]$Text) {
    if ($null -eq $Text) { return '' }
    $safe = $Text
    foreach ($secret in @($Script:PrivateKey, $Script:PrivateKey2)) {
        if ([string]::IsNullOrWhiteSpace($secret)) { continue }
        $safe = $safe.Replace($secret, '[redacted]')
        $bare = $secret
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
    Fail "$Name must be an integer wei value, or a decimal followed by ' ether'. Example: 2000000000000000 or 0.002 ether. Do not leave a bare decimal."
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

function Import-LabEnv($Parsed) {
    foreach ($name in $Parsed.Map.Keys) {
        Set-Item -Path "Env:$name" -Value $Parsed.Map[$name]
    }
    if ($Parsed.Map.ContainsKey('PRIVATE_KEY')) { $Script:PrivateKey = $Parsed.Map['PRIVATE_KEY'] }
    if ($Parsed.Map.ContainsKey('PRIVATE_KEY_2')) { $Script:PrivateKey2 = $Parsed.Map['PRIVATE_KEY_2'] }
    if (-not $env:SEPOLIA_RPC_URL) { $env:SEPOLIA_RPC_URL = 'https://ethereum-sepolia-rpc.publicnode.com' }
    if (-not $env:LASNA_RPC_URL) { $env:LASNA_RPC_URL = 'https://lasna-rpc.rnk.dev/' }
    if (-not $env:ORIGIN_CHAIN_ID) { $env:ORIGIN_CHAIN_ID = '11155111' }
    if (-not $env:DEST_CHAIN_ID) { $env:DEST_CHAIN_ID = '11155111' }
    if (-not $env:CALLBACK_PROXY) { $env:CALLBACK_PROXY = $ProxyDefault }
    if (-not $env:SIGNAL_REACTIVE_FUND) { $env:SIGNAL_REACTIVE_FUND = [string]$DefaultReactiveFund }
    if (-not $env:SIGNAL_LEDGER_FUND) { $env:SIGNAL_LEDGER_FUND = [string]$DefaultLedgerFund }
    if (-not $env:SIGNAL_WINDOW) { $env:SIGNAL_WINDOW = '3600' }
    if (-not $env:SIGNAL_MAX_ENCOUNTERS) { $env:SIGNAL_MAX_ENCOUNTERS = '3' }
    if (-not $env:SIGNAL_PAIR_ID) { $env:SIGNAL_PAIR_ID = $DefaultPairId }
    $env:SIGNAL_REACTIVE_FUND = [string](Convert-ToWei 'SIGNAL_REACTIVE_FUND' $env:SIGNAL_REACTIVE_FUND)
    $env:SIGNAL_LEDGER_FUND = [string](Convert-ToWei 'SIGNAL_LEDGER_FUND' $env:SIGNAL_LEDGER_FUND)
    foreach ($name in @('SIGNAL_REACTIVE_FUND', 'SIGNAL_LEDGER_FUND', 'SIGNAL_WINDOW', 'SIGNAL_MAX_ENCOUNTERS', 'SIGNAL_PAIR_ID')) {
        $fromFile = ''
        if ($Parsed.Map.ContainsKey($name)) { $fromFile = $Parsed.Map[$name].Trim() }
        $current = (Get-Item "Env:$name").Value
        if ($fromFile -ne $current) {
            # Foundry 读到 "0.002 ether" 这种带空格的值会把整份 .env 丢掉。缺省值也写进 SIGNAL_ 行，方便之后查看。
            Write-LabEnvLine -Name $name -Value $current
        }
    }
    foreach ($name in @('SIGNAL_BOARD_ADDR', 'SIGNAL_REACTIVE_ADDR', 'SIGNAL_LEDGER_ADDR')) {
        $fromFile = ''
        if ($Parsed.Map.ContainsKey($name)) { $fromFile = $Parsed.Map[$name].Trim() }
        if ([string]::IsNullOrWhiteSpace($fromFile)) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
    }
    $otherLabs = @(
        'ORIGIN_ADDR', 'REACTIVE_ADDR', 'CALLBACK_ADDR',
        'D5_REACTIVE_ADDR', 'D5_CALLBACK_ADDR', 'D5_FAILED_REACTIVE_ADDR', 'D5_FAILED_CALLBACK_ADDR',
        'SPREAD_AMM_ADDR', 'SPREAD_REACTIVE_ADDR', 'SPREAD_LEDGER_ADDR'
    )
    $Script:EnvForbidden = @()
    foreach ($name in $otherLabs) {
        if ($Parsed.Map.ContainsKey($name) -and -not [string]::IsNullOrWhiteSpace($Parsed.Map[$name])) {
            $Script:EnvForbidden += $Parsed.Map[$name].Trim()
        } else {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
    }
    if (Test-KeyShape $Script:PrivateKey2) {
        $env:SIGNAL_HAS_KEY2 = '1'
    } else {
        $env:SIGNAL_HAS_KEY2 = '0'
        if (-not [string]::IsNullOrWhiteSpace($Script:PrivateKey2)) {
            Fail 'PRIVATE_KEY_2 is set but is not a 32-byte hex key. The value was not printed.'
        }
        Remove-Item -Path 'Env:PRIVATE_KEY_2' -ErrorAction SilentlyContinue
    }
    Assert-SignalConfig
}

function Assert-SignalConfig {
    $window = [decimal]$env:SIGNAL_WINDOW
    $max = [decimal]$env:SIGNAL_MAX_ENCOUNTERS
    if ($window -ne [decimal]::Floor($window) -or $window -lt 1) {
        Fail 'SIGNAL_WINDOW must be a positive whole number of seconds.'
    }
    if ($max -ne [decimal]::Floor($max) -or $max -lt 1 -or $max -gt 5) {
        Fail 'SIGNAL_MAX_ENCOUNTERS must be a whole number from 1 to 5. The ledger refuses anything above 5.'
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
            Fail "$Name matches a SPREAD_, D5_, ORIGIN_ADDR, REACTIVE_ADDR, or CALLBACK_ADDR already in .env. This path does not reuse those contracts."
        }
    }
}

function Assert-EmptyAddress([string]$Name) {
    $addr = Get-Address $Name
    if (-not [string]::IsNullOrWhiteSpace($addr)) {
        Fail "$Name is already $addr. This stage stopped and did not send a transaction. Delete only that SIGNAL_ line if you really intend to deploy again."
    }
}

function Assert-SetAddress([string]$Name) {
    $addr = Get-Address $Name
    if ([string]::IsNullOrWhiteSpace($addr)) { Fail "$Name is empty. Run the previous stage first." }
    if ($addr -notmatch '^0x[0-9a-fA-F]{40}$') { Fail "$Name is not a 20-byte address." }
    Assert-NotOld $addr $Name
    return $addr
}

function Assert-PairId {
    $pair = Get-Address 'SIGNAL_PAIR_ID'
    if ($pair -notmatch '^0x[0-9a-fA-F]{64}$') {
        Fail 'SIGNAL_PAIR_ID must be a 32-byte hex value. The default is keccak256("mutual-signal").'
    }
    if ($pair -eq '0x0000000000000000000000000000000000000000000000000000000000000000') {
        Fail 'SIGNAL_PAIR_ID must not be zero.'
    }
    return $pair
}

function Write-LabEnvLine {
    param([string]$Name, [string]$Value)
    $allowed = @(
        'SIGNAL_BOARD_ADDR', 'SIGNAL_REACTIVE_ADDR', 'SIGNAL_LEDGER_ADDR',
        'SIGNAL_REACTIVE_FUND', 'SIGNAL_LEDGER_FUND',
        'SIGNAL_WINDOW', 'SIGNAL_MAX_ENCOUNTERS', 'SIGNAL_PAIR_ID'
    )
    if ($allowed -notcontains $Name) {
        Fail 'Refusing to write any .env key other than the SIGNAL_ lines.'
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
    $path = Join-Path $Starter "broadcast\DeploySignal.s.sol\$ChainId"
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
                Fail "deploy did not start. Existing broadcast was not ignored and .env was not changed. If this receipt is the contract you want, copy the address into the SIGNAL_ line yourself. If it failed, run -Stage prepareRerun or move broadcast\DeploySignal.s.sol\$ChainId aside."
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

function Get-Senders {
    $output = Invoke-Tool 'forge' @('script', 'script/DeploySignal.s.sol:ShowSenders', '--evm-version', 'cancun')
    $first = [regex]::Match($output, 'sender1:?\s*(0x[0-9a-fA-F]{40})')
    $second = [regex]::Match($output, 'sender2:?\s*(0x[0-9a-fA-F]{40})')
    if (-not $first.Success) { Fail 'Could not derive sender1. The private key was not printed. No transaction was sent.' }
    $Script:Sender1 = $first.Groups[1].Value
    if ($second.Success -and -not $second.Groups[1].Value.Equals('0x0000000000000000000000000000000000000000', [System.StringComparison]::OrdinalIgnoreCase)) {
        $Script:Sender2 = $second.Groups[1].Value
    } else {
        $Script:Sender2 = ''
    }
    if ($Script:Sender2 -and $Script:Sender1.Equals($Script:Sender2, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail 'PRIVATE_KEY_2 derives the same address as PRIVATE_KEY. The second signal must be a different account. No transaction was sent.'
    }
}

function Get-LiveNeed {
    $sepoliaBase = Get-FirstInteger (Invoke-Tool 'cast' @('base-fee', '--rpc-url', $env:SEPOLIA_RPC_URL))
    $lasnaBase = Get-FirstInteger (Invoke-Tool 'cast' @('base-fee', '--rpc-url', $env:LASNA_RPC_URL))
    $sepoliaBal = Get-FirstInteger (Invoke-Tool 'cast' @('balance', $Script:Sender1, '--rpc-url', $env:SEPOLIA_RPC_URL))
    $lasnaBal = Get-FirstInteger (Invoke-Tool 'cast' @('balance', $Script:Sender1, '--rpc-url', $env:LASNA_RPC_URL))
    $ledgerFund = [decimal]$env:SIGNAL_LEDGER_FUND
    $reactiveFund = [decimal]$env:SIGNAL_REACTIVE_FUND
    $sepoliaPrice = $sepoliaBase * 2
    $oneGwei = [decimal]'1000000000'
    # Sepolia base fee 可以低到十几 wei。下限 1 gwei，避免检查被尘埃 gas 骗过。不要拿这个下限去 Lasna。
    if ($sepoliaPrice -lt $oneGwei) { $sepoliaPrice = $oneGwei }
    $sepoliaGasUnits = $SepoliaBoardGasCap + $SepoliaLedgerGasCap + $SepoliaWaveGasCap
    $sepoliaGasCap = $sepoliaGasUnits * $sepoliaPrice
    $sepoliaNeed = $ledgerFund + $sepoliaGasCap
    $lasnaMaxFee = Get-MaxFee $lasnaBase
    $lasnaGasUnits = $LasnaReactiveGasCap + $LasnaBindGasCap
    $lasnaGasCap = $lasnaGasUnits * $lasnaMaxFee
    $lasnaNeed = $reactiveFund + $lasnaGasCap
    Write-Host "Wallet $Script:Sender1"
    if ($Script:Sender1.Equals($KnownTightWallet, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host 'This is the known test wallet. On 2026-11-25 its Lasna balance was about 0.135 lREACT, which does not cover 0.10 lREACT inside the contract plus deploy gas.'
    }
    Write-Host "SIGNAL_LEDGER_FUND wei=$ledgerFund"
    Write-Host "SIGNAL_REACTIVE_FUND wei=$reactiveFund"
    Write-Host "SIGNAL_WINDOW seconds=$($env:SIGNAL_WINDOW)"
    Write-Host "SIGNAL_MAX_ENCOUNTERS=$($env:SIGNAL_MAX_ENCOUNTERS)"
    Write-Host "SIGNAL_PAIR_ID=$($env:SIGNAL_PAIR_ID)"
    Write-Host "Sepolia balance wei=$sepoliaBal baseFee wei=$sepoliaBase gasCap wei=$sepoliaGasCap need wei=$sepoliaNeed"
    Write-Host "Lasna balance wei=$lasnaBal baseFee wei=$lasnaBase gasCap wei=$lasnaGasCap need wei=$lasnaNeed"
    Write-Host 'Lasna gas cap is the reactive deploy plus bind. It does not include the lREACT stored in the new contract. Fee cap stays at 2x base fee.'
    if ([string]::IsNullOrWhiteSpace($Script:Sender2)) {
        Write-Host 'sender2: absent. waveB needs PRIVATE_KEY_2 in starter\.env. The script will not print it, generate it, or fund a new key.'
    } else {
        Write-Host "sender2: $Script:Sender2"
    }
    return @{
        SepoliaBalance = $sepoliaBal
        LasnaBalance   = $lasnaBal
        SepoliaNeed    = $sepoliaNeed
        LasnaNeed      = $lasnaNeed
        SepoliaBase    = $sepoliaBase
        LasnaBase      = $lasnaBase
        SepoliaPrice   = $sepoliaPrice
    }
}

function Assert-SepoliaBalance($Live) {
    if ($Live.SepoliaBalance -lt $Live.SepoliaNeed) {
        Fail 'Sepolia balance is below the ledger fund plus deploy and waveA headroom. No transaction was sent.'
    }
}

function Assert-LasnaBalance($Live) {
    if ($Live.LasnaBalance -lt $Live.LasnaNeed) {
        $short = $Live.LasnaNeed - $Live.LasnaBalance
        Fail "Lasna balance is short by wei=$short. Need SIGNAL_REACTIVE_FUND plus deploy and bind gas at 2x base fee. No transaction was sent. Do not lower the fee cap below 2x base fee, and do not take lREACT out of the D5 contracts or any older lab contract. The faucet 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 pays 100 lREACT per 1 Sepolia ETH. See docs/cheatsheet.md."
    }
}

function Assert-Proxy {
    if (-not $env:CALLBACK_PROXY) { Fail 'CALLBACK_PROXY is empty.' }
    if (-not $env:CALLBACK_PROXY.Equals($ProxyDefault, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "CALLBACK_PROXY must be the Sepolia Omni proxy $ProxyDefault. An older proxy still has code but does not deliver."
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
    Write-Host 'PRIVATE_KEY: present'
    if ($env:SIGNAL_HAS_KEY2 -eq '1') { Write-Host 'PRIVATE_KEY_2: present' }
    else { Write-Host 'PRIVATE_KEY_2: absent' }
}

function Invoke-Preflight {
    Assert-Tool 'forge' | Out-Null
    Assert-Tool 'cast' | Out-Null
    Assert-Key
    Assert-Chains
    Assert-Proxy
    Assert-PairId | Out-Null
    foreach ($name in @('SIGNAL_BOARD_ADDR', 'SIGNAL_REACTIVE_ADDR', 'SIGNAL_LEDGER_ADDR')) {
        $addr = Get-Address $name
        if ([string]::IsNullOrWhiteSpace($addr)) { Write-Host "${name}: empty" }
        else {
            Assert-NotOld $addr $name
            Write-Host "${name}: $addr"
        }
    }
    Get-Senders
    Write-Host 'Compiling and testing on cancun. This does not broadcast.'
    Invoke-Tool 'forge' @('test', '--match-path', 'test/SignalPath.t.sol', '--evm-version', 'cancun', '-vv') | Out-Null
    Write-Host 'Running the callback gas test under Amsterdam. This does not broadcast and is not the deploy bytecode.'
    Invoke-Tool 'forge' @('test', '--match-path', 'test/SignalPath.t.sol', '--evm-version', 'amsterdam', '--match-test', 'test_record_oneSlotAndUnderStipend', '-vv') | Out-Null
    Write-Host 'Rebuilding production artifacts with cancun.'
    Invoke-Tool 'forge' @('build', '--evm-version', 'cancun') | Out-Null
    $live = Get-LiveNeed
    Assert-SepoliaBalance $live
    Assert-LasnaBalance $live
    Write-Host 'Two addresses are required. waveA uses PRIVATE_KEY. waveB uses PRIVATE_KEY_2 when that line exists.'
    Write-Host 'The homework source transaction is waveB, after both people have signaled inside the window.'
    Write-Host 'preflight finished. No transaction was sent.'
}

function Invoke-DeployBoard {
    Assert-Proxy
    Assert-Chains
    Assert-EmptyAddress 'SIGNAL_BOARD_ADDR'
    Assert-NoCreateReceipt '11155111' 'SignalBoard'
    Get-Senders
    $live = Get-LiveNeed
    Assert-SepoliaBalance $live
    Assert-LasnaBalance $live
    Invoke-Tool 'forge' @(
        'script', 'script/DeploySignal.s.sol:DeployBoard',
        '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
    ) | Out-Null
    Save-CreateFromBroadcast -ChainId '11155111' -ContractName 'SignalBoard' -EnvName 'SIGNAL_BOARD_ADDR'
}

function Invoke-DeployReactive {
    Assert-Chains
    Assert-SetAddress 'SIGNAL_BOARD_ADDR' | Out-Null
    Assert-EmptyAddress 'SIGNAL_REACTIVE_ADDR'
    Assert-NoCreateReceipt '5318007' 'SignalReactive'
    Get-Senders
    $live = Get-LiveNeed
    Assert-LasnaBalance $live
    Invoke-Tool 'forge' @(
        'script', 'script/DeploySignal.s.sol:DeployReactive',
        '--rpc-url', $env:LASNA_RPC_URL, '--broadcast', '--chain', '5318007', '--evm-version', 'cancun'
    ) | Out-Null
    Save-CreateFromBroadcast -ChainId '5318007' -ContractName 'SignalReactive' -EnvName 'SIGNAL_REACTIVE_ADDR'
}

function Invoke-DeployLedger {
    Assert-Proxy
    Assert-Chains
    Assert-SetAddress 'SIGNAL_REACTIVE_ADDR' | Out-Null
    Assert-EmptyAddress 'SIGNAL_LEDGER_ADDR'
    Assert-NoCreateReceipt '11155111' 'EncounterLedger'
    Get-Senders
    $live = Get-LiveNeed
    Assert-SepoliaBalance $live
    Invoke-Tool 'forge' @(
        'script', 'script/DeploySignal.s.sol:DeployLedger',
        '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
    ) | Out-Null
    Save-CreateFromBroadcast -ChainId '11155111' -ContractName 'EncounterLedger' -EnvName 'SIGNAL_LEDGER_ADDR'
}

function Invoke-Bind {
    $reactive = Assert-SetAddress 'SIGNAL_REACTIVE_ADDR'
    $ledger = Assert-SetAddress 'SIGNAL_LEDGER_ADDR'
    Assert-SetAddress 'SIGNAL_BOARD_ADDR' | Out-Null
    Get-Senders
    $live = Get-LiveNeed
    Assert-LasnaBalance $live
    $recipient = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, 'recipient()(address)'))
    $subscribed = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, 'subscribed()(bool)'))
    if ($subscribed -eq 'true' -and $recipient.Equals($ledger, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "Already bound. recipient=$recipient subscribed=true. No transaction was sent."
    }
    Invoke-Tool 'forge' @(
        'script', 'script/DeploySignal.s.sol:SetRecipient',
        '--rpc-url', $env:LASNA_RPC_URL, '--broadcast', '--chain', '5318007', '--evm-version', 'cancun'
    ) | Out-Null
    $hash = Get-LastBroadcastHash '5318007'
    Write-Host "bind tx=$hash"
    Write-Host "https://lasna.reactscan.net/tx/$hash"
    Write-Host 'SignalSent is now subscribed. Next: -Stage waveA, then -Stage waveB from a second account. Do not wave before this step.'
}

function Assert-Subscribed([string]$Reactive) {
    $subscribed = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $Reactive, 'subscribed()(bool)'))
    if ($subscribed -ne 'true') { Fail 'SignalReactive is not subscribed. Run -Stage bind first. No signal was sent.' }
}

function Invoke-WaveA {
    $board = Assert-SetAddress 'SIGNAL_BOARD_ADDR'
    $reactive = Assert-SetAddress 'SIGNAL_REACTIVE_ADDR'
    Assert-SetAddress 'SIGNAL_LEDGER_ADDR' | Out-Null
    Assert-PairId | Out-Null
    Assert-Subscribed $reactive
    $demo = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $board, 'ROMANTIC_DEMO()(bool)'))
    if ($demo -ne 'true') { Fail 'SIGNAL_BOARD_ADDR is not the signal board. No signal was sent.' }
    Get-Senders
    Invoke-Tool 'forge' @(
        'script', 'script/DeploySignal.s.sol:WaveA',
        '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
    ) | Out-Null
    $hash = Get-LastBroadcastHash '11155111'
    Write-Host "waveA tx=$hash"
    Write-Host "https://sepolia.etherscan.io/tx/$hash"
    Write-Host "sender1=$Script:Sender1"
    Write-Host 'waveA is only the first person. It does not unlock the record by itself.'
    Write-Host "Run waveB from a different account within $($env:SIGNAL_WINDOW) seconds. That second signal is the homework source transaction."
    Write-Host 'This script does not invent the Lasna react hash or the Sepolia callback hash.'
}

function Invoke-WaveB {
    Assert-Key
    if ($env:SIGNAL_HAS_KEY2 -ne '1') {
        Fail @"
waveB needs a second Sepolia account. The same wallet signaling twice does not unlock an encounter.
Add PRIVATE_KEY_2 to starter\.env (the file is gitignored). This script will not print it, and it will not generate a key.
Fund that second address with a little Sepolia ETH for gas, from a faucet or from your own test wallet. Do not take funds from old lab contracts.
Then run waveA again if the first signal is older than SIGNAL_WINDOW seconds, and run waveB while the window is still open.
The second wave is the source transaction for the homework path.
"@
    }
    $board = Assert-SetAddress 'SIGNAL_BOARD_ADDR'
    $reactive = Assert-SetAddress 'SIGNAL_REACTIVE_ADDR'
    Assert-SetAddress 'SIGNAL_LEDGER_ADDR' | Out-Null
    Assert-PairId | Out-Null
    Assert-Subscribed $reactive
    $demo = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $board, 'ROMANTIC_DEMO()(bool)'))
    if ($demo -ne 'true') { Fail 'SIGNAL_BOARD_ADDR is not the signal board. No signal was sent.' }
    Get-Senders
    if ([string]::IsNullOrWhiteSpace($Script:Sender2)) { Fail 'sender2 could not be derived. No transaction was sent.' }
    $balance = Get-FirstInteger (Invoke-Tool 'cast' @('balance', $Script:Sender2, '--rpc-url', $env:SEPOLIA_RPC_URL))
    $base = Get-FirstInteger (Invoke-Tool 'cast' @('base-fee', '--rpc-url', $env:SEPOLIA_RPC_URL))
    $price = $base * 2
    $oneGwei = [decimal]'1000000000'
    if ($price -lt $oneGwei) { $price = $oneGwei }
    $need = $SepoliaWaveGasCap * $price
    Write-Host "sender2 $Script:Sender2 balance wei=$balance wave gas cap wei=$need"
    if ($balance -lt $need) {
        Fail "sender2 balance is below the waveB gas cap. Fund $Script:Sender2 with a little Sepolia ETH, then rerun waveB. No transaction was sent. Do not take funds from old lab contracts."
    }
    Invoke-Tool 'forge' @(
        'script', 'script/DeploySignal.s.sol:WaveB',
        '--rpc-url', $env:SEPOLIA_RPC_URL, '--broadcast', '--chain', '11155111', '--evm-version', 'cancun'
    ) | Out-Null
    $hash = Get-LastBroadcastHash '11155111'
    Write-Host "waveB tx=$hash"
    Write-Host "https://sepolia.etherscan.io/tx/$hash"
    Write-Host 'waveB is the source transaction for the homework path. Wait 10-60 seconds, then run -Stage verify.'
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
    $board = Assert-SetAddress 'SIGNAL_BOARD_ADDR'
    $reactive = Assert-SetAddress 'SIGNAL_REACTIVE_ADDR'
    $ledger = Assert-SetAddress 'SIGNAL_LEDGER_ADDR'
    $pair = Assert-PairId
    Write-Host "Sepolia signal board $board"
    $demo = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $board, 'ROMANTIC_DEMO()(bool)'))
    Write-Host "ROMANTIC_DEMO $demo"
    Write-Host "Lasna $reactive"
    foreach ($sig in @(
        'subscribed()(bool)', 'stopped()(bool)', 'remaining()(uint256)', 'requested()(uint256)',
        'recipient()(address)', 'WINDOW()(uint256)', 'lastReactBlock()(uint256)'
    )) {
        $value = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $reactive, $sig))
        Write-Host "$sig $value"
    }
    $memory = Get-CastValue (Invoke-Tool 'cast' @(
        'call', '--rpc-url', $env:LASNA_RPC_URL, $reactive,
        'pairMemory(bytes32)(address,uint64,address,uint64)', $pair
    ))
    Write-Host "pairMemory $memory"
    Write-Host ("balance lREACT " + (Get-CastValue (Invoke-Tool 'cast' @('balance', '--rpc-url', $env:LASNA_RPC_URL, $reactive, '-e'))))
    Write-Host ("debt " + (Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:LASNA_RPC_URL, $System, 'debt(address)(uint256)', $reactive))))
    Write-Host "Sepolia ledger $ledger"
    foreach ($sig in @('count()(uint256)', 'earlierAt()(uint256)', 'laterAt()(uint256)', 'pairTag()(uint256)')) {
        $value = Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $ledger, $sig))
        Write-Host "$sig $value"
    }
    Write-Host ("balance ETH " + (Get-CastValue (Invoke-Tool 'cast' @('balance', '--rpc-url', $env:SEPOLIA_RPC_URL, $ledger, '-e'))))
    Write-Host ("proxy debt " + (Get-CastValue (Invoke-Tool 'cast' @('call', '--rpc-url', $env:SEPOLIA_RPC_URL, $env:CALLBACK_PROXY, 'debt(address)(uint256)', $ledger))))
    $bn = Get-FirstInteger (Invoke-Tool 'cast' @('block-number', '--rpc-url', $env:SEPOLIA_RPC_URL))
    $from = $bn - 50000
    if ($from -lt 0) { $from = 0 }
    Invoke-Tool 'cast' @(
        'logs', '--rpc-url', $env:SEPOLIA_RPC_URL, '--from-block', ([string]$from),
        '--address', $ledger,
        'EncounterUnlocked(address indexed reactive, bytes32 indexed pairId, address personLow, uint64 timeLow, address personHigh, uint64 timeHigh, uint32 count)'
    ) | Out-Null
    Write-Host 'verify finished. No transaction was sent.'
    Write-Host 'Copy the three live hashes from the explorers after they exist: waveB on Sepolia, the Lasna react, and the Sepolia EncounterUnlocked transaction. Do not invent them.'
    Write-Host 'The web page can read this ledger. The poem, picture, and chime stay in demo/mutual-signal and are not stored on chain.'
}

function Invoke-PrepareRerun {
    $board = Get-Address 'SIGNAL_BOARD_ADDR'
    $reactive = Get-Address 'SIGNAL_REACTIVE_ADDR'
    $ledger = Get-Address 'SIGNAL_LEDGER_ADDR'
    if ([string]::IsNullOrWhiteSpace($board) -and [string]::IsNullOrWhiteSpace($reactive) -and [string]::IsNullOrWhiteSpace($ledger)) {
        Fail 'SIGNAL_BOARD_ADDR, SIGNAL_REACTIVE_ADDR, and SIGNAL_LEDGER_ADDR are already empty. Nothing was moved.'
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $src = Join-Path $Starter 'broadcast\DeploySignal.s.sol'
    if (Test-Path -LiteralPath $src) {
        $destRoot = Join-Path $Starter "broadcast\signal-archive\$stamp"
        if (Test-Path -LiteralPath $destRoot) { Fail "Archive folder already exists: $destRoot" }
        New-Item -ItemType Directory -Path $destRoot | Out-Null
        Move-Item -LiteralPath $src -Destination (Join-Path $destRoot 'DeploySignal.s.sol')
        Write-Host "Moved public receipts to broadcast\signal-archive\$stamp\DeploySignal.s.sol"
    } else {
        Write-Host 'No broadcast\DeploySignal.s.sol directory was present.'
    }
    foreach ($name in @('SIGNAL_BOARD_ADDR', 'SIGNAL_REACTIVE_ADDR', 'SIGNAL_LEDGER_ADDR')) {
        Write-LabEnvLine -Name $name -Value ''
    }
    Write-Host 'Cleared only the three SIGNAL_ address lines. D5_, SPREAD_, and ORIGIN/REACTIVE/CALLBACK lines were kept. cache was not read.'
}

Add-FoundryPath
Set-Location -LiteralPath $Starter
$parsedEnv = Read-DotEnv
Import-LabEnv $parsedEnv

switch ($Stage) {
    'preflight' { Invoke-Preflight }
    'prepareRerun' { Invoke-PrepareRerun }
    'deployBoard' { Invoke-DeployBoard }
    'deployReactive' { Invoke-DeployReactive }
    'deployLedger' { Invoke-DeployLedger }
    'bind' { Invoke-Bind }
    'waveA' { Invoke-WaveA }
    'waveB' { Invoke-WaveB }
    'verify' { Invoke-Verify }
}
