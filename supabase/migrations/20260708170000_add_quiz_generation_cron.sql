-- design/system.md 6.2節「クイズ自動生成 + マルチエージェント検証パイプライン」に対応する
-- generate_quiz_batch Edge Function（Generator→Solver x3→Validatorの3段階パイプライン）の
-- 定期実行タイミングに関する設計意図を記録するためのメモ用マイグレーション。
--
-- pg_cronはSQLの定期実行のみをサポートしており、Edge FunctionへのHTTP呼び出しを行うには
-- pg_net拡張等の追加設定が必要になる。本プロジェクトではその構成を採用せず、
-- 外部cron（GitHub Actions等のスケジュールジョブ）から30分ごと（*/30 * * * *）に
-- generate_quiz_batch Edge Functionを直接HTTP呼び出しする方式を正とする
-- （recalculate_scoresと同様に`X-Cron-Secret`ヘッダー[`QUIZ_GENERATION_CRON_SECRET`]で保護する）。
--
-- そのため、このマイグレーションではpg_cron+pg_netによるHTTP呼び出しコードは実装せず、
-- 上記の設計意図をコメントとして残すのみとする。実際のスケジューリングはリポジトリの
-- CI/CD設定（GitHub Actions等のworkflowファイル）側で行うこと。
do $$
begin
  raise notice 'generate_quiz_batch Edge Function is scheduled via external cron (e.g. GitHub Actions) every 30 minutes, not via pg_cron. See migration comment for details.';
end;
$$;
