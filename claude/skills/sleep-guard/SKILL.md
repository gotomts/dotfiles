---
name: sleep-guard
description: Mac の蓋を閉じても Claude Code を動かし続けるためのスリープ管理。
argument-hint: on / off
allowed-tools:
  - Bash
---

# Sleep Guard

pmset disablesleep を安全に管理する。

## アクション判定

- on → 有効化（スリープ無効）
- off → 無効化（スリープ復帰）
- 引数なし → 状態確認

## 有効化（on）

1. `pmset -g | grep -i sleepdisabled` で状態確認。既に 1 なら終了
2. `sudo pmset -a disablesleep 1` で無効化
3. `pmset -g batt | head -1` で電源確認。バッテリー駆動なら警告
4. 「終わったら /sleep-guard off で戻して」と伝える
5. 蓋閉じ中は排熱が弱いのでカバンに入れないよう注意

## 無効化（off）

1. `pmset -g | grep -i sleepdisabled` で状態確認。既に 0 なら終了
2. `sudo pmset -a disablesleep 0` で復帰

## 状態確認（引数なし）

`pmset -g | grep -i sleepdisabled` を実行。
- SleepDisabled 1 → 無効化中
- SleepDisabled 0 or 該当なし → 通常状態
