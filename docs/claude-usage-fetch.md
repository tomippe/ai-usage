# Claude 使用率の取得方法（メニューバーアプリ向け）

Claudeの使用率を取れる**公式の公開APIはありません**。すでにある自作メニューバーアプリは、次のどれかの方法を使っています。

**AI Usage の現状:** **① OAuth API**（キーチェーン / `~/.claude/.credentials.json`、トークン更新、`GET /api/oauth/usage`）を **300秒** のメイン更新と一緒にポーリング。**② ステータスライン**（`~/.claude/ai-usage-rate-limits.json`）は **15秒** ごとにマージ。①が取れれば Claude Code 未起動でも％を表示。429 時は直前の値を維持。

---

## ① OAuth使用量エンドポイント（一番よく使われている方法）

Claude Codeにログインしたときの認証トークンを使って、非公開のエンドポイントを呼びます。

### トークンの取得

- 保存場所：macOSのキーチェーン（`Claude Code-credentials`）または `~/.claude/.credentials.json`
- **AI Usage:** キーチェーンは **UI を出さない読取のみ**（拒否・未許可時は以後キーチェーンに触れず、ファイルと statusline のみ）。トークン更新の保存先は **ファイルのみ**（Claude Code のキーチェーンは更新しない）。
- 次のコマンドでJSONが取れるので、中の `accessToken` を使います（ターミナル／Claude Code 用。AI Usage はパスワードダイアログを出さない）。

```bash
security find-generic-password -s "Claude Code-credentials" -w
```

### リクエスト

```bash
curl -s https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer <accessToken>" \
  -H "anthropic-beta: oauth-2025-04-20"
```

### レスポンス（主な項目）

| キー | 内容 |
|---|---|
| `five_hour.utilization` | 5時間枠の使用率（%） |
| `five_hour.resets_at` | 5時間枠のリセット時刻 |
| `seven_day.utilization` | 週枠の使用率（%） |
| `seven_day.resets_at` | 週枠のリセット時刻 |

### 注意点

- 公式に公開されたAPIではないので、予告なく変わる可能性があります。
- 短い間隔で呼ぶと429エラーが続くという報告があります。数分おきくらいの間隔が無難です。
- トークンは期限が切れるので、refresh tokenでの更新処理が要ります。

---

## ② Claude Codeのステータスライン経由（公式ドキュメントあり）

Claude Code v2.1.80以降は、ステータスライン用のスクリプトに渡されるJSONに `rate_limits`（5時間枠と週枠の使用率・リセット時刻）が入っています。

このスクリプトで値をファイルに書き出し、メニューバーアプリがそのファイルを読む、という構成にすれば公式の範囲で取れます。

- 長所：公式にドキュメント化されている
- 短所：Claude Codeを起動している間しか値は更新されない

AI Usage では `--claude-statusline` で `~/.claude/ai-usage-rate-limits.json` に書き、15秒ごとに読み取る。

---

## ③ claude.ai Webのセッションを使う方法

ブラウザの `sessionKey` Cookieで次のURLを呼ぶ方法です。

```
GET https://claude.ai/api/organizations/{org_id}/usage
```

①と同じような値が返りますが、Cookieの扱いが面倒で壊れやすいです。

---

## 無料版について

①と②はClaude Codeの認証が前提です。Claude Codeは有料プラン（Pro以上）でしか使えないので、無料アカウントでは取得できないのは仕様どおりです。実装自体はできるので、テストだけ有料アカウントで行う形になります。

---

## 参考にできる既存のOSS

- [claude-usage-widget](https://github.com/PanithanNanti/claude-usage-widget)：SwiftPM製のネイティブアプリ。キーチェーンからトークンを読み、トークンの自動更新にも対応
- [top_bar_claude_code_usage](https://github.com/diegocp01/top_bar_claude_code_usage)
- [claude-usage-bar](https://github.com/tomada1114/claude-usage-bar)
- [SwiftBar + OAuth APIで使用量表示（Zenn）](https://zenn.dev/yktsnet/articles/202604-claude-usage-swiftbar?locale=en)

## 参考資料

- [Customize your status line - Claude Code Docs](https://code.claude.com/docs/en/statusline)
- [Issue #31021: /api/oauth/usage が429を返し続ける](https://github.com/anthropics/claude-code/issues/31021)
- [Issue #81768: 公開の使用量APIがない](https://github.com/anthropics/claude-code/issues/81768)
- [Claude Code v2.1.80 のレート制限表示](https://claude-world.com/articles/claude-code-2180-release/)
