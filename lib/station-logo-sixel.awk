# SPDX-License-Identifier: GPL-3.0-or-later
# RGB24 96x96 normalizado -> cuerpo SIXEL acotado, sin escapes del servidor.
# Paleta RGB 3:3:2 (256 colores), RLE, una conversión en el worker.
function run(ch, count, i) {
    if (count > 3) printf "!%d%s", count, ch
    else for (i=0; i<count; i++) printf "%s", ch
}
{
    for (i=1; i<=NF; i++) bytes[n++]=$i
}
END {
    if (n != 27648 || side < 6 || side > 96 || side % 6) exit 1
    for (y=0; y<side; y++) for (x=0; x<side; x++) {
        pos=(int(y*96/side)*96+int(x*96/side))*3
        color=int(bytes[pos]*7/255+0.5)*32 + int(bytes[pos+1]*7/255+0.5)*4 + int(bytes[pos+2]*3/255+0.5)
        pixels[y*side+x]=color
        used[color]=1
    }
    printf "\"1;1;%d;%d", side, side
    for (color=0; color<256; color++) if (used[color])
        printf "#%d;2;%d;%d;%d", color, int(int(color/32)*100/7+0.5), int(int(color/4)%8*100/7+0.5), int(color%4*100/3+0.5)
    for (y=0; y<side; y+=6) {
        delete band
        for (dy=0; dy<6; dy++) for (x=0; x<side; x++) band[pixels[(y+dy)*side+x]]=1
        first=1
        for (color=0; color<256; color++) if (band[color]) {
            if (!first) printf "$"
            first=0
            printf "#%d", color
            last=""; count=0
            for (x=0; x<side; x++) {
                bits=0; weight=1
                for (dy=0; dy<6; dy++) {
                    if (pixels[(y+dy)*side+x] == color) bits+=weight
                    weight*=2
                }
                ch=sprintf("%c", bits+63)
                if (ch == last) count++
                else { if (count) run(last, count); last=ch; count=1 }
            }
            if (count) run(last, count)
        }
        if (y+6 < side) printf "-"
    }
    printf "\n"
}
