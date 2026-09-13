#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -uo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task_tmp=$(mktemp -d) || exit 1
export XDG_CONFIG_HOME="$task_tmp/config" XDG_STATE_HOME="$task_tmp/state" XDG_CACHE_HOME="$task_tmp/cache"
set -- --version
source "$ROOT_DIR/keila-radio" >/dev/null
trap 'logo_cleanup >/dev/null; rm -rf -- "$task_tmp"' EXIT
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
mkdir -p "$task_tmp/job" "$task_tmp/cache/logos"
job=$task_tmp/job cache=$task_tmp/cache/logos
timeout 10s ffmpeg -nostdin -v error -f lavfi -i 'color=c=blue:s=80x40' -frames:v 1 -threads 1 "$task_tmp/source.png" || fail fixture
cp "$task_tmp/source.png" "$job/image"
logo_convert "$job" || fail 'conversión PNG'
logo_read_render "$job/result" || fail 'formato normalizado'
[[ ${#LOGO_PIXELS_BASE64} == 36864 && ${#LOGO_PIXELS_HEX} == 864 ]] || fail dimensiones
printf '%s' "$LOGO_PIXELS_BASE64" | base64 -d > "$task_tmp/decoded"
cmp -s "$task_tmp/decoded" "$job/rgb" || fail 'payload Kitty alterado'
mv "$job/result" "$task_tmp/valid.logo"
mv "$job/rgb" "$task_tmp/png.rgb"; mv "$job/small" "$task_tmp/png.small"
timeout 10s ffmpeg -nostdin -v error -f lavfi -i 'color=c=red:s=32x32' -frames:v 1 -threads 1 "$task_tmp/source.jpg" || fail fixture
cp "$task_tmp/source.jpg" "$job/image"
logo_convert "$job" || fail 'conversión JPEG'
printf '<svg><script>contenido no permitido</script></svg>' > "$job/image"
logo_convert "$job" && fail 'acepta SVG'
truncate -s 1048577 "$job/image"
logo_convert "$job" && fail 'acepta fichero grande'
printf 'keila-logo-v1\n\033[2J\n00\n' > "$task_tmp/corrupt"
logo_read_render "$task_tmp/corrupt" && fail 'acepta escapes almacenados'
ln -s "$task_tmp/valid.logo" "$task_tmp/link.logo"
logo_read_render "$task_tmp/link.logo" && fail 'sigue enlace de caché'

for ip in 127.0.0.1 10.2.3.4 0.0.0.0 172.16.1.1 172.31.0.1 169.254.169.254 192.168.1.3 100.100.100.200 224.0.0.1 256.1.1.1 198.18.1.1 192.0.2.1 203.0.113.8; do
    logo_public_ipv4 "$ip" && fail "IP no pública $ip"
done
logo_public_ipv4 8.8.8.8 || fail 'IPv4 pública'
for url in file:///etc/passwd 'https://user:secret@host/image' 'https://host/image\x' $'https://host/\033evil' 'https://host:99999/logo'; do
    logo_url_parts "$url" && fail "URL insegura $url"
done
logo_url_parts 'https://logos.example/image.png?a=b&c=d' || fail 'URL válida'
[[ $LOGO_HTTP_PORT == 443 && $LOGO_HTTP_HOST == logos.example ]] || fail 'descompone URL'
# Redirección pública a red privada: jamás ejecutar el segundo curl.
logo_resolve() { if [[ $1 == logos.example ]]; then printf '8.8.8.8 STREAM logos.example\n'; else printf '127.0.0.1 STREAM local\n'; fi; }
curl() {
    printf x >> "$task_tmp/fetches"
    [[ " $* " == *' --resolve logos.example:443:8.8.8.8 '* ]] || fail 'DNS no fijado'
    printf '302\nhttp://127.0.0.1/private'
}
logo_fetch https://logos.example/image.png "$job" && fail 'sigue redirección privada'
[[ $(<"$task_tmp/fetches") == x ]] || fail 'accede a red privada'
unset -f curl

# Worker sin red: fallo/éxito de descarga controlados, conversor real.
logo_fetch() { cp "$task_tmp/source.png" "$2/image"; }
url=https://radio.invalid/stream
jq -n --arg url "$url" '[{url:$url,favicon:"https://logos.example/logo.png"}]' > "$task_tmp/catalog.json"
mkdir "$task_tmp/first"
logo_worker "$url" "$task_tmp/catalog.json" "$cache" "$task_tmp/first" || fail worker
key=$(printf '%s' "$url" | sha256sum); key=${key%% *}
[[ -f "$cache/$key.logo" && $(stat -c %a "$cache/$key.logo") == 600 ]] || fail 'caché privada'
logo_fetch() { fail 'repite descarga con caché fresca'; }
mkdir "$task_tmp/hit"
logo_worker "$url" "$task_tmp/catalog.json" "$cache" "$task_tmp/hit" || fail 'no reutiliza caché'
cmp -s "$task_tmp/hit/result" "$task_tmp/first/result" || fail 'hit distinto'
logo_fetch() { cp "$task_tmp/source.png" "$2/image"; }
touch -d '8 days ago' "$cache/$key.logo"
mkdir "$task_tmp/expired"
logo_worker "$url" "$task_tmp/catalog.json" "$cache" "$task_tmp/expired" || fail 'no renueva caché caducada'
# 64 entradas como máximo; solo retirar caché reconocida, no archivos ajenos.
for ((i=1; i<64; i++)); do printf -v name '%064x' "$i"; cp "$task_tmp/valid.logo" "$cache/$name.logo"; done
printf conservar > "$cache/personal.txt"
printf -v name '%064x' 65
logo_cache_store "$cache" "$name" "$task_tmp/valid.logo" || fail publicar
entries=("$cache"/*.logo)
[[ ${#entries[@]} == 64 && $(<"$cache/personal.txt") == conservar ]] || fail 'límite o archivo ajeno'
printf 'ok   logos: PNG/JPEG, caché privada limitada, caducidad, payload y red segura\n'
