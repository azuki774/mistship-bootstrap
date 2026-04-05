# Pull Request Creator

AI がこのリポジトリで新規 pull request を作成するときの基本ルールです。

目的は、古い base branch から派生したブランチや、意図しない派生元での作業開始を避けることです。

## 適用タイミング

- 新規で開発ブランチを切って PR を作成するとき
- まだ派生元ブランチが明示されていないとき

## 基本ルール

- ユーザから派生元ブランチの指定がある場合は、その指示を優先する
- ユーザから特に指示がない場合は、`master` を派生元にする
- 新しい開発ブランチを切る前に、`origin/master` を最新化する
- 古いローカル `master` からそのままブランチを切らない

## 実行手順

1. ユーザが派生元ブランチを指定しているか確認する
2. 指定がなければ、派生元を `master` とする
3. `origin/master` の最新状態を取得する
4. 最新化した `master` を基準に開発ブランチを作る
5. そのブランチで作業し、PR を作成する

## AI への指示文

以下をそのまま PR 作成エージェントの基本指示として使えます。

```text
When creating a new pull request for this repository, use the user-specified base branch if one is provided.
If the user does not specify a base branch, use master by default.
Before creating the development branch, make sure origin/master is updated to the latest remote state.
Do not start a new branch from a stale local master.
```
