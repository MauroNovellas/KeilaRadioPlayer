# SPDX-License-Identifier: GPL-3.0-or-later
# Extrae como máximo tres iconos estáticos. No interpreta scripts ni entidades XML.
function attribute(tag, name, pos, quote, value) {
    if (!match(tolower(tag), "[[:space:]]" name "[[:space:]]*=[[:space:]]*[\"\047]")) return ""
    pos=RSTART+RLENGTH; quote=substr(tag,pos-1,1)
    value=substr(tag,pos); pos=index(value,quote)
    return pos ? substr(value,1,pos-1) : ""
}
{ html=html " " $0 }
END {
    lower=tolower(html); stop=index(lower,"</head")
    if (stop) html=substr(html,1,stop-1)
    # No confundir ejemplos/comentarios o strings de JavaScript con enlaces.
    while (match(tolower(html), /<script([[:space:]][^>]*)?>/)) {
        start=RSTART; rest=substr(html,RSTART+RLENGTH); stop=index(tolower(rest),"</script>")
        html=substr(html,1,start-1) (stop ? substr(rest,stop+9) : "")
    }
    while (match(html, /<!--/)) {
        start=RSTART; rest=substr(html,RSTART+RLENGTH); stop=index(rest,"-->")
        html=substr(html,1,start-1) (stop ? substr(rest,stop+3) : "")
    }
    while (match(tolower(html), /<link[[:space:]][^>]*>/)) {
        tag=substr(html,RSTART,RLENGTH); html=substr(html,RSTART+RLENGTH)
        rel=tolower(attribute(tag,"rel")); href=attribute(tag,"href")
        if (!href || length(href)>2048 || href ~ /[[:space:][:cntrl:]]/) continue
        gsub(/&amp;/,"\\&",href)
        if (rel ~ /(^|[[:space:]])apple-touch-icon(-precomposed)?([[:space:]]|$)/) { if (a<3) apple[++a]=href }
        else if (rel ~ /(^|[[:space:]])icon([[:space:]]|$)/) { if (b<3) icon[++b]=href }
    }
    for (i=1; i<=a && count<3; i++) if (!seen[apple[i]]++) { print apple[i]; count++ }
    for (i=1; i<=b && count<3; i++) if (!seen[icon[i]]++) { print icon[i]; count++ }
}
