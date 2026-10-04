# SPDX-License-Identifier: GPL-3.0-or-later
# Solo metadatos de variantes. No descargar segmentos ni ejecutar atributos.
function attributes(text, out,    i,ch,quoted,part,n,items,p,k,v) {
    quoted=0; part=""; n=0
    for (i=1;i<=length(text);i++) {
        ch=substr(text,i,1)
        if (ch=="\"") quoted=!quoted
        if (ch=="," && !quoted) { items[++n]=part; part="" } else part=part ch
    }
    if (quoted) return 0
    items[++n]=part
    for (i=1;i<=n;i++) {
        p=index(items[i],"="); if (!p) return 0
        k=substr(items[i],1,p-1); v=substr(items[i],p+1)
        gsub(/^ +| +$/,"",k); gsub(/^"|"$/,"",v)
        if (k in out) return 0
        out[k]=v
    }
    return 1
}
BEGIN { FS="\t"; pending=0; header=0; invalid=0 }
{
    sub(/\r$/,"",$0)
    if (NR==1) { if ($0!="#EXTM3U") invalid=1; else header=1; next }
    if (length($0)>4096 || $0 ~ /[[:cntrl:]]/) { invalid=1; next }
    if ($0 ~ /^#EXT-X-STREAM-INF:/) {
        delete attr; pending=0
        if (!attributes(substr($0,19),attr)) { invalid=1; next }
        rate=attr["BANDWIDTH"]
        if (rate !~ /^[1-9][0-9]*$/ || length(rate)>7) next
        rate+=0
        if (rate<8000 || rate>2000000) next
        if ("RESOLUTION" in attr || "AUDIO" in attr || "VIDEO" in attr) next
        codecs=attr["CODECS"]; codec=""
        if (codecs ~ /^mp4a\.40\.(5|29)$/) codec="HE-AAC"
        else if (codecs ~ /^mp4a\.40\.2$/) codec="AAC"
        else if (codecs=="opus") codec="Opus"
        else if (codecs=="flac" || codecs=="fLaC") codec="FLAC"
        else if (codecs=="ac-3" || codecs=="ec-3") codec="AC-3"
        else next
        pending=1; next
    }
    if ($0 ~ /^#/ || $0 == "") next
    if (pending) {
        # Solo URI de HTTP(S) o relativas. El reproductor vuelve a abrir el
        # master con el bitrate, nunca una URL hija temporal guardada.
        if ($0 ~ /[[:space:]\\|]/ || ($0 ~ /^[A-Za-z][A-Za-z0-9+.-]*:/ && $0 !~ /^https?:\/\//)) { invalid=1; next }
        # Un límite numérico no distingue idioma/codec con el mismo bitrate.
        # Rechazar esa lista es más seguro que prometer una variante concreta.
        if (seen[rate]++) invalid=1
        else { rates[++count]=rate; labels[count]=codec }
        pending=0
        if (count>32) invalid=1
    }
}
END {
    if (invalid || !header || pending) exit 1
    for (i=1;i<=count;i++) print rates[i] "\t" labels[i]
}
