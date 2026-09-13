# toolsディレクトリ内のファイルについて

ここにあるのは、CP/M-86のコマンドファイル FDISK.CMD, FDFORMAT.CMD, HDFORMAT.CMD を生成するためのソースコードです。CP/M-86環境に *.A86ファイルと、*.INCファイルをコピーして、例えば次のようにコマンドを実行すればコマンドファイルを生成できます。
```
ASM86 FDISK.A86
GENCMD FDISK
```

## FDISK.CMD

SCSI HDDにCP/M-86用の区画を作成するためのコマンドです。引数にはSCSI IDを指定します。例えばSCSI IDが1のHDDに区画を作る場合には、次のように実行します。指定できるSCSI IDは0～6の整数です。

```
FDISK 1
```

Linuxのfdiskのサブセットになっていて、pで区画情報表示、nで区画作成、bで起動フラグの設定、dで区画削除、wで設定の反映、qでコマンド終了です。作成と起動フラグの設定ができるのはCP/M-86専用の区画だけですが、削除についてはどの区画も対象にできます。

区画サイズは1～512MiBの範囲で、MiB単位で設定できます。シリンダー単位で切り捨てるので、実際に作成される区画のサイズは指定した数値よりも少し小さくなります。

## FDFORMAT.CMD

フロッピーディスクをCP/M-86用にフォーマットするコマンドです。引数にはフォーマットしたいディスクがあるドライブを指定します。例えばB:のディスクをフォーマットするには、次のように実行します。

```
FDFORMAT B:
```

/Sオプションを指定すると、フォーマット後にCP/M-86のシステムイメージを書き込みます。これにより、CP/M-86を起動可能なディスクを作成できます。/Lオプションを指定すると、ローレベルなフォーマットのみを実施します。

## HDFORMAT.CMD

FDISK.CMDで作成したCP/M-86用の区画をフォーマットするコマンドです。引数にはフォーマット対象の区画を「SCSI ID:区画番号」の形式で指定します。例えばSCSI ID3のHDDにある2番目の区画をフォーマットするには、次のように実行します。

```
HDFORMAT 3:2
```

/Sオプションを指定すると、フォーマット後にCP/M-86のシステムイメージを書き込みます。

/Sオプション指定時、対象HDDに「固定ディスク起動メニュープログラム」などのマスターIPLが書き込まれている場合には、それを上書きしません。CP/M-86を起動する場合には、そのマスターIPLのメニューなどでCP/M-86区画を選択してください。HDDにマスターIPLがなければ、CP/M-86起動専用のマスターIPLを書き込みます。このマスターIPLは、最初に見つけた起動可能なCP/M-86区画をブートする機能しか持っていません。

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
