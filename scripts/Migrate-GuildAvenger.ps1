[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ClientRoot
)

$ErrorActionPreference = 'Stop'
$client = (Resolve-Path -LiteralPath $ClientRoot).ProviderPath
$addonsPath = Join-Path $client 'Interface/AddOns'
$addons = (Resolve-Path -LiteralPath $addonsPath).ProviderPath
if ($addons -ne [IO.Path]::GetFullPath($addonsPath)) {
    throw 'The AddOns directory did not resolve to the selected game directory.'
}

$running = Get-Process -Name 'Wow', 'WowB', 'WowT' -ErrorAction SilentlyContinue |
    Where-Object { -not $_.Path -or [IO.Path]::GetDirectoryName($_.Path) -eq $client }
if ($running) { throw 'Close the WoW client before migrating its saved variables.' }

$oldPath = Join-Path $addons 'ForeverWatch'
$oldToc = Join-Path $oldPath 'ForeverWatch.toc'
if (-not (Test-Path -LiteralPath $oldToc -PathType Leaf)) {
    throw 'The original GrudgeBook or Forever Watch addon was not found.'
}
$metadata = Get-Content -LiteralPath $oldToc -Raw -Encoding UTF8
$isGrudgeBook = $metadata -cmatch '(?m)^## Title: GrudgeBook\s*$' -and
    $metadata -cmatch '(?m)^## SavedVariables: GrudgeBookDB, ForeverWatchDB\s*$'
$isOriginal = $metadata -cmatch '(?m)^## Title: Forever Watch\s*$' -and
    $metadata -cmatch '(?m)^## Notes: PvP proximity alerts for watched characters and guilds in WoW: Forever\.\s*$'
if (-not ($isGrudgeBook -or $isOriginal)) {
    throw 'The ForeverWatch folder belongs to a different addon.'
}

$oldFolder = Get-Item -LiteralPath $oldPath
if ($oldFolder.FullName -ne [IO.Path]::GetFullPath($oldPath) -or
    ($oldFolder.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The original addon directory must be a regular folder inside AddOns.'
}
$newToc = Join-Path $addons 'GuildAvenger/GuildAvenger.toc'
if (-not (Test-Path -LiteralPath $newToc -PathType Leaf)) {
    throw 'Install Guild Avenger before migrating the saved variables.'
}

$rename = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
$rename.Add('GrudgeBookDB', 'GuildAvengerDB')
$rename.Add('ForeverWatchDB', 'GuildAvengerLegacyDB')
$assignment = '(?m)^(?<name>[A-Za-z_][A-Za-z_0-9]*)[\t ]*=[\t ]*(?=\{|nil\s*$)'
$accountRoot = Join-Path $client 'WTF/Account'
$copies = @()
$legacyFiles = @()
$matched = 0
if (Test-Path -LiteralPath $accountRoot -PathType Container) {
    foreach ($profile in Get-ChildItem -LiteralPath $accountRoot -Directory) {
        $saved = Join-Path $profile.FullName 'SavedVariables'
        $source = Join-Path $saved 'ForeverWatch.lua'
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { $source += '.bak' }
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }

        $original = [IO.File]::ReadAllText($source)
        if ([string]::IsNullOrWhiteSpace($original)) { continue }
        $tables = [regex]::Matches($original, $assignment)
        if ($tables.Count -eq 0) { throw 'A saved variables file does not contain a recognized table.' }
        $seen = @{}
        foreach ($table in $tables) {
            $name = $table.Groups['name'].Value
            if (-not $rename.ContainsKey($name) -or $seen.ContainsKey($name)) {
                throw 'A saved variables file contains an unexpected table.'
            }
            $seen[$name] = $true
        }
        $dataTokens = [regex]::Replace($original, $assignment, '')
        $dataTokens = [regex]::Replace($dataTokens, '"(?:\\[\s\S]|[^"\\])*"|--[^\r\n]*', '')
        $dataTokens = [regex]::Replace($dataTokens, '\b(?:nil|true|false)\b|0[xX][0-9a-fA-F]+|[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?', '')
        if ($dataTokens -match '[^\s{}\[\]=,;]') { throw 'A saved variables file contains data outside the WoW table format.' }

        $text = [regex]::Replace($original, $assignment, {
            param($match)
            $rename[$match.Groups['name'].Value] + ' = '
        })
        $destination = Join-Path $saved 'GuildAvenger.lua'
        if (Test-Path -LiteralPath $destination) {
            if ([IO.File]::ReadAllText($destination) -cne $text) {
                throw 'Guild Avenger already has different saved data. Its data will need to be merged before migration.'
            }
        } else {
            $copies += [pscustomobject]@{ Path = $destination; Text = $text }
        }
        $legacyFiles += [pscustomobject]@{ Path = $source; Account = $profile.Name }
        $olderBackup = Join-Path $saved 'ForeverWatch.lua.bak'
        if ($olderBackup -ne $source -and (Test-Path -LiteralPath $olderBackup -PathType Leaf)) {
            $olderTables = [regex]::Matches([IO.File]::ReadAllText($olderBackup), $assignment)
            $knownTables = @($olderTables | Where-Object { $rename.ContainsKey($_.Groups['name'].Value) })
            if ($olderTables.Count -gt 0 -and $olderTables.Count -eq $knownTables.Count) {
                $legacyFiles += [pscustomobject]@{ Path = $olderBackup; Account = $profile.Name }
            }
        }
        $matched++
    }
}

$backupRoot = [IO.Path]::GetFullPath((Join-Path $client 'GuildAvengerMigrationBackup'))
if ([IO.Path]::GetDirectoryName($backupRoot) -ne $client) { throw 'The backup path is outside the selected client.' }
if (Test-Path -LiteralPath $backupRoot) {
    $backupItem = Get-Item -LiteralPath $backupRoot
    if (-not $backupItem.PSIsContainer -or ($backupItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The backup directory must be a regular folder.'
    }
}
$backup = Join-Path $backupRoot ([Guid]::NewGuid().ToString('N'))
$backupAddon = [IO.Path]::GetFullPath((Join-Path $backup 'ForeverWatch'))
if ([IO.Path]::GetDirectoryName($backupAddon) -ne $backup) { throw 'The addon archive path is invalid.' }

if ($PSCmdlet.ShouldProcess($client, "Migrate $matched saved-variable file(s) and archive the original addon")) {
    foreach ($copy in $copies) {
        $temporary = $copy.Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        try {
            [IO.File]::WriteAllText($temporary, $copy.Text, [Text.UTF8Encoding]::new($false))
            [IO.File]::Move($temporary, $copy.Path)
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
        }
        if ([IO.File]::ReadAllText($copy.Path) -cne $copy.Text) { throw 'Verification of a converted file failed.' }
    }
    New-Item -ItemType Directory -Path $backup | Out-Null
    Move-Item -LiteralPath $oldFolder.FullName -Destination $backupAddon
    foreach ($file in $legacyFiles) {
        $savedBackup = Join-Path $backup ('SavedVariables/' + $file.Account)
        $null = New-Item -ItemType Directory -Path $savedBackup -Force
        $target = Join-Path $savedBackup ([IO.Path]::GetFileName($file.Path))
        $originalHash = (Get-FileHash -LiteralPath $file.Path).Hash
        Move-Item -LiteralPath $file.Path -Destination $target
        if ((Get-FileHash -LiteralPath $target).Hash -ne $originalHash) { throw 'Verification of an archived file failed.' }
    }
    Write-Output "Migrated $matched saved-variable file(s). Original addon archived in $backup."
}
