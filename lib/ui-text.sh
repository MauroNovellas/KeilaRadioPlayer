#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Celdas, no caracteres: tablas Unicode 15.1 (East Asian Width W/F y Mn/Me/Cf).
# Datos estáticos; sin Python, jq ni procesos durante el dibujo.
UI_TEXT_WIDE=$'\u1100-\u115f\u231a-\u231b\u2329-\u232a\u23e9-\u23ec\u23f0\u23f3\u25fd-\u25fe\u2614-\u2615\u2648-\u2653\u267f\u2693\u26a1\u26aa-\u26ab\u26bd-\u26be\u26c4-\u26c5\u26ce\u26d4\u26ea\u26f2-\u26f3\u26f5\u26fa\u26fd\u2705\u270a-\u270b\u2728\u274c\u274e\u2753-\u2755\u2757\u2795-\u2797\u27b0\u27bf\u2b1b-\u2b1c\u2b50\u2b55\u2e80-\u2e99\u2e9b-\u2ef3\u2f00-\u2fd5\u2ff0-\u303e\u3041-\u3096\u3099-\u30ff\u3105-\u312f\u3131-\u318e\u3190-\u31e3\u31ef-\u321e\u3220-\u3247\u3250-\u4dbf\u4e00-\ua48c\ua490-\ua4c6\ua960-\ua97c\uac00-\ud7a3\uf900-\ufa6d\ufa70-\ufad9\ufe10-\ufe19\ufe30-\ufe52\ufe54-\ufe66\ufe68-\ufe6b\uff01-\uff60\uffe0-\uffe6\U00016fe0-\U00016fe4\U00016ff0-\U00016ff1\U00017000-\U000187f7\U00018800-\U00018cd5\U00018d00-\U00018d08\U0001aff0-\U0001aff3\U0001aff5-\U0001affb\U0001affd-\U0001affe\U0001b000-\U0001b122\U0001b132\U0001b150-\U0001b152\U0001b155\U0001b164-\U0001b167\U0001b170-\U0001b2fb\U0001f004\U0001f0cf\U0001f18e\U0001f191-\U0001f19a\U0001f200-\U0001f202\U0001f210-\U0001f23b\U0001f240-\U0001f248\U0001f250-\U0001f251\U0001f260-\U0001f265\U0001f300-\U0001f320\U0001f32d-\U0001f335\U0001f337-\U0001f37c\U0001f37e-\U0001f393\U0001f3a0-\U0001f3ca\U0001f3cf-\U0001f3d3\U0001f3e0-\U0001f3f0\U0001f3f4\U0001f3f8-\U0001f43e\U0001f440\U0001f442-\U0001f4fc\U0001f4ff-\U0001f53d\U0001f54b-\U0001f54e\U0001f550-\U0001f567\U0001f57a\U0001f595-\U0001f596\U0001f5a4\U0001f5fb-\U0001f64f\U0001f680-\U0001f6c5\U0001f6cc\U0001f6d0-\U0001f6d2\U0001f6d5-\U0001f6d7\U0001f6dc-\U0001f6df\U0001f6eb-\U0001f6ec\U0001f6f4-\U0001f6fc\U0001f7e0-\U0001f7eb\U0001f7f0\U0001f90c-\U0001f93a\U0001f93c-\U0001f945\U0001f947-\U0001f9ff\U0001fa70-\U0001fa7c\U0001fa80-\U0001fa88\U0001fa90-\U0001fabd\U0001fabf-\U0001fac5\U0001face-\U0001fadb\U0001fae0-\U0001fae8\U0001faf0-\U0001faf8\U00020000-\U0002a6df\U0002a700-\U0002b739\U0002b740-\U0002b81d\U0002b820-\U0002cea1\U0002ceb0-\U0002ebe0\U0002ebf0-\U0002ee5d\U0002f800-\U0002fa1d\U00030000-\U0003134a\U00031350-\U000323af'
UI_TEXT_ZERO=$'\u00ad\u0300-\u036f\u0483-\u0489\u0591-\u05bd\u05bf\u05c1-\u05c2\u05c4-\u05c5\u05c7\u0600-\u0605\u0610-\u061a\u061c\u064b-\u065f\u0670\u06d6-\u06dd\u06df-\u06e4\u06e7-\u06e8\u06ea-\u06ed\u070f\u0711\u0730-\u074a\u07a6-\u07b0\u07eb-\u07f3\u07fd\u0816-\u0819\u081b-\u0823\u0825-\u0827\u0829-\u082d\u0859-\u085b\u0890-\u0891\u0898-\u089f\u08ca-\u0902\u093a\u093c\u0941-\u0948\u094d\u0951-\u0957\u0962-\u0963\u0981\u09bc\u09c1-\u09c4\u09cd\u09e2-\u09e3\u09fe\u0a01-\u0a02\u0a3c\u0a41-\u0a42\u0a47-\u0a48\u0a4b-\u0a4d\u0a51\u0a70-\u0a71\u0a75\u0a81-\u0a82\u0abc\u0ac1-\u0ac5\u0ac7-\u0ac8\u0acd\u0ae2-\u0ae3\u0afa-\u0aff\u0b01\u0b3c\u0b3f\u0b41-\u0b44\u0b4d\u0b55-\u0b56\u0b62-\u0b63\u0b82\u0bc0\u0bcd\u0c00\u0c04\u0c3c\u0c3e-\u0c40\u0c46-\u0c48\u0c4a-\u0c4d\u0c55-\u0c56\u0c62-\u0c63\u0c81\u0cbc\u0cbf\u0cc6\u0ccc-\u0ccd\u0ce2-\u0ce3\u0d00-\u0d01\u0d3b-\u0d3c\u0d41-\u0d44\u0d4d\u0d62-\u0d63\u0d81\u0dca\u0dd2-\u0dd4\u0dd6\u0e31\u0e34-\u0e3a\u0e47-\u0e4e\u0eb1\u0eb4-\u0ebc\u0ec8-\u0ece\u0f18-\u0f19\u0f35\u0f37\u0f39\u0f71-\u0f7e\u0f80-\u0f84\u0f86-\u0f87\u0f8d-\u0f97\u0f99-\u0fbc\u0fc6\u102d-\u1030\u1032-\u1037\u1039-\u103a\u103d-\u103e\u1058-\u1059\u105e-\u1060\u1071-\u1074\u1082\u1085-\u1086\u108d\u109d\u135d-\u135f\u1712-\u1714\u1732-\u1733\u1752-\u1753\u1772-\u1773\u17b4-\u17b5\u17b7-\u17bd\u17c6\u17c9-\u17d3\u17dd\u180b-\u180f\u1885-\u1886\u18a9\u1920-\u1922\u1927-\u1928\u1932\u1939-\u193b\u1a17-\u1a18\u1a1b\u1a56\u1a58-\u1a5e\u1a60\u1a62\u1a65-\u1a6c\u1a73-\u1a7c\u1a7f\u1ab0-\u1ace\u1b00-\u1b03\u1b34\u1b36-\u1b3a\u1b3c\u1b42\u1b6b-\u1b73\u1b80-\u1b81\u1ba2-\u1ba5\u1ba8-\u1ba9\u1bab-\u1bad\u1be6\u1be8-\u1be9\u1bed\u1bef-\u1bf1\u1c2c-\u1c33\u1c36-\u1c37\u1cd0-\u1cd2\u1cd4-\u1ce0\u1ce2-\u1ce8\u1ced\u1cf4\u1cf8-\u1cf9\u1dc0-\u1dff\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u206f\u20d0-\u20f0\u2cef-\u2cf1\u2d7f\u2de0-\u2dff\u302a-\u302d\u3099-\u309a\ua66f-\ua672\ua674-\ua67d\ua69e-\ua69f\ua6f0-\ua6f1\ua802\ua806\ua80b\ua825-\ua826\ua82c\ua8c4-\ua8c5\ua8e0-\ua8f1\ua8ff\ua926-\ua92d\ua947-\ua951\ua980-\ua982\ua9b3\ua9b6-\ua9b9\ua9bc-\ua9bd\ua9e5\uaa29-\uaa2e\uaa31-\uaa32\uaa35-\uaa36\uaa43\uaa4c\uaa7c\uaab0\uaab2-\uaab4\uaab7-\uaab8\uaabe-\uaabf\uaac1\uaaec-\uaaed\uaaf6\uabe5\uabe8\uabed\ufb1e\ufe00-\ufe0f\ufe20-\ufe2f\ufeff\ufff9-\ufffb\U000101fd\U000102e0\U00010376-\U0001037a\U00010a01-\U00010a03\U00010a05-\U00010a06\U00010a0c-\U00010a0f\U00010a38-\U00010a3a\U00010a3f\U00010ae5-\U00010ae6\U00010d24-\U00010d27\U00010eab-\U00010eac\U00010efd-\U00010eff\U00010f46-\U00010f50\U00010f82-\U00010f85\U00011001\U00011038-\U00011046\U00011070\U00011073-\U00011074\U0001107f-\U00011081\U000110b3-\U000110b6\U000110b9-\U000110ba\U000110bd\U000110c2\U000110cd\U00011100-\U00011102\U00011127-\U0001112b\U0001112d-\U00011134\U00011173\U00011180-\U00011181\U000111b6-\U000111be\U000111c9-\U000111cc\U000111cf\U0001122f-\U00011231\U00011234\U00011236-\U00011237\U0001123e\U00011241\U000112df\U000112e3-\U000112ea\U00011300-\U00011301\U0001133b-\U0001133c\U00011340\U00011366-\U0001136c\U00011370-\U00011374\U00011438-\U0001143f\U00011442-\U00011444\U00011446\U0001145e\U000114b3-\U000114b8\U000114ba\U000114bf-\U000114c0\U000114c2-\U000114c3\U000115b2-\U000115b5\U000115bc-\U000115bd\U000115bf-\U000115c0\U000115dc-\U000115dd\U00011633-\U0001163a\U0001163d\U0001163f-\U00011640\U000116ab\U000116ad\U000116b0-\U000116b5\U000116b7\U0001171d-\U0001171f\U00011722-\U00011725\U00011727-\U0001172b\U0001182f-\U00011837\U00011839-\U0001183a\U0001193b-\U0001193c\U0001193e\U00011943\U000119d4-\U000119d7\U000119da-\U000119db\U000119e0\U00011a01-\U00011a0a\U00011a33-\U00011a38\U00011a3b-\U00011a3e\U00011a47\U00011a51-\U00011a56\U00011a59-\U00011a5b\U00011a8a-\U00011a96\U00011a98-\U00011a99\U00011c30-\U00011c36\U00011c38-\U00011c3d\U00011c3f\U00011c92-\U00011ca7\U00011caa-\U00011cb0\U00011cb2-\U00011cb3\U00011cb5-\U00011cb6\U00011d31-\U00011d36\U00011d3a\U00011d3c-\U00011d3d\U00011d3f-\U00011d45\U00011d47\U00011d90-\U00011d91\U00011d95\U00011d97\U00011ef3-\U00011ef4\U00011f00-\U00011f01\U00011f36-\U00011f3a\U00011f40\U00011f42\U00013430-\U00013440\U00013447-\U00013455\U00016af0-\U00016af4\U00016b30-\U00016b36\U00016f4f\U00016f8f-\U00016f92\U00016fe4\U0001bc9d-\U0001bc9e\U0001bca0-\U0001bca3\U0001cf00-\U0001cf2d\U0001cf30-\U0001cf46\U0001d167-\U0001d169\U0001d173-\U0001d182\U0001d185-\U0001d18b\U0001d1aa-\U0001d1ad\U0001d242-\U0001d244\U0001da00-\U0001da36\U0001da3b-\U0001da6c\U0001da75\U0001da84\U0001da9b-\U0001da9f\U0001daa1-\U0001daaf\U0001e000-\U0001e006\U0001e008-\U0001e018\U0001e01b-\U0001e021\U0001e023-\U0001e024\U0001e026-\U0001e02a\U0001e08f\U0001e130-\U0001e136\U0001e2ae\U0001e2ec-\U0001e2ef\U0001e4ec-\U0001e4ef\U0001e8d0-\U0001e8d6\U0001e944-\U0001e94a\U000e0001\U000e0020-\U000e007f\U000e0100-\U000e01ef'
UI_TEXT_COMPLEX=$UI_TEXT_WIDE$UI_TEXT_ZERO
UI_TEXT_NARROW=' -~À-ÿ←-⇿─-▟★☆▶▸'
UI_TEXT_FITTED='' UI_TEXT_WIDTH=0
declare -A UI_TEXT_CACHE=() UI_TEXT_WIDTH_CACHE=()

ui_fit_text() {
    local text=${1//[[:cntrl:]]/ } max=$2 ellipsis=${3:-1} key LC_COLLATE=C
    UI_TEXT_FITTED='' UI_TEXT_WIDTH=0
    ((max > 0)) || return 0
    # La ruta normal (latín, bordes, barras) no recorre caracteres ni usa caché.
    if [[ $text != *[!${UI_TEXT_NARROW}]* || $text != *[${UI_TEXT_COMPLEX}]* ]]; then
        if ((${#text} > max && ellipsis && max > 3)); then UI_TEXT_FITTED="${text:0:max-3}..."
        else UI_TEXT_FITTED=${text:0:max}; fi
        UI_TEXT_WIDTH=${#UI_TEXT_FITTED}
        return 0
    fi
    key="${LC_ALL:-}|${LC_CTYPE:-}|${LANG:-}|$max|$ellipsis|$text"
    if [[ -n ${UI_TEXT_WIDTH_CACHE[$key]+cached} ]]; then
        UI_TEXT_FITTED=${UI_TEXT_CACHE[$key]} UI_TEXT_WIDTH=${UI_TEXT_WIDTH_CACHE[$key]}
        return 0
    fi
    ui_fit_text_uncached "$text" "$max" "$ellipsis"
    if ((${#UI_TEXT_WIDTH_CACHE[@]} >= 256)); then UI_TEXT_CACHE=() UI_TEXT_WIDTH_CACHE=(); fi
    if ((${#text} <= 2048)); then UI_TEXT_CACHE[$key]=$UI_TEXT_FITTED UI_TEXT_WIDTH_CACHE[$key]=$UI_TEXT_WIDTH; fi
}

ui_fit_text_uncached() {
    local text=${1//[[:cntrl:]]/ } max=$2 ellipsis=${3:-1} i char cells last_cells=0 prefix='' prefix_width=0 LC_COLLATE=C
    UI_TEXT_FITTED='' UI_TEXT_WIDTH=0
    ((max > 0)) || return 0
    for ((i=0; i<${#text}; i++)); do
        char=${text:i:1} cells=1
        if [[ $char == [${UI_TEXT_ZERO}] ]]; then
            cells=0
            # VS16 puede convertir un símbolo estrecho (♥) en un emoji ancho.
            [[ $char != $'\ufe0f' || $last_cells != 1 ]] || cells=1
        elif [[ $char == [${UI_TEXT_WIDE}] ]]; then cells=2; fi
        if ((UI_TEXT_WIDTH + cells > max)); then
            if ((ellipsis && max > 3)); then UI_TEXT_FITTED="$prefix..."; UI_TEXT_WIDTH=$((prefix_width+3)); fi
            return 0
        fi
        UI_TEXT_FITTED+=$char
        UI_TEXT_WIDTH=$((UI_TEXT_WIDTH+cells))
        ((cells == 0)) || last_cells=$cells
        if ((UI_TEXT_WIDTH <= max-3)); then prefix=$UI_TEXT_FITTED; prefix_width=$UI_TEXT_WIDTH; fi
    done
}
