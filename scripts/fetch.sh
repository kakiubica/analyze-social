#!/bin/zsh
# fetch.sh <URL> [frames=auto] [lang=auto]
# Downloads a public social post/video locally, extracts frames, transcribes
# audio with whisper.cpp. Nothing is sent to third-party AI services.
# Env: SOCIAL_OUT (output root), SOCIAL_COOKIES=auto|chrome|none (default auto:
# retry with Chrome's login only when the anonymous try is refused), SOCIAL_MODEL.
set -euo pipefail
setopt extended_glob
URL="$1"; FRAMES="${2:-auto}"; LANG_="${3:-auto}"
MODEL="${SOCIAL_MODEL:-$HOME/.cache/whisper-cpp/ggml-large-v3-turbo.bin}"
VAD="$HOME/.cache/whisper-cpp/ggml-silero-v5.1.2.bin"
COOKIE_MODE="${SOCIAL_COOKIES:-auto}"
ROOT="${SOCIAL_OUT:-$HOME/Downloads/analyze-social}"
OUT="$ROOT/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT/frames"
cd "$OUT"

CK=(); [[ "$COOKIE_MODE" == chrome ]] && CK=(--cookies-from-browser chrome)

# 1) metadata + media; the second call only saves metadata (photo posts have no video formats)
fetch() {
  # no platform subtitles: a refused subtitle request (HTTP 429) aborts the whole download, whisper covers it
  yt-dlp "${CK[@]}" --no-playlist --write-info-json --write-thumbnail \
    -f "bv*[height<=1080]+ba/b" --merge-output-format mp4 \
    -o "media.%(ext)s" "$URL" >>ytdlp.log 2>&1 \
  || yt-dlp "${CK[@]}" --no-playlist --write-info-json --skip-download \
    --ignore-no-formats-error --write-thumbnail \
    -o "media.%(ext)s" -o "thumbnail:images/%(playlist_index)03d.%(ext)s" "$URL" >>ytdlp.log 2>&1 || true
  # shortcut: on a photo post the "thumbnail" is the full photo (IG gives 1080 px without login);
  # a video whose download failed leaves only its cover here, check meta.txt before calling it a photo
}
fetch
VIDS=(media.(mp4|webm|mkv)(N))
# nothing at all came back = refused (login wall), so retry once with Chrome's login
if (( ! $#VIDS )) && [[ ! -f media.info.json && "$COOKIE_MODE" == auto ]]; then
  echo "anonymous download refused, retrying with Chrome login" >&2
  CK=(--cookies-from-browser chrome); fetch; VIDS=(media.(mp4|webm|mkv)(N))
fi

# 2) photo posts / carousels: yt-dlp's photos from step 1, else gallery-dl
IMGS=(images/*~*.json(N.))
if (( ! $#VIDS && ! $#IMGS )); then
  gdl() { gallery-dl "$@" --write-metadata -D images "$URL" >>gallery-dl.log 2>&1 || true; }
  gdl "${CK[@]}"; IMGS=(images/*~*.json(N.))
  if (( ! $#IMGS )) && [[ "$COOKIE_MODE" == auto && ! ${#CK} -gt 0 ]]; then
    gdl --cookies-from-browser chrome; IMGS=(images/*~*.json(N.))
  fi
fi

if (( ! $#VIDS && ! $#IMGS )); then
  echo "FAILED: nothing downloaded from $URL" >&2
  tail -n 5 ytdlp.log gallery-dl.log >&2 2>/dev/null || true
  echo "$OUT"; exit 1
fi

# 3) short metadata summary (yt-dlp info.json, else the first gallery-dl metadata file)
META=(media.info.json(N) images/*.json(N))
python3 -I - "${META[1]:-}" > meta.txt <<'PY'
import json,sys
if not sys.argv[1]: sys.exit(print("(no metadata)"))
d=json.load(open(sys.argv[1]))
for k in ("title","uploader","channel","username","author","upload_date","date","duration","view_count","like_count","comment_count","webpage_url","post_url"):
    v=d.get(k)
    if v not in (None,"") and not isinstance(v,(dict,list)): print(f"{k}: {v}")
desc=next((d[k] for k in ("description","caption","content","desc") if isinstance(d.get(k),str) and d[k]),"")
print("description:", desc[:3000])
PY

TRANS="(no video)"
if (( $#VIDS )); then
  VIDEO="${VIDS[1]}"
  DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO")
  # 4) frames: ~1 per 2.5 s, 8–30 by default; longer side 1024 px so on-screen text stays readable
  python3 -I - "$VIDEO" "$DUR" "$FRAMES" <<'PY'
import subprocess,sys
v,d,n=sys.argv[1],float(sys.argv[2]),sys.argv[3]
n=int(n) if n!="auto" else max(8,min(30,round(d/2.5)))
for i in range(n):
    t=d*(i+0.5)/n
    subprocess.run(['ffmpeg','-v','error','-ss',f'{t:.2f}','-i',v,'-frames:v','1',
        '-vf','scale=1024:1024:force_original_aspect_ratio=decrease',f'frames/t{t:07.2f}s.jpg'],check=True)
PY
  # 5) local transcription; VAD keeps music-only stretches from turning into invented sentences
  if ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$VIDEO" | grep -q .; then
    if [[ ! -f "$MODEL" ]]; then
      echo "whisper model missing: $MODEL" | tee transcript.txt >&2
    else
      VADARGS=(); [[ -f "$VAD" ]] && VADARGS=(--vad -vm "$VAD")
      ffmpeg -v error -i "$VIDEO" -ar 16000 -ac 1 -c:a pcm_s16le audio.wav
      whisper-cli -m "$MODEL" -l "$LANG_" "${VADARGS[@]}" -f audio.wav -otxt -osrt -of transcript >/dev/null 2>whisper.log \
        || echo "transcription failed (see whisper.log)" > transcript.txt
      rm -f audio.wav
      grep -q '[[:alnum:]]' transcript.txt 2>/dev/null || echo "(no speech detected)" > transcript.txt
    fi
  else
    echo "(no audio track)" > transcript.txt
  fi
  TRANS=$(head -c 60 transcript.txt | tr '\n' ' ')
fi
# shortcut: a carousel's own videos (in images/) are not transcribed; run whisper on one if asked

FR=(frames/*.jpg(N))
echo "video: ${VIDS[1]:-none} | frames: $#FR | carousel files: $#IMGS | transcript: $TRANS" >&2
echo "$OUT"
