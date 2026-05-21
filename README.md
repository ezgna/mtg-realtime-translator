# mtg-realtime-translator

OpenAI Realtime Translation API を使った、ブラウザ版のリアルタイム翻訳アプリ。
ブラウザの WebRTC 音声経路でマイク入力を OpenAI に送り、翻訳音声と字幕を受け取ります。

リポジトリ: <https://github.com/nanameru/mtg-realtime-translator>

## 必要なもの

- Python 3.10+
- OpenAI API キー（Realtime API が使えるもの）
- WebRTC 対応ブラウザ（Chrome / Edge 推奨）

## セットアップ

```bash
git clone https://github.com/nanameru/mtg-realtime-translator.git
cd mtg-realtime-translator

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

mkdir -p ~/.keys/openai/mtg-realtime-translator
printf 'OPENAI_API_KEY=sk-...\n' > ~/.keys/openai/mtg-realtime-translator/.env
chmod 600 ~/.keys/openai/mtg-realtime-translator/.env
```

## 起動

```bash
python web/server.py
```

ブラウザで <http://127.0.0.1:8787> を開きます。

1. **Output language** を選ぶ
2. **Microphone** / **Speaker** を必要に応じて選ぶ
3. **Echo** / **Noise** / **Gain** を必要に応じて切り替える
4. **Start** を押す。Live 中は同じボタンが **Stop** になります

Output language、Microphone、Echo / Noise / Gain はセッション開始時に固定されます。変更するときは一度 **Stop** してから設定し直してください。

API キーは `~/.keys/openai/mtg-realtime-translator/.env` から読みます。シェルの `OPENAI_API_KEY` でも上書きできます。

## 仕組み

- ローカルサーバーが `/session` で OpenAI の短命 client secret を発行
- ブラウザが `getUserMedia()` でマイクを取得
- `RTCPeerConnection` で `https://api.openai.com/v1/realtime/translations/calls` に接続
- 音声は WebRTC media track として送信
- 翻訳音声は remote audio track として再生
- 字幕は data channel の `session.output_transcript.delta` で表示

ブラウザ側の音声取得では `echoCancellation`、`noiseSuppression`、`autoGainControl` を有効にできます。これは OpenAI サーバー側の AEC ではなく、ブラウザ/OS/WebRTC stack 側の音声処理です。

## 旧実装

`app.py` / `main.py` は WebSocket + PCM 手動送受信の参考実装として残しています。新しい実装は `web/` 配下です。

## ライセンス

[MIT License](LICENSE) © 2026 nanameru
