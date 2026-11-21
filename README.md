# analyze-social

A Claude Code skill that watches Instagram, TikTok, YouTube, Pinterest, X and Facebook links **on your own Mac**. It downloads the post, takes frames (Claude reads the on-screen text from them), transcribes speech with whisper.cpp, and answers from the whole video: summary, transcript, translation, recipe, places, products, study notes. Photo carousels work too. Nothing is sent to a third-party AI service, and it's free.

## Install (macOS, Apple Silicon)

```bash
brew install yt-dlp gallery-dl ffmpeg whisper-cpp
mkdir -p ~/.cache/whisper-cpp && cd ~/.cache/whisper-cpp
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin   # 1.6 GB, speech model
curl -LO https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin     # 1 MB, skips music/silence
git clone https://github.com/kakiubica/analyze-social ~/.claude/skills/analyze-social
```

Start a new Claude Code session and paste a link.

## Good to know

- Output lands in `~/Downloads/analyze-social/<timestamp>/`: the original video (`media.mp4`) or carousel photos (`images/`), frames, transcript, caption.
- When a site refuses an anonymous download, the script retries once with your Chrome login (`--cookies-from-browser chrome`; macOS asks for Keychain access the first time). Turn that off with `SOCIAL_COOKIES=none`.
- A 1-minute Reel or TikTok takes about 10–25 s. YouTube downloads are often throttled and take a minute or two.
- Public posts only; downloaded files are for personal use.
