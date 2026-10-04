#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
trap 'rm -rf -- "$task_tmp"' EXIT
source "$ROOT_DIR/lib/station-logo-worker.sh"
source "$ROOT_DIR/lib/lock.sh"
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
mkdir "$task_tmp/cache" "$task_tmp/job"
pixels=$(printf '%036864d' 0); pixels=${pixels//0/A}
printf 'keila-logo-v1\n%s\n%0864d\n' "$pixels" 0 > "$task_tmp/valid"
url=https://radio.example/live
jq -n --arg url "$url" '[
    {name:"Radio Prueba",url:$url,homepage:"https://brand.example/",countrycode:"ES",favicon:"https://img.example/rejected.svg"},
    {name:"Radio Prueba",url:$url,homepage:"https://brand.example/",countrycode:"ES",favicon:"https://img.example/second.webp"},
    {name:"Radio Prueba",url:$url,homepage:"https://brand.example/",countrycode:"ES",favicon:"https://img.example/second.webp"}
]' > "$task_tmp/catalog"
fetches=()
logo_fetch() { fetches+=("$1"); printf '%s' "$1" > "$2/image"; }
logo_convert() {
    [[ $(<"$1/image") == https://img.example/second.webp ]] || return 1
    cp "$task_tmp/valid" "$1/result"
}
logo_worker "$url" "$task_tmp/catalog" "$task_tmp/cache" "$task_tmp/job" 'Radio Prueba' || fail alternativas
[[ ${#fetches[@]} == 2 && ${fetches[1]} == https://img.example/second.webp ]] || fail 'no prueba segundo candidato o repite URL'

# Coincidencia de nombre solo si no hay conflicto de país/sitio. Sin substring.
jq -n '[
    {name:"RAC 1",url:"https://new.example/stream",homepage:"https://www.rac.example/",countrycode:"ES",favicon:"https://img.example/rac.png"},
    {name:"RAC105",url:"https://other.example/stream",homepage:"https://www.rac105.example/",countrycode:"ES",favicon:"https://img.example/wrong.png"}
]' > "$task_tmp/catalog"
rows=$(logo_catalog_candidates https://old.example/stream "$task_tmp/catalog" RAC1) || fail nombre
[[ $rows == *rac.png* && $rows != *wrong.png* ]] || fail 'nombre normalizado confunde RAC1/RAC105'
jq '. + [{name:"RAC1",url:"https://foreign.example/stream",homepage:"https://foreign.example/",countrycode:"FR",favicon:"https://img.example/foreign.png"}]' "$task_tmp/catalog" > "$task_tmp/ambiguous"
[[ -z $(logo_catalog_candidates https://old.example/stream "$task_tmp/ambiguous" RAC1) ]] || fail 'acepta identidad ambigua'
jq -n '[{name:"RNE Radio 5",url:"https://new.example/radio5",homepage:"https://www.rtve.example/",countrycode:"ES",favicon:"https://img.example/rne.png"}]' > "$task_tmp/catalog"
[[ $(logo_catalog_candidates https://old.example/radio5 "$task_tmp/catalog" 'Radio 5 RNE') == *rne.png* ]] || fail 'alias RNE seguro'
jq -n '[{name:"Pop",url:"https://radio.example/listen?station=pop",favicon:"https://img.example/pop.png"}]' > "$task_tmp/catalog"
[[ -z $(logo_catalog_candidates 'https://radio.example/listen?station=rock' "$task_tmp/catalog") ]] || fail 'borra query que identifica emisora'

# HTML estático, orden de atributos, multilinea, ampersand y límite de enlaces.
printf '%s\n' '<head><link href="/favicon.ico" rel="shortcut icon">' \
    "<link rel='apple-touch-icon'" "href='/apple.png?a=1&amp;b=2'>" \
    '<link rel="stylesheet" href="/wrong.css"></head><link rel="icon" href="/body.png">' > "$task_tmp/page"
icons=$(logo_homepage_icons "$task_tmp/page")
[[ $icons == $'/apple.png?a=1&b=2\n/favicon.ico' ]] || fail 'enlaces estáticos incorrectos'

jq -n --arg url "$url" '[{name:"Prueba",url:$url,homepage:"https://brand.example/",favicon:""}]' > "$task_tmp/catalog"
mkdir "$task_tmp/home-job" "$task_tmp/home-cache"
logo_fetch() {
    fetches+=("$1")
    case $1 in
        https://brand.example/) cp "$task_tmp/page" "$2/image" ;;
        'https://brand.example/apple.png?a=1&b=2') printf 'valid' > "$2/image" ;;
        *) return 1 ;;
    esac
}
logo_convert() { [[ $(<"$1/image") == valid ]] && cp "$task_tmp/valid" "$1/result"; }
logo_worker "$url" "$task_tmp/catalog" "$task_tmp/home-cache" "$task_tmp/home-job" Prueba || fail 'favicon de homepage'
[[ ${fetches[-1]} == 'https://brand.example/apple.png?a=1&b=2' ]] || fail 'resolución relativa'

# Raíz sin barra y ruta final tras redirigir: el icono es relativo al documento.
printf '<head><link rel="icon" href="logo.png"></head>' > "$task_tmp/page"
for scenario in root redirect; do
    mkdir "$task_tmp/$scenario-job" "$task_tmp/$scenario-cache"
    jq -n --arg url "$url" '[{name:"Prueba",url:$url,homepage:"https://brand.example",favicon:""}]' > "$task_tmp/catalog"
    expected=https://brand.example/logo.png
    [[ $scenario != redirect ]] || expected='https://brand.example/es/logo.png'
    logo_fetch() {
        fetches+=("$1")
        case $1 in
            https://brand.example)
                [[ $scenario != redirect ]] || LOGO_FETCH_URL='https://brand.example/es/index.html?version=1'
                cp "$task_tmp/page" "$2/image" ;;
            "$expected") printf valid > "$2/image" ;;
            *) return 1 ;;
        esac
    }
    logo_worker "$url" "$task_tmp/catalog" "$task_tmp/$scenario-cache" "$task_tmp/$scenario-job" Prueba || fail "icono relativo: $scenario"
    [[ ${fetches[-1]} == "$expected" ]] || fail "base de documento: $scenario"
done
printf 'ok   logos: alternativas, identidad conservadora, query intacta e iconos estáticos\n'
