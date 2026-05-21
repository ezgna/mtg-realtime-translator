# mtg-realtime-translator

OpenAI Realtime Translation API を使った、デスクトップ向けのリアルタイム翻訳アプリ。
マイクから入った音声をその場で翻訳し、テキストと音声で返します。Swift 版では FluidAudio の Streaming VAD（Silero VAD v6 / CoreML）で発話区間を検出し、話し終わった瞬間にサーバへコミットさせます。

リポジトリ: <https://github.com/nanameru/mtg-realtime-translator>

## デモ

こんな感じで動きます👇

<video src="https://github.com/nanameru/mtg-realtime-translator/raw/main/docs/videos/demo.mp4" controls width="720"></video>

> 上の動画が再生されない場合は [docs/videos/demo.mp4](docs/videos/demo.mp4) から直接ダウンロードしてください。

---

## 必要なもの

- macOS / Windows / Linux （動作確認は macOS）
- Swift 5.10+ / macOS 14+（Swift ネイティブ版）
- OpenAI API キー（Realtime API が使えるもの）
- Zoom / Google Meet で使う場合は **仮想オーディオデバイス**（macOS は [BlackHole](https://existential.audio/blackhole/) を推奨）

## セットアップ

Swift ネイティブ版は repo 直下の `.env` を使いません。API キーは repo 外に置きます。

```bash
git clone https://github.com/nanameru/mtg-realtime-translator.git
cd mtg-realtime-translator

mkdir -p ~/.keys/openai/mtg-realtime-translator
printf 'OPENAI_API_KEY=sk-...\n' > ~/.keys/openai/mtg-realtime-translator/.env
chmod 600 ~/.keys/openai/mtg-realtime-translator/.env
```

## 起動

```bash
cd macos/RealtimeTranslator
swift run RealtimeTranslator
```

ウィンドウが開いたら：

1. **Output language** — 翻訳先の言語を選ぶ
2. **Mode** — 既定入出力で Apple AEC を使うなら `Presentation`、iPhone など任意デバイスで発表するなら `Presentation + Devices`、Teams / BlackHole 連携なら `Routing`
3. **Input** — マイク（相手の声を訳すなら後述の仮想デバイス）
4. **Output** — 再生先のスピーカー
5. **Start** を押す → 話す → 翻訳テキストと音声が流れてくる

Swift 版は Keychain を使いません。`OPENAI_API_KEY` は常に `~/.keys/openai/mtg-realtime-translator/.env` から読みます。

### Python 版について

Python 版の `app.py` / `main.py` は参考実装として残しています。新しい macOS 版の開発・起動は `macos/RealtimeTranslator` を使います。

---

## Zoom / Google Meet で使うとき

ここがこのアプリの本命の使い方です。**「相手が話している言語を、自分側でリアルタイムに翻訳して聞く／読む」** ためのセットアップ。

ポイントは 2 つ：

1. **会議アプリ側のスピーカー出力を、仮想オーディオデバイスに切り替える**
   （Zoom / Meet の音声を、本アプリのマイク入力として横取りするため）
2. **本アプリの Input をその仮想デバイスにする**
   （横取りした音声を翻訳エンジンに流し込むため）

> **なぜマイク／スピーカーを変える必要があるのか？**
> Zoom や Google Meet の音声は、普通はそのままスピーカーから出るだけで、他のアプリからは取れません。
> [BlackHole](https://existential.audio/blackhole/) のような **仮想オーディオデバイス** を間に挟むと、Zoom の出力 → BlackHole → 本アプリの入力、という配線ができ、相手の声を翻訳器に渡せるようになります。
> 同じ理由で、本アプリが翻訳した **自分の声** を会議の相手に届けたい場合は、Zoom / Meet 側の **マイク入力** を BlackHole に切り替える必要があります。

### 手順（macOS / BlackHole の例）

1. BlackHole 2ch をインストール（`brew install blackhole-2ch` でも可）
2. 用途に合わせて配線する：

   **A. 相手の声を翻訳して聞く**
   - Zoom / Meet の **スピーカー** を `BlackHole 2ch` に変更
   - 本アプリの **Input** を `BlackHole 2ch`、**Output** を実スピーカー（MacBook のスピーカー等）に
   - そのままだと自分には Zoom の音が聞こえなくなるので、macOS の「Audio MIDI 設定」で **複数出力装置**（実スピーカー + BlackHole 2ch）を作って Zoom の出力先にすると、聞きながら翻訳できる

   **B. 自分の翻訳音声を相手に届ける**
   - 本アプリの **Output** を `BlackHole 2ch` に
   - Zoom / Meet の **マイク** を `BlackHole 2ch` に変更
   - 自分が話す → 翻訳された音声が BlackHole に流れ込み、Zoom がそれを「マイク入力」として相手に送る

### 会議アプリ側でマイクを切り替える画面

Zoom の例。マイクの「∧」アイコンから出てくるメニューで `BlackHole 2ch` を選びます（Google Meet も画面右上「設定 → 音声」から同じことができます）。

![Zoom のマイク選択メニューで BlackHole 2ch を選択](docs/images/zoom-mic-blackhole.jpeg)

### 本アプリ側で入出力を切り替える画面

`Input` / `Output` のドロップダウンから、同じ `BlackHole 2ch` を選びます（用途 A なら Input、B なら Output）。
**Start を押した後でも切り替えられます** — Swift 版ではデバイスを変えると音声ストリームと Realtime セッションを張り直します。

![Realtime Translator の Output で BlackHole 2ch を選択](docs/images/app-output-blackhole.png)

### よくあるハマりどころ

- **自分側に何も聞こえない** → Zoom の出力を BlackHole 単独にしてしまっている。macOS の「Audio MIDI 設定」で「複数出力装置」を作って、実スピーカーと BlackHole を同時に鳴らす。
- **相手に翻訳音声が届かない** → Zoom 側の **マイク** が BlackHole になっているか確認。スピーカーだけ変えても相手には届かない。
- **エコーが乗る** → Zoom のマイクと本アプリの Output が同じ BlackHole を共有している場合、自分の声が翻訳ループに戻る。Zoom の「マイクをミュート」または用途 A／B のどちらかに絞る。

---

## 仕組み（短く）

- WebSocket で `wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate` に接続
- マイク音声を 24kHz / 20ms チャンクで送信
- Swift 版は FluidAudio の Streaming VAD（Silero VAD v6 / CoreML）で発話の開始／終了を検出
- Presentation Mode では Apple Voice Processing I/O と再生中ミュートで翻訳音声の自己再入力を抑制
- Presentation Mode では Apple Voice Processing I/O を必須にし、起動できない場合は通常音声エンジンへ自動フォールバックしません
- Presentation + Devices Mode では任意デバイスを選べます。Apple Voice Processing I/O は使わず、再生中ミュートで自己再入力を抑制
- 発話終了時に短い無音を流してサーバ VAD のコミットを誘発

詳しいパラメータは Swift 版の `macos/RealtimeTranslator/Sources/RealtimeTranslatorCore` を参照。

## ライセンス

[MIT License](LICENSE) © 2026 nanameru
