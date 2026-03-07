param(
    [Parameter(Mandatory = $true)]
    [string]$ListfilePath,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseTag
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ListfilePath)) {
    throw "Listfile not found: $ListfilePath"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$generatedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$entriesByFamily = @{}

$reader = [System.IO.StreamReader]::new($ListfilePath)
try {
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        $parts = $line -split ";", 2
        if ($parts.Count -ne 2) {
            continue
        }

        $idText = $parts[0]
        $path = $parts[1]
        if ($path -notlike "sound/music/midnight/mus_120_*.mp3") {
            continue
        }

        $id = [int]$idText
        $fileKey = [System.IO.Path]::GetFileNameWithoutExtension($path)

        if ($fileKey -match "^mus_120_(.+)_[a-z0-9]+$") {
            $family = $matches[1]
        } else {
            $family = $fileKey.Substring(8)
        }

        if (-not $entriesByFamily.ContainsKey($family)) {
            $entriesByFamily[$family] = New-Object System.Collections.Generic.List[object]
        }

        $entriesByFamily[$family].Add([PSCustomObject]@{
                id   = $id
                key  = $fileKey
                path = $path
            })
    }
}
finally {
    $reader.Close()
}

$familyNames = @($entriesByFamily.Keys | Sort-Object)
$allIDs = New-Object System.Collections.Generic.List[int]

foreach ($family in $familyNames) {
    $sorted = $entriesByFamily[$family] | Sort-Object id
    $newList = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $sorted) {
        $newList.Add($entry)
        $allIDs.Add($entry.id)
    }
    $entriesByFamily[$family] = $newList
}

# Lua output
$luaOut = Join-Path $repoRoot "Midnight_ID_catalog.lua"
$luaLines = New-Object System.Collections.Generic.List[string]
$luaLines.Add("-- ============================================================")
$luaLines.Add("--  Midnight_ID_catalog.lua")
$luaLines.Add("--  Auto-generated reference data for Midnight 12.0 music IDs.")
$luaLines.Add("--  Source: wowdev/wow-listfile community-listfile.csv")
$luaLines.Add("--  Release: $ReleaseTag")
$luaLines.Add("--  Generated UTC: $generatedUtc")
$luaLines.Add("--  This file is safe to load at runtime.")
$luaLines.Add("-- ============================================================")
$luaLines.Add("")
$luaLines.Add("BElfVR_MidnightIDCatalogMeta = {")
$luaLines.Add(('    source = "{0}",' -f "wowdev/wow-listfile"))
$luaLines.Add(('    release = "{0}",' -f $ReleaseTag))
$luaLines.Add(('    generatedUTC = "{0}",' -f $generatedUtc))
$luaLines.Add(('    scope = "{0}",' -f "Midnight 12.0 music families (sound/music/midnight/mus_120_*.mp3)"))
$luaLines.Add("}")
$luaLines.Add("")
$luaLines.Add("BElfVR_MidnightMusicCatalog = {")
foreach ($family in $familyNames) {
    $luaLines.Add(("    {0} = {{" -f $family))
    foreach ($entry in $entriesByFamily[$family]) {
        $pathEscaped = $entry.path.Replace('\', '\\').Replace('"', '\"')
        $keyEscaped = $entry.key.Replace('\', '\\').Replace('"', '\"')
        $luaLines.Add(("        {{ id = {0}, key = ""{1}"", path = ""{2}"" }}," -f $entry.id, $keyEscaped, $pathEscaped))
    }
    $luaLines.Add("    },")
}
$luaLines.Add("}")
$luaLines.Add("")
$luaLines.Add("BElfVR_MidnightMusicFamilyIDs = {")
foreach ($family in $familyNames) {
    $luaLines.Add(("    {0} = {{" -f $family))
    foreach ($entry in $entriesByFamily[$family]) {
        $luaLines.Add(("        {0}," -f $entry.id))
    }
    $luaLines.Add("    },")
}
$luaLines.Add("}")
$luaLines.Add("")
$luaLines.Add("BElfVR_MidnightAllMusicIDs = {")
foreach ($id in ($allIDs | Sort-Object -Unique)) {
    $luaLines.Add(("    {0}," -f $id))
}
$luaLines.Add("}")

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllLines($luaOut, $luaLines, $utf8NoBom)

# Markdown output
$mdOut = Join-Path $repoRoot "Midnight_ID_Index.md"
$mdLines = New-Object System.Collections.Generic.List[string]
$mdLines.Add("# Midnight ID Index")
$mdLines.Add("")
$mdLines.Add(('- Source: `wowdev/wow-listfile` `community-listfile.csv` (release `{0}`)' -f $ReleaseTag))
$mdLines.Add(('- Generated UTC: `{0}`' -f $generatedUtc))
$mdLines.Add('- Scope: Midnight 12.0 music families under `sound/music/midnight/mus_120_*.mp3`.')
$mdLines.Add('- Machine-readable catalog: `Midnight_ID_catalog.lua`')
$mdLines.Add("")
$mdLines.Add("## Family Counts")
$mdLines.Add("")
$mdLines.Add("| Family | Count |")
$mdLines.Add("|---|---:|")
foreach ($family in $familyNames) {
    $mdLines.Add(('| `{0}` | {1} |' -f $family, $entriesByFamily[$family].Count))
}
$mdLines.Add("")
$mdLines.Add("## Full IDs")
$mdLines.Add("")
foreach ($family in $familyNames) {
    $mdLines.Add(('### `{0}`' -f $family))
    $mdLines.Add("")
    foreach ($entry in $entriesByFamily[$family]) {
        $mdLines.Add(('- `{0}` `{1}`' -f $entry.id, $entry.path))
    }
    $mdLines.Add("")
}
$mdLines.Add("## Notes")
$mdLines.Add("")
$mdLines.Add("- Family names are derived from the shared prefix before the trailing variant token (for example `_a`, `_h`, `_void_a`).")
$mdLines.Add("- This catalog intentionally focuses on `mus_120_*` music assets only; anonymous fallback IDs such as `mus_1200_*` are not present in the source listfile.")
$mdLines.Add("- Runtime integration note: `Midnight_ID_catalog.lua` is loaded before `SoundData.lua`, and the addon uses this catalog as the main source for tracked Midnight music muting.")
$mdLines.Add("- Runtime exclusion note: Harandar families are intentionally excluded from active muting through `MIDNIGHT_CATALOG_MUTE_FAMILY_EXCLUSIONS` so Harandar stays native.")
$mdLines.Add("- Runtime supplemental note: manual non-catalog `mus_1200_*` seed IDs still live in `BElfVR_NewMusicIDs`.")
$mdLines.Add("- Runtime supplemental note: non-Midnight Blizzard tavern / inn / rest-area zonemusic used in supported interiors lives in `BElfVR_SupplementalMusicMuteIDs` and is outside this generated catalog.")

[System.IO.File]::WriteAllLines($mdOut, $mdLines, $utf8NoBom)

Write-Output "Generated: $luaOut"
Write-Output "Generated: $mdOut"
