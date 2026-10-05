# SPDX-License-Identifier: GPL-3.0-or-later
include "now-playing-metadata";
def array: if type == "array" then . elif type == "object" then [.] else [] end;
# Igualdad del stream: conservar ruta, query y puerto; nunca agrupar por nombre.
def urlkey:
    if type != "string" then "" else
        try (capture("^(?<scheme>https?)://(?<host>[A-Za-z0-9.-]+)(?<port>:[0-9]+)?(?<path>/[^#]*)?(?:#.*)?$")
             | (.scheme | ascii_downcase) as $s
             | ($s + "://" + (.host | ascii_downcase)
                + (if (.port // "") == (if $s == "https" then ":443" else ":80" end) then "" else .port // "" end)
                + (.path // "/"))) catch ""
    end;
def same: urlkey as $candidate | ($stream | urlkey) as $wanted
    | $candidate != "" and $candidate == $wanted;
def content($name):
    np_clean | if . == ($name | np_clean) or test("^https?://"; "i") then "" else . end;
def result($title; $host; $until):
    ($title | np_clean) as $clean_title | ($host | np_clean | .[0:60]) as $clean_host |
    if $until > $now and $clean_title == "" and $clean_host == "" then error("sin metadatos actuales")
    else {version:1,stream:$stream,endpoint:$endpoint,kind:$kind,
          title:$clean_title,host:$clean_host,checked_at:$now,valid_until:$until} end;
if $kind == "icecast" then
    [.icestats.source | array | .[] | select(type == "object")
     | select((.listenurl | same) or
              ((.listenurl // "") == "" and ($stream | contains("?") | not)
               and (.mount? | type) == "string"
               and .mount == ($stream | sub("^https?://[^/]+"; ""))))] as $matched |
    if ($matched | length) != 1 then error("stream ambiguo o ausente") else
        $matched[0] | (.server_name // "") as $name |
        result((np_join((.artist | np_clean); (.title | np_clean)) | content($name)); ""; $now+120)
    end
elif $kind == "azuracast" then
    [array | .[] | select(type == "object")
     | select([.station.listen_url, .station.hls_url,
               (.station.mounts[]?.url), (.station.remotes[]?.url)] | any(.[]; same))] as $matched |
    if ($matched | length) != 1 then error("stream ambiguo o ausente") else
        $matched[0] |
        (.now_playing.played_at // 0) as $start |
        (.now_playing.duration // 0) as $duration |
        if .is_online == false then result(""; ""; $now)
        elif .is_online != true then error("estado no verificable")
        elif ($start | type) != "number" or ($duration | type) != "number"
             or $start < 0 or $start > $now+90 or $duration < 0
             or ($duration > 0 and $start > 0 and $start+$duration <= $now) then error("dato fuera de vigencia")
        else
            (if .live.is_live == true then .live.streamer_name | np_clean else "" end) as $host |
            (np_join((.now_playing.song.artist | np_clean); (.now_playing.song.title | np_clean))) as $title |
            (.station.name // "") as $name |
            result(((if $title != "" then $title else .now_playing.song.text | np_clean end) | content($name)); $host;
                   (if $duration > 0 and $start > 0 then [$now+120,($start+$duration | floor)] | min else $now+120 end))
        end
    end
else error("proveedor desconocido") end
