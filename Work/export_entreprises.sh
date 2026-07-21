#!/bin/bash
# export_entreprises.sh — Combined export script
# https://github.com/yannoux10/public
# Revenue >= 20 M€, custom columns + logs, HQ only
# Version 2.0: Unified script with mode selection
#
# Usage:
#   ./export_entreprises.sh <mode> [options]
#
# Modes:
#   aura_bfc       AURA + BFC regions (by region code)
#   aura-69        AURA excluding Rhône (département 69)
#   bfc            Bourgogne-Franche-Comté (by department)
#   69             Rhône (département 69) only
#   all            Run all four exports sequentially
#
# Options:
#   -t, --type TYPE         Export type (aura_bfc, aura-69, bfc, 69, all)
#   -e, --employees CODES   Filter by employee bracket (comma-separated)
#   -h, --help              Show this help message
#
# Employee bracket codes:
#   NN (aucun salarié)       00 (0 salarié)
#   01 (1-2 sal.)            02 (3-5 sal.)
#   03 (6-9 sal.)            11 (10-19 sal.)
#   12 (20-49 sal.)          21 (50-99 sal.)
#   22 (100-199 sal.)        31 (200-249 sal.)
#   32 (250-499 sal.)        41 (500-999 sal.)
#   42 (1000-1999 sal.)      51 (2000-4999 sal.)
#   52 (5000-9999 sal.)      53 (10000+ sal.)
#
# Examples:
#   ./export_entreprises.sh aura_bfc
#   ./export_entreprises.sh -t aura-69
#   ./export_entreprises.sh bfc -e "21,22,31,32,41,42,51,52,53"
#   ./export_entreprises.sh all -e "31,32,41,42,51,52,53"
#   TRANCHES_EFFECTIF="21,22,31,32" ./export_entreprises.sh 69

# ============================================================
# Configuration
# ============================================================
BASE_URL="https://recherche-entreprises.api.gouv.fr/search"
UA="BashScript/2.0 (yann.ropars@gmail.com)"
CA_MIN=20000000      # 20 M€
PER_PAGE=25          # max 25

# Employee filter — can be set via env var or -e flag
TRANCHES_EFFECTIF="${TRANCHES_EFFECTIF:-}"

# ============================================================
# Helper functions
# ============================================================

usage() {
  sed -n '/^# Usage:/,/^$/ s/^# //p' "$0"
  exit 0
}

# Common jq transformation: extract CSV rows from API response
# Arguments: $1 = filter field name ("region" or "departement"), $2 = filter value
# Reads JSON from stdin, outputs CSV to stdout
jq_transform() {
  local filter_field="$1"
  local filter_value="$2"

  jq -r --arg fld "$filter_field" --arg val "$filter_value" '
    def get_sector(code):
      (if (code | type) == "string" and (code | length) >= 2 then code[0:2] | tonumber? // 0 else 0 end) as $div
      | if $div >= 1 and $div <= 3 then "Agriculture, forestry and fishing"
        elif $div >= 5 and $div <= 9 then "Mining and quarrying"
        elif $div >= 10 and $div <= 33 then "Manufacturing"
        elif $div == 35 then "Electricity, gas, steam and air conditioning supply"
        elif $div >= 36 and $div <= 39 then "Water supply; sewerage, waste management and remediation activities"
        elif $div >= 41 and $div <= 43 then "Construction"
        elif $div >= 45 and $div <= 47 then "Wholesale and retail trade; repair of motor vehicles and motorcycles"
        elif $div >= 49 and $div <= 53 then "Transportation and storage"
        elif $div >= 55 and $div <= 56 then "Accommodation and food service activities"
        elif $div >= 58 and $div <= 63 then "Information and communication"
        elif $div >= 64 and $div <= 66 then "Financial and insurance activities"
        elif $div == 68 then "Real estate activities"
        elif $div >= 69 and $div <= 75 then "Professional, scientific and technical activities"
        elif $div >= 77 and $div <= 82 then "Administrative and support service activities"
        elif $div == 84 then "Public administration and defence; compulsory social security"
        elif $div == 85 then "Education"
        elif $div >= 86 and $div <= 88 then "Human health and social work activities"
        elif $div >= 90 and $div <= 93 then "Arts, entertainment and recreation"
        elif $div >= 94 and $div <= 96 then "Other service activities"
        elif $div >= 97 and $div <= 98 then "Activities of households as employers"
        elif $div == 99 then "Activities of extraterritorial organisations and bodies"
        else "Unknown"
        end;

    def get_detailed_sector(code):
      (if (code | type) == "string" and (code | length) >= 2 then code[0:2] | tonumber? // 0 else 0 end) as $div
      | if $div >= 1 and $div <= 3 then "Agriculture, Forestry and Fishing"
        elif $div >= 5 and $div <= 9 then "Mining and Quarrying"
        elif $div >= 10 and $div <= 12 then "Manufacturing: Food, Beverages and Tobacco"
        elif $div >= 13 and $div <= 15 then "Manufacturing: Textiles, Apparel and Leather"
        elif $div >= 16 and $div <= 18 then "Manufacturing: Wood, Paper and Printing"
        elif $div >= 19 and $div <= 21 then "Manufacturing: Chemicals, Pharma and Petroleum"
        elif $div >= 22 and $div <= 23 then "Manufacturing: Rubber, Plastic and Minerals"
        elif $div >= 24 and $div <= 25 then "Manufacturing: Basic Metals and Fabricated Products"
        elif $div >= 26 and $div <= 28 then "Manufacturing: Electronics, Electrical and Machinery"
        elif $div >= 29 and $div <= 30 then "Manufacturing: Transport Equipment"
        elif $div >= 31 and $div <= 33 then "Manufacturing: Furniture and Other"
        elif $div == 35 then "Electricity, Gas, Steam and Air Conditioning"
        elif $div >= 36 and $div <= 39 then "Water, Waste and Remediation"
        elif $div >= 41 and $div <= 43 then "Construction"
        elif $div == 45 then "Trade: Motor Vehicles and Repair"
        elif $div == 46 then "Trade: Wholesale (except Motor Vehicles)"
        elif $div == 47 then "Trade: Retail (except Motor Vehicles)"
        elif $div >= 49 and $div <= 53 then "Transportation and Storage"
        elif $div >= 55 and $div <= 56 then "Accommodation and Food Services"
        elif $div >= 58 and $div <= 60 then "Communication: Media and Publishing"
        elif $div == 61 then "Communication: Telecommunications"
        elif $div >= 62 and $div <= 63 then "Information Technology and Services"
        elif $div >= 64 and $div <= 66 then "Financial and Insurance"
        elif $div == 68 then "Real Estate"
        elif $div >= 69 and $div <= 71 then "Professional: Legal, Consulting, Engineering"
        elif $div == 72 then "Professional: Research and Development"
        elif $div >= 73 and $div <= 75 then "Professional: Other Technical"
        elif $div >= 77 and $div <= 82 then "Administrative and Support"
        elif $div == 84 then "Public Administration"
        elif $div == 85 then "Education"
        elif $div >= 86 and $div <= 88 then "Human Health and Social Work"
        elif $div >= 90 and $div <= 93 then "Arts, Entertainment and Recreation"
        elif $div >= 94 and $div <= 99 then "Other Services"
        else "Unknown"
        end;

    .results // [] | .[]
    | select(.siege?[$fld] | tostring == $val)
    | . as $ent
    | ($ent.finances // {}) as $fin
    | ($ent.activite_principale // "") as $code
    | get_sector($code) as $sector
    | get_detailed_sector($code) as $det_sector
    | if ($fin | keys | length) == 0 then
        [
          ($ent.nom_complet // "N/A"),
          ($ent.siren // "N/A"),
          ($ent.site_internet // ""),
          $code,
          $sector,
          $det_sector,
          ($ent.siege?.adresse // "N/A"),
          ($ent.siege?.code_postal // ""),
          ($ent.siege?.departement // ""),
          ($ent.siege?.region // ""),
          ($ent.siege?.tranche_effectif_salarie // ""),
          ($ent.nombre_etablissements // 0 | tostring),
          "",
          ""
        ]
      else
        (
          $fin
          | to_entries
          | sort_by(.key)
          | last
        ) as $last
        | [
            ($ent.nom_complet // "N/A"),
            ($ent.siren // "N/A"),
            ($ent.site_internet // ""),
            $code,
            $sector,
            $det_sector,
            ($ent.siege?.adresse // "N/A"),
            ($ent.siege?.code_postal // ""),
            ($ent.siege?.departement // ""),
            ($ent.siege?.region // ""),
            ($ent.siege?.tranche_effectif_salarie // ""),
            ($ent.nombre_etablissements // 0 | tostring),
            ($last.key // ""),
            ($last.value.ca // "")
          ]
      end
    | @csv
  ' 2>/dev/null
}

# Log skipped companies (those whose HQ is outside the target area)
# Arguments: $1 = filter field name, $2 = filter value
jq_skipped() {
  local filter_field="$1"
  local filter_value="$2"

  jq -r --arg fld "$filter_field" --arg val "$filter_value" '
    .results[] | select(.siege?[$fld] | tostring != $val)
    | "     Skipped \(.nom_complet // "Unknown") (HQ in \(.siege?[$fld] // "Unknown"))"
  ' 2>/dev/null >&2
}

# Count matching rows in a page
# Arguments: $1 = filter field name, $2 = filter value
jq_count() {
  local filter_field="$1"
  local filter_value="$2"

  jq -r --arg fld "$filter_field" --arg val "$filter_value" '
    .results // [] | .[] | select(.siege?[$fld] | tostring == $val) | 1
  ' 2>/dev/null | wc -l
}

# ============================================================
# Core API fetch + export function
# ============================================================
# Arguments:
#   $1 = filter field name ("region" or "departement")
#   $2 = filter value (e.g. "84" or "69")
#   $3 = label for stderr logging (e.g. "region 84" or "dept 69")
# Reads: TRANCHES_EFFECTIF (global)
# Writes CSV rows to stdout, logs to stderr
fetch_and_export() {
  local filter_field="$1"
  local filter_value="$2"
  local label="$3"

  local PAGE=1

  echo "=== Processing $label ===" >&2

  while :; do
    echo "  → API call for $label, page $PAGE..." >&2
    sleep 3

    MAX_RETRIES=5
    RETRY_COUNT=0
    SUCCESS=0
    resp=""

    while (( RETRY_COUNT < MAX_RETRIES )); do
      tmp_file=$(mktemp)

      FILTERS="${filter_field}=${filter_value}&ca_min=${CA_MIN}&minimal=true&include=siege,finances&per_page=${PER_PAGE}&page=${PAGE}"
      if [[ -n "$TRANCHES_EFFECTIF" ]]; then
        FILTERS+="&tranche_effectif_salarie=${TRANCHES_EFFECTIF}"
      fi

      http_code=$(curl -sS -L --compressed -o "$tmp_file" -w "%{http_code}" \
        -H "Accept: application/json" \
        -H "User-Agent: $UA" \
        "${BASE_URL}?${FILTERS}")

      resp_content=$(cat "$tmp_file" 2>/dev/null || echo "")
      rm -f "$tmp_file"

      if [[ "$http_code" == "200" ]]; then
        if echo "$resp_content" | jq empty >/dev/null 2>&1; then
          resp="$resp_content"
          SUCCESS=1
          break
        else
          echo "  !! Invalid JSON received on $label, page $PAGE. Retrying..." >&2
        fi
      elif [[ "$http_code" == "429" ]]; then
        wait_time=$(( (RETRY_COUNT + 1) * 15 ))
        echo "  !! Rate limit (429), waiting ${wait_time}s..." >&2
        sleep "$wait_time"
      else
        echo "  !! HTTP Error $http_code on $label, page $PAGE. Retrying..." >&2
        sleep 5
      fi

      ((RETRY_COUNT++))
    done

    if [[ "$SUCCESS" -ne 1 ]]; then
      echo "  !! Failed to fetch $label, page $PAGE after $MAX_RETRIES attempts. Skipping." >&2
      break
    fi

    total_pages=$(echo "$resp" | jq -r '.total_pages // 1' 2>/dev/null || echo "1")
    raw_count=$(echo "$resp" | jq -r '.results // [] | length' 2>/dev/null || echo "0")

    echo "     Received $raw_count raw results (Total pages: $total_pages)" >&2

    if [[ "$raw_count" -eq 0 ]]; then
      break
    fi

    # Log skipped companies
    echo "$resp" | jq_skipped "$filter_field" "$filter_value"

    # Export CSV rows
    echo "$resp" | jq_transform "$filter_field" "$filter_value"

    nb_match=$(echo "$resp" | jq_count "$filter_field" "$filter_value")
    echo "     Exported $nb_match matching HQs from this page." >&2

    if [[ "$PAGE" -ge "$total_pages" ]]; then
      echo "=== End of $label ($PAGE pages) ===" >&2
      break
    fi

    ((PAGE++))
  done
}

# ============================================================
# Export mode definitions
# ============================================================

# -----------------------------------------------------------
# Mode: aura_bfc
# Covers both regions: Auvergne-Rhône-Alpes (84) and Bourgogne-Franche-Comté (27)
# Queries by region code (not by individual departments)
# Output: entreprises_aura_bfc_<date>.csv
# -----------------------------------------------------------
run_aura_bfc() {
  local output_file="entreprises_aura_bfc_$(date +%Y%m%d).csv"
  echo "--- Exporting AURA + BFC data to $output_file (HQ only) ---" >&2
  exec > "$output_file"
  echo "Company Name,SIREN,Website,Main Activity,Business Sector,Detailed Sector,HQ Address,Zip Code,Department,Region Code,Employee Bracket,Number of Establishments,Revenue Year,Latest Revenue"
  for reg in "84" "27"; do
    fetch_and_export "region" "$reg" "region $reg"
  done
}

# -----------------------------------------------------------
# Mode: aura-69
# AURA region (Auvergne-Rhône-Alpes) excluding Rhône département 69
# Covers all 11 AURA departments: 01(Ain), 03(Allier), 07(Ardèche),
# 15(Cantal), 26(Drôme), 38(Isère), 42(Loire), 43(Haute-Loire),
# 63(Puy-de-Dôme), 73(Savoie), 74(Haute-Savoie)
# Output: export_aura_excl_69_<date>.csv
# -----------------------------------------------------------
run_aura_excl_69() {
  local output_file="export_aura_excl_69_$(date +%Y%m%d).csv"
  echo "--- Exporting AURA (excl 69) data to $output_file (HQ only) ---" >&2
  exec > "$output_file"
  echo "Company Name,SIREN,Website,Main Activity,Business Sector,Detailed Sector,HQ Address,Zip Code,Department,Region Code,Employee Bracket,Number of Establishments,Revenue Year,Latest Revenue"
  for dep in "01" "03" "07" "15" "26" "38" "42" "43" "63" "73" "74"; do
    fetch_and_export "departement" "$dep" "dept $dep"
  done
}

# -----------------------------------------------------------
# Mode: bfc
# Bourgogne-Franche-Comté region only
# Covers all 8 BFC departments: 21(Côte-d'Or), 25(Doubs), 39(Jura),
# 58(Nièvre), 70(Haute-Saône), 71(Saône-et-Loire), 89(Yonne),
# 90(Territoire de Belfort)
# Output: export_bfc_<date>.csv
# -----------------------------------------------------------
run_bfc() {
  local output_file="export_bfc_$(date +%Y%m%d).csv"
  echo "--- Exporting BFC data to $output_file (HQ only) ---" >&2
  exec > "$output_file"
  echo "Company Name,SIREN,Website,Main Activity,Business Sector,Detailed Sector,HQ Address,Zip Code,Department,Region Code,Employee Bracket,Number of Establishments,Revenue Year,Latest Revenue"
  for dep in "21" "25" "39" "58" "70" "71" "89" "90"; do
    fetch_and_export "departement" "$dep" "dept $dep"
  done
}

# -----------------------------------------------------------
# Mode: 69
# Rhône département 69 only (Lyon metro area)
# Output: export_dept_69_<date>.csv
# -----------------------------------------------------------
run_dept_69() {
  local output_file="export_dept_69_$(date +%Y%m%d).csv"
  echo "--- Exporting Dept 69 data to $output_file (HQ only) ---" >&2
  exec > "$output_file"
  echo "Company Name,SIREN,Website,Main Activity,Business Sector,Detailed Sector,HQ Address,Zip Code,Department,Region Code,Employee Bracket,Number of Establishments,Revenue Year,Latest Revenue"
  fetch_and_export "departement" "69" "dept 69"
}

# -----------------------------------------------------------
# Mode: all
# Runs all four exports sequentially, each to its own file.
# -----------------------------------------------------------
run_all() {
  run_aura_bfc
  run_aura_excl_69
  run_bfc
  run_dept_69
}

# ============================================================
# Argument parsing
# ============================================================
# Usage: ./export_entreprises.sh <mode> [options]
#
# Modes (positional or -t argument, required):
#   aura_bfc       AURA + BFC regions (by region code 84 + 27)
#   aura-69        AURA excluding Rhône (region 84, excl 69)
#   bfc            Bourgogne-Franche-Comté (region 27)
#   69             Rhône département 69 only
#   all            Run all four exports sequentially
#
# Options:
#   -t, --type TYPE         Export type (aura_bfc, aura-69, bfc, 69, all)
#   -e, --employees CODES   Filter by employee bracket (comma-separated).
#                           Codes: 01 (1-2), 02 (3-5), 03 (6-9), 11 (10-19),
#                           12 (20-49), 21 (50-99), 22 (100-199), 31 (200-249),
#                           32 (250-499), 41 (500-999), 42 (1000-1999),
#                           51 (2000-4999), 52 (5000-9999), 53 (10000+)
#                           Example: -e "21,22,31,32" = 50-499 employees
#                           Can also be set via env var: TRANCHES_EFFECTIF="..."
#   -h, --help              Show this help message and exit

MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -e|--employees)
      shift
      TRANCHES_EFFECTIF="$1"
      ;;
    -t|--type)
      shift
      if [[ -n "$MODE" ]]; then
        echo "Error: Multiple modes specified. Pick one." >&2
        usage
      fi
      MODE="$1"
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      usage
      ;;
    *)
      if [[ -n "$MODE" ]]; then
        echo "Error: Multiple modes specified. Pick one." >&2
        usage
      fi
      MODE="$1"
      ;;
  esac
  shift
done

if [[ -z "$MODE" ]]; then
  echo "Error: No mode specified." >&2
  echo "" >&2
  usage
fi

# ============================================================
# Run — dispatch to the selected mode
# ============================================================
# Each mode function:
#   - Creates its own output file (redirects stdout with exec >)
#   - Writes the CSV header
#   - Iterates over regions or departments, calling fetch_and_export
#   - Logs progress to stderr

case "$MODE" in
  aura_bfc)
    run_aura_bfc
    ;;
  aura-69)
    run_aura_excl_69
    ;;
  bfc)
    run_bfc
    ;;
  69)
    run_dept_69
    ;;
  all)
    run_all
    ;;
  *)
    echo "Error: Unknown mode '$MODE'" >&2
    usage
    ;;
esac

echo "=== Export complete ===" >&2