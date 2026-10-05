# SPDX-License-Identifier: GPL-3.0-or-later
# Etiquetas de texto, no HTML ni instrucciones. No inferir contenido por género.
def np_clean:
    if type == "string" then
        gsub("[\u0000-\u001f\u007f-\u009f]"; " ")
        | gsub("[[:space:]]+"; " ") | gsub("^ +| +$"; "") | .[0:240]
    else "" end;
def np_get($keys):
    . as $m | if type != "object" then "" else
        [$keys[] as $key | $m | to_entries[]
         | select((.key | ascii_downcase) == $key) | .value | np_clean
         | select(length > 0)] | .[0] // ""
    end;
def np_join($artist; $title):
    if $title == "" then ""
    elif $artist == "" or ($title | ascii_downcase) == ($artist | ascii_downcase)
         or ($title | ascii_downcase | startswith(($artist | ascii_downcase) + " - ")) then $title
    else ($artist + " - " + $title) | .[0:240] end;
def np_content:
    . as $m |
    ($m | np_get(["icy-title", "streamtitle", "stream-title", "now-playing", "now_playing"])) as $icy |
    ($m | np_get(["programme-title", "program-title", "show-title", "programme", "program"])) as $programme |
    ($m | np_get(["title"])) as $title |
    ($m | np_get(["artist", "performer"])) as $artist |
    [$icy, $programme, np_join($artist; $title)] | map(select(length > 0)) | .[0] // "";
def np_usable($name; $url; $input):
    np_clean | select(length > 0 and . != $name and . != $url and . != $input
                     and (test("^https?://"; "i") | not));
