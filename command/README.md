# commandディレクトリ内のファイルについて

ここにあるのは、CP/M-86のコマンドファイル FDISK.CMD, FDFORMAT.CMD, HDFORMAT.CMD を生成するためのソースコードです。CP/M-86環境に *.A86ファイルと、*.INCファイルをコピーして、例えば次のようにコマンドを実行すればコマンドファイルを生成できます。
```
ASM86 FDISK.A86
GENCMD FDISK
```

## *.INCファイルについて

FDFORMAT.A86のアセンブル時にはFDIPL.INC、HDFORMAT.A86のアセンブル時にはHDMIPL.INC、HDIPL.INCというファイルをインクルードします。FDIPLはフロッピー用のIPLコード、HDIPLはHDD区画用のIPLコードです。HDMIPL.INCは、HDDのマスターIPLコードです。

*.INCファイルは次のコマンドで生成できます。

```
nasm -f bin fdipl.asm -o fdipl.bin
nasm -f bin hdipl.asm -o hdipl.bin
nasm -f bin master-ipl.asm -o hdmipl.bin

python3 bin2a86.py fdipl.bin  FDIPL.INC  --label fdipl_template  --expect-size 512
python3 bin2a86.py hdipl.bin  HDIPL.INC  --label hdipl_template  --expect-size 512
python3 bin2a86.py hdmipl.bin HDMIPL.INC --label hdmipl_template --expect-size 512
```
