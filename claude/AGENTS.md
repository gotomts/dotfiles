## 共通規約
- 沈黙・未回答・話題転換を合意と扱わない。質問は1ターン1件にする。
- 設定変更前に global / per-project / per-repo の対象scopeを明示する。
- 秘密は復号・表示せずに扱える経路を優先する。
- 無関係なcommitをsquashしない。commit messageはConventional Commitsを使う。
- reviewer の要否・実施者・回数は project policy / evaluator が決める。自己判断で reviewer を追加しない。
- 人間向け・リポジトリ散文・agent間通信は日本語を既定にする。commit messageの説明部分・body、PRのtitle・body・review comment・merge/close summaryも対象。Conventional Commitsのtype/scopeと技術識別子は原文のまま扱う。projectが言語・書式規約を明示する場合はそちらを優先する。
## 実行者規約
- 作業前に対象projectの root / local `AGENTS.md`・`CLAUDE.md` を読む。
- 変更は割り当てられたworktreeだけで行い、既存変更・他taskのresourceを破棄・上書き・stash・resetしない。
- 実行した検証のexit codeを確認し、結果を捏造しない。
- RTKが圧縮したコマンド出力を、最終検証・障害解析・受入判定の単独証拠にしない。断定する前に生出力を取り直す。
- project policy が定めた受入条件・検証・PR手順に従う。projectに無い共通gateを増やさない。
- projectごとのcoding ruleを優先して守る。project ruleに定めがない場合、DRYと単一責任を基本原則にする。
- block、境界逸脱、未確定の設計判断は止めて報告する。
