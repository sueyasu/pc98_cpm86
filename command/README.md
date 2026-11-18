## SYNC: 全ドライブのキャッシュ書き戻し

`SYNC.A86` はPC-9801版とFM-11版で共通のソースです。両CBIOSの
`0400:3DD8` にある `CACHE_SYNC` をFAR CALLし、dirtyセクタを
ディスクに書き戻します。成功なら `SYNC: cache flushed.`、
書き戻しエラーなら `SYNC: disk write-back failed.` と表示します。

```text
A>ASM86 SYNC.A86
A>GENCMD SYNC
A>SYNC
```

`SYNC` はキャッシュを無効化しません。メディア交換やFORMATの直前に
キャッシュを無効化する必要がある場合には `CACHE_RESET` が必要です。
このコマンドは、上記の外部APIを持つ更新済みCBIOS専用です。
BDOSファンクション0による通常のコマンド終了でもWBOOTが実行されるため、
通常はWBOOT側でも同期します。

# commandディレクトリ内のファイルについて

ここにあるのは、CP/M-86のコマンドファイル FDISK.CMD, FDFORMAT.CMD, HDFORMAT.CMD を生成するためのソースコードです。CP/M-86環境に *.A86ファイルと、*.INCファイルをコピーして、例えば次のようにコマンドを実行すればコマンドファイルを生成できます。
```
ASM86 FDISK.A86
GENCMD FDISK
```

## *.INCファイルについて

FDFORMAT.A86のアセンブル時にはFDIPL.INC、HDFORMAT.A86のアセンブル時にはMASIPL.INC、HDIPL.INCというファイルをインクルードします。FDIPL.INCはフロッピー用のIPLコード、HDIPL.INCはHDD区画用のIPLコードです。MASIPL.INCは、HDDのマスターIPLコードです。

*.INCファイルは次のコマンドで生成できます。

```
nasm -f bin fdipl.asm -o fdipl.bin
nasm -f bin hdipl.asm -o hdipl.bin
nasm -f bin master-ipl.asm -o masipl.bin

python3 bin2a86.py fdipl.bin  FDIPL.INC  --label fdipl_template  --expect-size 512
python3 bin2a86.py hdipl.bin  HDIPL.INC  --label hdipl_template  --expect-size 512
python3 bin2a86.py masipl.bin MASIPL.INC --label masteripl_template --expect-size 512
```
