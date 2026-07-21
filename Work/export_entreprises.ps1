<#
.SYNOPSIS
    Exporte les entreprises françaises (CA >= 20 M€) depuis l'API recherche-entreprises.
    https://github.com/yannoux10/public

    REMARQUE : si PowerShell refuse d'exécuter ce script avec l'erreur
    "l'exécution de scripts est désactivée sur ce système", lancez dans
    une console Administrateur :
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    Ou sans changer la politique, depuis cmd.exe :
        powershell -ExecutionPolicy Bypass -File .\export_entreprises.ps1

.DESCRIPTION
    Interroge l'API recherche-entreprises.api.gouv.fr/search et génère des fichiers CSV
    avec les colonnes : Company Name, SIREN, Website, Main Activity, Business Sector,
    Detailed Sector, HQ Address, Zip Code, Department, Region Code, Employee Bracket,
    Number of Establishments, Revenue Year, Latest Revenue.
    Filtre par siège social uniquement, avec option de tranche d'effectif.

.PARAMETER Mode
    Mode d'export (aura_bfc, aura-69, bfc, 69, all). Peut être passé en position 0.

.PARAMETER Type
    Alias -t. Alternative à Mode pour spécification explicite du type d'export.

.PARAMETER Employees
    Alias -e. Filtre par tranche d'effectif (codes séparés par des virgules).
    Exemples : "21,22,31,32" = 50-499 salariés.
    Peut aussi être défini via la variable d'environnement TRANCHES_EFFECTIF.

.PARAMETER Help
    Alias -h. Affiche cette aide détaillée.

.EXAMPLE
    .\export_entreprises.ps1 aura_bfc

.EXAMPLE
    .\export_entreprises.ps1 -t aura-69 -e "21,22,31,32"

.EXAMPLE
    .\export_entreprises.ps1 69

.EXAMPLE
    $env:TRANCHES_EFFECTIF="31,32,41,42"; .\export_entreprises.ps1 all

.NOTES
    PowerShell 5.1+ requis. Aucune dépendance externe — utilise Invoke-RestMethod.
    Version 2.0 — portage PowerShell du script export_entreprises.sh.
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Mode,

    [Parameter(Mandatory=$false)]
    [Alias('t')]
    [string]$Type,

    [Parameter(Mandatory=$false)]
    [Alias('e')]
    [string]$Employees,

    [Parameter(Mandatory=$false)]
    [Alias('h')]
    [switch]$Help
)

# ============================================================
# Configuration
# ============================================================
$script:BASE_URL = "https://recherche-entreprises.api.gouv.fr/search"
$script:UA       = "PowerShell/2.0 (yann.ropars@gmail.com)"
$script:CA_MIN   = 20000000
$script:PER_PAGE = 25

# Employee filter — priority: -e flag > env var
if ($Employees) {
    $script:TRANCHES_EFFECTIF = $Employees
}
else {
    $script:TRANCHES_EFFECTIF = [Environment]::GetEnvironmentVariable('TRANCHES_EFFECTIF')
}

# ============================================================
# NAF classification functions
# ============================================================

function Get-Sector {
    param([string]$nafCode)

    if ([string]::IsNullOrEmpty($nafCode) -or $nafCode.Length -lt 2) { return 'Unknown' }
    $div = 0
    $null = [int]::TryParse($nafCode.Substring(0,2), [ref]$div)
    if (-not $div) { return 'Unknown' }

    switch ($div) {
        {$_ -ge 1 -and $_ -le 3}  { return 'Agriculture, forestry and fishing' }
        {$_ -ge 5 -and $_ -le 9}  { return 'Mining and quarrying' }
        {$_ -ge 10 -and $_ -le 33} { return 'Manufacturing' }
        35                         { return 'Electricity, gas, steam and air conditioning supply' }
        {$_ -ge 36 -and $_ -le 39} { return 'Water supply; sewerage, waste management and remediation activities' }
        {$_ -ge 41 -and $_ -le 43} { return 'Construction' }
        {$_ -ge 45 -and $_ -le 47} { return 'Wholesale and retail trade; repair of motor vehicles and motorcycles' }
        {$_ -ge 49 -and $_ -le 53} { return 'Transportation and storage' }
        {$_ -ge 55 -and $_ -le 56} { return 'Accommodation and food service activities' }
        {$_ -ge 58 -and $_ -le 63} { return 'Information and communication' }
        {$_ -ge 64 -and $_ -le 66} { return 'Financial and insurance activities' }
        68                         { return 'Real estate activities' }
        {$_ -ge 69 -and $_ -le 75} { return 'Professional, scientific and technical activities' }
        {$_ -ge 77 -and $_ -le 82} { return 'Administrative and support service activities' }
        84                         { return 'Public administration and defence; compulsory social security' }
        85                         { return 'Education' }
        {$_ -ge 86 -and $_ -le 88} { return 'Human health and social work activities' }
        {$_ -ge 90 -and $_ -le 93} { return 'Arts, entertainment and recreation' }
        {$_ -ge 94 -and $_ -le 96} { return 'Other service activities' }
        {$_ -ge 97 -and $_ -le 98} { return 'Activities of households as employers' }
        99                         { return 'Activities of extraterritorial organisations and bodies' }
        default                    { return 'Unknown' }
    }
}

function Get-DetailedSector {
    param([string]$nafCode)

    if ([string]::IsNullOrEmpty($nafCode) -or $nafCode.Length -lt 2) { return 'Unknown' }
    $div = 0
    $null = [int]::TryParse($nafCode.Substring(0,2), [ref]$div)
    if (-not $div) { return 'Unknown' }

    switch ($div) {
        {$_ -ge 1 -and $_ -le 3}   { return 'Agriculture, Forestry and Fishing' }
        {$_ -ge 5 -and $_ -le 9}   { return 'Mining and Quarrying' }
        {$_ -ge 10 -and $_ -le 12}  { return 'Manufacturing: Food, Beverages and Tobacco' }
        {$_ -ge 13 -and $_ -le 15}  { return 'Manufacturing: Textiles, Apparel and Leather' }
        {$_ -ge 16 -and $_ -le 18}  { return 'Manufacturing: Wood, Paper and Printing' }
        {$_ -ge 19 -and $_ -le 21}  { return 'Manufacturing: Chemicals, Pharma and Petroleum' }
        {$_ -ge 22 -and $_ -le 23}  { return 'Manufacturing: Rubber, Plastic and Minerals' }
        {$_ -ge 24 -and $_ -le 25}  { return 'Manufacturing: Basic Metals and Fabricated Products' }
        {$_ -ge 26 -and $_ -le 28}  { return 'Manufacturing: Electronics, Electrical and Machinery' }
        {$_ -ge 29 -and $_ -le 30}  { return 'Manufacturing: Transport Equipment' }
        {$_ -ge 31 -and $_ -le 33}  { return 'Manufacturing: Furniture and Other' }
        35                          { return 'Electricity, Gas, Steam and Air Conditioning' }
        {$_ -ge 36 -and $_ -le 39}  { return 'Water, Waste and Remediation' }
        {$_ -ge 41 -and $_ -le 43}  { return 'Construction' }
        45                          { return 'Trade: Motor Vehicles and Repair' }
        46                          { return 'Trade: Wholesale (except Motor Vehicles)' }
        47                          { return 'Trade: Retail (except Motor Vehicles)' }
        {$_ -ge 49 -and $_ -le 53}  { return 'Transportation and Storage' }
        {$_ -ge 55 -and $_ -le 56}  { return 'Accommodation and Food Services' }
        {$_ -ge 58 -and $_ -le 60}  { return 'Communication: Media and Publishing' }
        61                          { return 'Communication: Telecommunications' }
        {$_ -ge 62 -and $_ -le 63}  { return 'Information Technology and Services' }
        {$_ -ge 64 -and $_ -le 66}  { return 'Financial and Insurance' }
        68                          { return 'Real Estate' }
        {$_ -ge 69 -and $_ -le 71}  { return 'Professional: Legal, Consulting, Engineering' }
        72                          { return 'Professional: Research and Development' }
        {$_ -ge 73 -and $_ -le 75}  { return 'Professional: Other Technical' }
        {$_ -ge 77 -and $_ -le 82}  { return 'Administrative and Support' }
        84                          { return 'Public Administration' }
        85                          { return 'Education' }
        {$_ -ge 86 -and $_ -le 88}  { return 'Human Health and Social Work' }
        {$_ -ge 90 -and $_ -le 99}  { return 'Other Services' }
        default                     { return 'Unknown' }
    }
}

# ============================================================
# Data transformation functions
# ============================================================

function ConvertFrom-EnterpriseToCsv {
    <#
    .SYNOPSIS
        Transforme les résultats JSON de l'API en objets CSV.
    #>
    param(
        [array]$Results,
        [string]$FilterField,
        [string]$FilterValue
    )

    foreach ($item in $Results) {
        # Filtre : ne garder que les sièges dans la zone cible
        $fieldVal = if ($item.siege) { $item.siege.$FilterField } else { $null }
        if ($fieldVal -ne $FilterValue) { continue }

        $code     = if ($item.activite_principale) { $item.activite_principale } else { '' }
        $sector   = Get-Sector $code
        $detSector = Get-DetailedSector $code

        # Extraire la dernière année de finances
        $revenueYear   = ''
        $latestRevenue = ''
        if ($item.finances -and $item.finances.PSObject.Properties) {
            $props = @($item.finances.PSObject.Properties)
            if ($props.Count -gt 0) {
                $lastFinance = $props | Sort-Object Name -Descending | Select-Object -First 1
                $revenueYear   = $lastFinance.Name
                $latestRevenue = $lastFinance.Value.ca
            }
        }

        $siege = $item.siege

        [PSCustomObject]@{
            'Company Name'            = if ($item.nom_complet)     { $item.nom_complet } else { 'N/A' }
            'SIREN'                   = if ($item.siren)           { $item.siren } else { 'N/A' }
            'Website'                 = if ($item.site_internet)   { $item.site_internet } else { '' }
            'Main Activity'           = $code
            'Business Sector'         = $sector
            'Detailed Sector'         = $detSector
            'HQ Address'              = if ($siege.adresse)             { $siege.adresse } else { 'N/A' }
            'Zip Code'                = if ($siege.code_postal)         { $siege.code_postal } else { '' }
            'Department'              = if ($siege.departement)         { $siege.departement } else { '' }
            'Region Code'             = if ($siege.region)              { $siege.region } else { '' }
            'Employee Bracket'        = if ($siege.tranche_effectif_salarie) { $siege.tranche_effectif_salarie } else { '' }
            'Number of Establishments' = if ($null -ne $item.nombre_etablissements) { $item.nombre_etablissements } else { 0 }
            'Revenue Year'            = $revenueYear
            'Latest Revenue'          = $latestRevenue
        }
    }
}

function Get-SkippedEnterprises {
    <#
    .SYNOPSIS
        Log les entreprises dont le siège est hors zone cible.
    #>
    param(
        [array]$Results,
        [string]$FilterField,
        [string]$FilterValue
    )

    foreach ($item in $Results) {
        $fieldVal = if ($item.siege) { $item.siege.$FilterField } else { $null }
        if ($fieldVal -ne $FilterValue) {
            $company    = if ($item.nom_complet) { $item.nom_complet } else { 'Unknown' }
            $hqLocation = if ($fieldVal)         { $fieldVal } else { 'Unknown' }
            $host.UI.WriteErrorLine("     Skipped $company (HQ in $hqLocation)")
        }
    }
}

function Count-MatchingEnterprises {
    <#
    .SYNOPSIS
        Compte les entreprises matchant le filtre dans un résultat page.
    #>
    param(
        [array]$Results,
        [string]$FilterField,
        [string]$FilterValue
    )

    return ($Results | Where-Object { $_.siege.$FilterField -eq $FilterValue }).Count
}

# ============================================================
# Core API fetch + export function
# ============================================================

function Invoke-EnterpriseApi {
    <#
    .SYNOPSIS
        Boucle de pagination API avec retry, log et export CSV.
    #>
    param(
        [string]$FilterField,
        [string]$FilterValue,
        [string]$Label,
        [string]$EmployeeFilter = $script:TRANCHES_EFFECTIF
    )

    $page = 1
    Write-Host "=== Processing $Label ==="

    while ($true) {
        Write-Host "  -> API call for $Label, page $page..."
        Start-Sleep -Seconds 3

        # Construire les paramètres de la requête
        $queryParams = @{
            ca_min    = $script:CA_MIN
            minimal   = 'true'
            include   = 'siege,finances'
            per_page  = $script:PER_PAGE
            page      = $page
        }
        # Ajouter le champ de filtre (region ou departement)
        $queryParams[$FilterField] = $FilterValue

        if ($EmployeeFilter) {
            $queryParams['tranche_effectif_salarie'] = $EmployeeFilter
        }

        # Boucle de retry (5 tentatives)
        $success = $false
        $resp = $null
        for ($retry = 0; $retry -lt 5; $retry++) {
            try {
                $resp = Invoke-RestMethod -Uri $script:BASE_URL -Body $queryParams `
                    -Method Get -UserAgent $script:UA -ContentType 'application/json' `
                    -ErrorAction Stop
                if ($resp) { $success = $true; break }
            }
            catch [System.Net.WebException] {
                $statusCode = $_.Exception.Response.StatusCode.value__
                if ($statusCode -eq 429) {
                    $waitTime = ($retry + 1) * 15
                    Write-Host "  !! Rate limit (429), waiting ${waitTime}s..." -ForegroundColor Red
                    Start-Sleep -Seconds $waitTime
                }
                else {
                    Write-Host "  !! HTTP Error $statusCode on $Label, page $page. Retrying..." -ForegroundColor Red
                    Start-Sleep -Seconds 5
                }
            }
            catch {
                Write-Host "  !! Connection error on $Label, page $page. Retrying..." -ForegroundColor Red
                Start-Sleep -Seconds 5
            }
        }

        if (-not $success) {
            Write-Host "  !! Failed to fetch $Label, page $page after 5 attempts. Skipping." -ForegroundColor Red
            break
        }

        $totalPages = if ($resp.total_pages) { $resp.total_pages } else { 1 }
        $rawCount   = if ($resp.results)     { $resp.results.Count } else { 0 }

        Write-Host "     Received $rawCount raw results (Total pages: $totalPages)"

        if ($rawCount -eq 0) { break }

        # Log skipped companies
        Get-SkippedEnterprises -Results $resp.results -FilterField $FilterField -FilterValue $FilterValue

        # Export CSV rows
        ConvertFrom-EnterpriseToCsv -Results $resp.results -FilterField $FilterField -FilterValue $FilterValue

        $nbMatch = Count-MatchingEnterprises -Results $resp.results -FilterField $FilterField -FilterValue $FilterValue
        Write-Host "     Exported $nbMatch matching HQs from this page."

        if ($page -ge $totalPages) {
            Write-Host "=== End of $Label ($page pages) ==="
            break
        }
        $page++
    }
}

# ============================================================
# Export mode definitions
# ============================================================

$script:CSV_HEADER = "Company Name,SIREN,Website,Main Activity,Business Sector,Detailed Sector,HQ Address,Zip Code,Department,Region Code,Employee Bracket,Number of Establishments,Revenue Year,Latest Revenue"

# -----------------------------------------------------------
# Mode: aura_bfc
# AURA (84) + BFC (27) regions by region code
# Output: entreprises_aura_bfc_<date>.csv
# -----------------------------------------------------------
function Run-AuraBfc {
    $date = Get-Date -Format yyyyMMdd
    $outputFile = "entreprises_aura_bfc_$date.csv"
    Write-Host "--- Exporting AURA + BFC data to $outputFile (HQ only) ---"
    Set-Content -Path $outputFile -Value $script:CSV_HEADER -Encoding UTF8
    foreach ($reg in @('84','27')) {
        Invoke-EnterpriseApi -FilterField 'region' -FilterValue $reg -Label "region $reg" |
            ConvertTo-Csv -NoTypeInformation |
            Select-Object -Skip 1 |
            Out-File -FilePath $outputFile -Encoding UTF8 -Append
    }
}

# -----------------------------------------------------------
# Mode: aura-69
# AURA region excluding Rhône (département 69)
# 11 departments: 01,03,07,15,26,38,42,43,63,73,74
# Output: export_aura_excl_69_<date>.csv
# -----------------------------------------------------------
function Run-AuraExcl69 {
    $date = Get-Date -Format yyyyMMdd
    $outputFile = "export_aura_excl_69_$date.csv"
    Write-Host "--- Exporting AURA (excl 69) data to $outputFile (HQ only) ---"
    Set-Content -Path $outputFile -Value $script:CSV_HEADER -Encoding UTF8
    foreach ($dep in @('01','03','07','15','26','38','42','43','63','73','74')) {
        Invoke-EnterpriseApi -FilterField 'departement' -FilterValue $dep -Label "dept $dep" |
            ConvertTo-Csv -NoTypeInformation |
            Select-Object -Skip 1 |
            Out-File -FilePath $outputFile -Encoding UTF8 -Append
    }
}

# -----------------------------------------------------------
# Mode: bfc
# Bourgogne-Franche-Comté (8 departments)
# 21,25,39,58,70,71,89,90
# Output: export_bfc_<date>.csv
# -----------------------------------------------------------
function Run-Bfc {
    $date = Get-Date -Format yyyyMMdd
    $outputFile = "export_bfc_$date.csv"
    Write-Host "--- Exporting BFC data to $outputFile (HQ only) ---"
    Set-Content -Path $outputFile -Value $script:CSV_HEADER -Encoding UTF8
    foreach ($dep in @('21','25','39','58','70','71','89','90')) {
        Invoke-EnterpriseApi -FilterField 'departement' -FilterValue $dep -Label "dept $dep" |
            ConvertTo-Csv -NoTypeInformation |
            Select-Object -Skip 1 |
            Out-File -FilePath $outputFile -Encoding UTF8 -Append
    }
}

# -----------------------------------------------------------
# Mode: 69
# Rhône département 69 only
# Output: export_dept_69_<date>.csv
# -----------------------------------------------------------
function Run-Dept69 {
    $date = Get-Date -Format yyyyMMdd
    $outputFile = "export_dept_69_$date.csv"
    Write-Host "--- Exporting Dept 69 data to $outputFile (HQ only) ---"
    Set-Content -Path $outputFile -Value $script:CSV_HEADER -Encoding UTF8
    Invoke-EnterpriseApi -FilterField 'departement' -FilterValue '69' -Label 'dept 69' |
        ConvertTo-Csv -NoTypeInformation |
        Select-Object -Skip 1 |
        Out-File -FilePath $outputFile -Encoding UTF8 -Append
}

# -----------------------------------------------------------
# Mode: all
# Runs all four exports sequentially
# -----------------------------------------------------------
function Run-AllExports {
    Run-AuraBfc
    Run-AuraExcl69
    Run-Bfc
    Run-Dept69
}

# ============================================================
# Help display
# ============================================================

function Show-Help {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
}

# ============================================================
# Argument resolution
# ============================================================

if ($Help) {
    Show-Help
    exit 0
}

# Resolve mode: priority -t > positional
$resolvedMode = if ($Type) { $Type } else { $Mode }

if (-not $resolvedMode) {
    Write-Host "Error: No mode specified." -ForegroundColor Red
    Write-Host ""
    Show-Help
    exit 1
}

# ============================================================
# Run — dispatch to the selected mode
# ============================================================

switch ($resolvedMode) {
    'aura_bfc' { Run-AuraBfc }
    'aura-69'  { Run-AuraExcl69 }
    'bfc'      { Run-Bfc }
    '69'       { Run-Dept69 }
    'all'      { Run-AllExports }
    default {
        Write-Host "Error: Unknown mode '$resolvedMode'" -ForegroundColor Red
        Write-Host ""
        Show-Help
        exit 1
    }
}

Write-Host "=== Export complete ==="