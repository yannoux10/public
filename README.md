# Export Entreprises France

Exporte les entreprises françaises (CA ≥ 20 M€) depuis l'API publique
[recherche-entreprises.api.gouv.fr](https://recherche-entreprises.api.gouv.fr).
Filtre par région/département, avec classification NAF et données financières.

## Scripts disponibles

| Script | Usage | Dépendances |
|--------|-------|-------------|
| `export_entreprises.sh` | Linux / Mac / WSL | `bash`, `curl`, `jq` |
| `export_entreprises.ps1` | Windows (PowerShell 5.1+) | Aucune |

Les deux produisent des fichiers CSV identiques avec les mêmes options.

## Modes d'export

| Mode | Périmètre | Source |
|------|-----------|--------|
| `aura_bfc` | AURA (84) + BFC (27) | 2 appels région |
| `aura-69` | AURA sans le Rhône (11 dépt.) | 11 appels département |
| `bfc` | Bourgogne-Franche-Comté (8 dépt.) | 8 appels département |
| `69` | Rhône uniquement | 1 appel département |
| `all` | Les 4 exports à la suite | Tous les appels |

## Fichiers générés

```
entreprises_aura_bfc_20260721.csv
export_aura_excl_69_20260721.csv
export_bfc_20260721.csv
export_dept_69_20260721.csv
```

Chaque fichier contient 14 colonnes : Company Name, SIREN, Website,
Main Activity, Business Sector, Detailed Sector, HQ Address, Zip Code,
Department, Region Code, Employee Bracket, Number of Establishments,
Revenue Year, Latest Revenue.

## Utilisation

### Bash (Linux / Mac / WSL)

```bash
# Modes simples
./export_entreprises.sh aura_bfc
./export_entreprises.sh 69

# Avec option -t
./export_entreprises.sh -t aura-69

# Filtre par tranche d'effectif
./export_entreprises.sh bfc -e "21,22,31,32,41,42,51,52,53"

# Variable d'environnement
TRANCHES_EFFECTIF="31,32" ./export_entreprises.sh 69

# Aide
./export_entreprises.sh -h
```

### PowerShell (Windows)

> ⚠️ **Premier lancement ?** Si PowerShell refuse le script avec
> `"l'exécution de scripts est désactivée"`, lancez dans une console
> **Administrateur** :
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```
> Ou sans changer la politique, utilisez :
> ```cmd
> powershell -ExecutionPolicy Bypass -File .\export_entreprises.ps1
> ```

```powershell
# Modes simples
.\export_entreprises.ps1 aura_bfc
.\export_entreprises.ps1 69

# Avec option -t
.\export_entreprises.ps1 -t aura-69

# Filtre par tranche d'effectif
.\export_entreprises.ps1 bfc -e "21,22,31,32,41,42,51,52,53"

# Variable d'environnement
$env:TRANCHES_EFFECTIF = "31,32"; .\export_entreprises.ps1 69

# Aide
.\export_entreprises.ps1 -h
```

## Codes tranche d'effectif

| Code | Tranche |
|------|---------|
| `NN` | Aucun salarié |
| `00` | 0 salarié |
| `01` | 1–2 sal. |
| `02` | 3–5 sal. |
| `03` | 6–9 sal. |
| `11` | 10–19 sal. |
| `12` | 20–49 sal. |
| `21` | 50–99 sal. |
| `22` | 100–199 sal. |
| `31` | 200–249 sal. |
| `32` | 250–499 sal. |
| `41` | 500–999 sal. |
| `42` | 1000–1999 sal. |
| `51` | 2000–4999 sal. |
| `52` | 5000–9999 sal. |
| `53` | 10000+ sal. |

Exemple : `-e "21,22,31,32"` filtre les entreprises de 50 à 499 salariés.

## Configuration

Les paramètres par défaut sont modifiables en tête de script :

| Variable | Défaut | Description |
|----------|--------|-------------|
| `CA_MIN` | `20 000 000` | CA minimum en € |
| `PER_PAGE` | `25` | Résultats par page (max 25) |
| `BASE_URL` | `https://recherche-entreprises.api.gouv.fr/search` | API endpoint |
