# SPDX-License-Identifier: GPL-3.0-or-later
# No confundir cadenas, ediciones locales ni homónimos de países diferentes.
def clean: tostring | gsub("[\u0000-\u001f\u007f|]"; " ") | .[0:160];
def norm: tostring | ascii_downcase | gsub("^ +| +$"; "") | gsub(" +"; " ");
def home:
    if type!="string" or (test("^https?://[^/?#@[:space:]]+([/?#]|$)"; "i")|not) then ""
    else sub("^https?://"; ""; "i") | split("/") as $parts |
         ($parts[0] | ascii_downcase | sub("^www\\."; "")) +
         (if ($parts|length)>1 then "/"+($parts[1:]|join("/")) else "" end) | sub("/+$"; "") end;
def stream_url:
    type=="string" and length<=2048 and test("^https?://([a-zA-Z0-9][a-zA-Z0-9._-]*|\\[[0-9a-fA-F:]+\\])(:[0-9]{1,5})?([/?#]|$)") and
    (test("[|\u0000-\u0020\u007f]")|not) and (contains("\\")|not);
def record:
    {url:(if (.url_resolved|type)=="string" and .url_resolved!="" then .url_resolved else (.url // "") end), original:(.url // ""),
     name:((.name // "") | norm), country:(.countrycode // ""),
     zone:((.state // "") | norm), web:((.homepage // "") | home),
     codec:((.codec // "") | clean), bits:((.bitrate // 0) | if type=="number" then . * 1000 else 0 end), hls:(.hls // 0)};
def choice($r; $kind):
    {url:$r.url,rate:0,codec:$r.codec,bits:(if ($r.bits|type)=="number" and $r.bits>=0 and $r.bits<=2000000 then ($r.bits|floor) else 0 end),kind:$kind};
. as $all |
[$all[]? | select(type=="object") | select(.url_resolved==$origin or .url==$origin) | record] as $anchors |
($anchors | unique_by([.name,.country,.zone,.web])) as $families |
($families | map(select(.name!="" and (.country|type=="string" and test("^[A-Z]{2}$")) and .web!=""))) as $identified |
{version:1, probe_hls:([$all[]? | select(type=="object") | select(.url_resolved==$input or .url==$input) | .hls] | any(.==1)),
 rows:(([{url:$origin,rate:0,codec:($anchors[0].codec // ""),bits:(if ($anchors|length)>0 and $anchors[0].hls!=1 then choice($anchors[0]; "original").bits else 0 end),kind:"original"}] +
       (if ($families|length)==1 and ($identified|length)==1 then
          $identified[0] as $a |
          # Normalizar solo posibles coincidencias, no todo el catálogo.
          # País y nombre descartan casi todas antes de procesar web/codec/URL.
          [$all[]? | select(type=="object") | select(.countrycode==$a.country) |
           select(((.name // "") | norm)==$a.name) | record |
           select((.url|stream_url) and .url!=$origin and .zone==$a.zone and .web==$a.web) |
           choice(.; "catalog")]
        else [] end)) |
       reduce .[] as $row ([]; if any(.[]; .url==$row.url and .rate==$row.rate) then . else .+[$row] end) | .[0:65]),
 notice:(if ($families|length)==0 then "Sin coincidencia por URL en el catálogo: no se agrupan emisoras solo por nombre."
         elif ($families|length)>1 then "El catálogo tiene datos de identidad contradictorios; no se ofrecen otras URL automáticamente."
         elif ($identified|length)==0 then "Falta país o web para identificar con seguridad otras versiones."
         else "Alternativas declaradas por el catálogo, no verificadas en vivo. Comprueba que mantienen la programación." end)}
