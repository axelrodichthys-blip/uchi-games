#!/usr/bin/env bash
# セッション開始時に git pull して GitHub 上の最新を取り込む。
# クラウド（Claude Code on the web）と Windows（Git Bash 経由）の両方で動く。
# 失敗しても自分では解決しない。メッセージを出すだけにして、Claude がユーザーに伝える。
set -u

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" || exit 0

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
  echo "[session-start] ブランチが特定できないため git pull をスキップしました"
  exit 0
fi

# 作業中の変更があるときは pull で壊さないようにスキップ
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "[session-start] コミットされていない変更があるため git pull をスキップしました（ブランチ: $branch）"
  exit 0
fi

# リモートに同名ブランチが無ければ何もしない（新しいローカルブランチなど）
if ! git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  echo "[session-start] origin に '$branch' が無いため git pull をスキップしました"
  exit 0
fi

if out="$(git pull --ff-only origin "$branch" 2>&1)"; then
  echo "[session-start] git pull 完了（ブランチ: $branch）: $(echo "$out" | tail -1)"
else
  echo "[session-start] git pull に失敗しました（ブランチ: $branch）。自分で解決せず、ユーザーに状況を伝えてください:"
  echo "$out"
fi
exit 0
