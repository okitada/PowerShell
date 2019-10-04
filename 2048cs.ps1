<#
2048cs.ps1 - 2048 Game (PowerShell+C#バージョン)
実行例：.\2048cs.ps1 -auto_mode 3 -print_mode 1 -one_time 1
2017/01/08 powershell へ移植
2019/01/19 Go最新版に合わせつつデバッグ
2019/01/26 パラメータ対応
2019/02/09 軽微なスペル修正
2019/02/10 スペル修正（D_INIT2→D_INIT_2,D_INIT2→D_INIT_2), calcGap重複削除
2019/09/30 C#に移植開始
2019/10/04 Go版からC#版に移植完了
#>

$src = cat 2048.cs | Out-String
Add-Type -TypeDefinition $src -Language CSharp
[Game2048]::Main()
