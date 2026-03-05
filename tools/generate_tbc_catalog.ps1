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

$zoneSpec = @(
    @{ Folder = "Eversong"; Key = "eversong"; Group = "quelthalas"; Label = "Eversong Woods" },
    @{ Folder = "Ghostlands"; Key = "ghostlands"; Group = "quelthalas"; Label = "Ghostlands" },
    @{ Folder = "Zulaman"; Key = "zulaman"; Group = "quelthalas"; Label = "Zul'Aman / Amani" },
    @{ Folder = "Sunwell"; Key = "sunwell"; Group = "quelthalas"; Label = "Isle of Quel'Danas / Sunwell" },
    @{ Folder = "HellfirePeninsula"; Key = "hellfire_peninsula"; Group = "outland"; Label = "Hellfire Peninsula" },
    @{ Folder = "ZangarMarsh"; Key = "zangarmarsh"; Group = "outland"; Label = "Zangarmarsh" },
    @{ Folder = "Terokkar"; Key = "terokkar"; Group = "outland"; Label = "Terokkar Forest" },
    @{ Folder = "Nagrand"; Key = "nagrand"; Group = "outland"; Label = "Nagrand" },
    @{ Folder = "BladesEdge"; Key = "blades_edge"; Group = "outland"; Label = "Blade's Edge Mountains" },
    @{ Folder = "Netherstorm"; Key = "netherstorm"; Group = "outland"; Label = "Netherstorm" },
    @{ Folder = "ShadowmoonValley"; Key = "shadowmoon_valley"; Group = "outland"; Label = "Shadowmoon Valley" },
    @{ Folder = "OutlandGeneral"; Key = "outland_general"; Group = "outland"; Label = "Outland General" },
    @{ Folder = "Karazhan"; Key = "karazhan"; Group = "tbc_instances"; Label = "Karazhan" },
    @{ Folder = "TempestKeep"; Key = "tempest_keep"; Group = "tbc_instances"; Label = "Tempest Keep" },
    @{ Folder = "BlackTemple"; Key = "black_temple"; Group = "tbc_instances"; Label = "Black Temple" }
)

$folderToSpec = @{}
$entriesByFolder = @{}
foreach ($z in $zoneSpec) {
    $folderToSpec[$z.Folder] = $z
    $entriesByFolder[$z.Folder] = New-Object System.Collections.Generic.List[object]
}

$reader = [System.IO.StreamReader]::new($ListfilePath)
try {
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($line -match "^(\\d+);Sound/music/ZONEMUSIC/([^/]+)/(.+)$") {
            $id = [int]$matches[1]
            $folder = $matches[2]
            $tail = $matches[3]
            if ($folderToSpec.ContainsKey($folder)) {
                $entriesByFolder[$folder].Add([PSCustomObject]@{
                        id   = $id
                        path = "Sound/music/ZONEMUSIC/$folder/$tail"
                    })
            }
        }
    }
}
finally {
    $reader.Close()
}

$keys = @($entriesByFolder.Keys)
foreach ($k in $keys) {
    $sorted = $entriesByFolder[$k] | Sort-Object id
    $newList = New-Object System.Collections.Generic.List[object]
    foreach ($e in $sorted) {
        $newList.Add($e)
    }
    $entriesByFolder[$k] = $newList
}

$generatedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$groups = @("quelthalas", "outland", "tbc_instances")

# Lua output
$luaOut = Join-Path $repoRoot "TBC_ID_CATALOG.lua"
$luaLines = New-Object System.Collections.Generic.List[string]
$luaLines.Add("-- ============================================================")
$luaLines.Add("--  TBC_ID_CATALOG.lua")
$luaLines.Add("--  Auto-generated reference data for The Burning Crusade zone music IDs.")
$luaLines.Add("--  Source: wowdev/wow-listfile community-listfile-withcapitals.csv")
$luaLines.Add("--  Release: $ReleaseTag")
$luaLines.Add("--  Generated UTC: $generatedUtc")
$luaLines.Add("--  Note: This file is for catalog/config authoring and is not loaded by the addon runtime yet.")
$luaLines.Add("-- ============================================================")
$luaLines.Add("")
$luaLines.Add("BElfVR_TBCIDCatalogMeta = {")
$luaLines.Add(('    source = "{0}",' -f "wowdev/wow-listfile"))
$luaLines.Add(('    release = "{0}",' -f $ReleaseTag))
$luaLines.Add(('    generatedUTC = "{0}",' -f $generatedUtc))
$luaLines.Add(('    scope = "{0}",' -f "TBC-era zone music catalogs (Quel'Thalas focus + Outland + key TBC instances)"))
$luaLines.Add("}")
$luaLines.Add("")
$luaLines.Add("BElfVR_TBCZoneMusicCatalog = {")

foreach ($group in $groups) {
    $luaLines.Add(("    {0} = {{" -f $group))
    foreach ($z in $zoneSpec | Where-Object { $_.Group -eq $group }) {
        $luaLines.Add(("        {0} = {{" -f $z.Key))
        foreach ($entry in $entriesByFolder[$z.Folder]) {
            $pathEscaped = $entry.path.Replace('\', '\\').Replace('"', '\"')
            $luaLines.Add(("            {{ id = {0}, path = ""{1}"" }}," -f $entry.id, $pathEscaped))
        }
        $luaLines.Add("        },")
    }
    $luaLines.Add("    },")
}
$luaLines.Add("}")

Set-Content -Path $luaOut -Value $luaLines -Encoding UTF8

# Markdown output
$mdOut = Join-Path $repoRoot "TBC_ID_INDEX.md"
$mdLines = New-Object System.Collections.Generic.List[string]
$mdLines.Add("# TBC ID Index")
$mdLines.Add("")
$mdLines.Add(('- Source: `wowdev/wow-listfile` `community-listfile-withcapitals.csv` (release `{0}`)' -f $ReleaseTag))
$mdLines.Add(('- Generated UTC: `{0}`' -f $generatedUtc))
$mdLines.Add("- Scope: TBC-era zone-music IDs for Quel'Thalas (focus), Outland zones, and key TBC instance folders.")
$mdLines.Add('- Machine-readable catalog: `TBC_ID_CATALOG.lua`')
$mdLines.Add("")
$mdLines.Add("## Zone Counts")
$mdLines.Add("")
$mdLines.Add("| Group | Zone | Folder | Count |")
$mdLines.Add("|---|---|---|---:|")
foreach ($group in $groups) {
    foreach ($z in $zoneSpec | Where-Object { $_.Group -eq $group }) {
        $count = $entriesByFolder[$z.Folder].Count
        $mdLines.Add(('| {0} | {1} | `{2}` | {3} |' -f $group, $z.Label, $z.Folder, $count))
    }
}

$mdLines.Add("")
$mdLines.Add("## Quel'Thalas Full IDs")
$mdLines.Add("")
foreach ($z in $zoneSpec | Where-Object { $_.Group -eq "quelthalas" }) {
    $mdLines.Add(('### {0} (`{1}`)' -f $z.Label, $z.Folder))
    $mdLines.Add("")
    foreach ($entry in $entriesByFolder[$z.Folder]) {
        $mdLines.Add(('- `{0}` `{1}`' -f $entry.id, $entry.path))
    }
    $mdLines.Add("")
}

$mdLines.Add("## Notes")
$mdLines.Add("")
$mdLines.Add("- This index is intentionally data-first for future `config.lua` routing work.")
$mdLines.Add("- Not every TBC-era asset in the client is under `Sound/music/ZONEMUSIC/*`; this file catalogs zone-music families only.")
$mdLines.Add("- Existing Blood Elf TBC voice pools remain in `SoundData.lua` (`BElfVR_TBCVoices_Male`, `BElfVR_TBCVoices_Female`).")

Set-Content -Path $mdOut -Value $mdLines -Encoding UTF8

Write-Output "Generated: $luaOut"
Write-Output "Generated: $mdOut"
