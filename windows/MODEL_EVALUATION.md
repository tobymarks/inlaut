# Windows speech-model evaluation

Date: 2026-10-14. CPU inference, four threads, same `SherpaEngine` silence
trimming for all candidates. The existing German FastConformer INT8 remains the
default until a replacement has demonstrated a useful quality/resource tradeoff.

## Candidates

- Existing German FastConformer hybrid large PC transducer INT8: 136,488,746
  bytes of model files; modified beam search, four active paths.
- [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3):
  multilingual, including German; the [sherpa-onnx INT8 export](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-transducer/nemo-transducer-models.html)
  is tested with greedy search as documented by its exporter.
- [Whisper large-v3 Turbo](https://huggingface.co/openai/whisper-large-v3-turbo):
  sherpa-onnx INT8 encoder/decoder, German transcription, greedy decoding.
- [Qwen3-ASR 0.6B](https://huggingface.co/Qwen/Qwen3-ASR-0.6B) is a further
  current candidate, not yet benchmarked here. This evaluation does not establish
  a global winner among all available models.

## Reproduction and limitations

`Inlaut.ModelBenchmark <model-directory> <corpus-directory> <result.json>
[nemo|nemo-tdt|whisper]` runs each candidate in a fresh process. The corpus contains
`expected.json` (an ordered string array) and `test-1.wav` through `test-N.wav`.
It records per-clip hypotheses, decode times, WER, model file size, peak process
working set and final private bytes. Working set includes the runtime; it is not
just the weights. Disk size currently includes other files inside the model folder.
WER lowercases and strips punctuation; it does not equate written-out numbers with
digits or normalize compounds. Inspect individual differences before drawing
conclusions. Punctuation accuracy is not included in WER.

Two local corpora are separate:

1. Twenty synthetic German sentences, Microsoft SAPI voice, three speaking rates,
   265 reference words. This checks technical integration, not general recognition
   quality. Existing model: 2/265 errors (0.75%), both from splitting a compound.
2. Twenty public human recordings from [PolyAI MINDS-14](https://huggingface.co/datasets/PolyAI/minds14),
   German `de-DE`, training split, first 100 viewer rows sampled every fifth row.
   Source revision `40ce77cb32a384e4d50a568e1ec39ac804019d33`, CC BY 4.0.
   Telephone/banking domain; 353 reference words. Original 8 kHz mu-law audio is
   decoded to PCM16 at 8 kHz, then resampled by the recognizer. Published references
   themselves include apparent transcription errors; raw WER is therefore an
   imperfect proxy for actual errors. This small convenience sample is not a
   held-out general dictation benchmark and may overlap model training data.

Existing model on the human sample: 56/353 word differences (15.86%), 139.65 s
of trimmed audio decoded in 17.23 s, peak working set 471 MiB. These are a single
local run, not confidence intervals. Public benchmark files stay outside Git;
never commit private recordings or transcripts. FLEURS was attempted first but
the dataset service rejected its own parquet scan as exceeding its size limit.

| Candidate | Human word differences | Decode / 139.65 s audio | Peak working set | Model directory |
|---|---:|---:|---:|---:|
| German FastConformer INT8 | 56/353 (15.86%) | 17.23 s | 471 MiB | 130 MiB |
| Parakeet TDT v3 INT8 | 46/353 (13.03%) | 28.21 s | 1011 MiB | 640 MiB |
| Whisper Turbo INT8 | 35/353 (9.92%) | 146.49 s | 1884 MiB | 989 MiB |

Parakeet's synthetic score is 12/265 (4.53%). Eight differences come from useful
number/date/currency formatting, but four are actual word differences. Do not
present that score as all recognition mistakes or hide the remaining errors.

Decision: preserve FastConformer as the small established/default-download option.
Ship a separate `0.6.4-model-preview.1` portable quality trial bundling Parakeet:
better human-sample WER than the small model, substantially faster and smaller than
Whisper on this PC. This is a candidate, not a proven universal best model or a
final production-default change. Whisper is unattractive as a CPU dictation default
on this machine due to roughly real-time decoding. Qwen and broader dictation tests
remain open.

Portable Parakeet packages contain `models/inlaut-model.json` with
`{"family":"nemo-tdt","name":"Parakeet TDT 0.6B v3 INT8"}`. `SherpaEngine`
reads that explicit family and selects greedy decoding. Absent a profile, existing
NeMo behavior is preserved. Invalid families fail visibly instead of being guessed.
The benchmark also supports explicit `whisper`; that is not yet a tray model picker.
Startup diagnostics record the actual configuration. The benchmark now catches
unsupported input formats and exits with code 1 instead of raising a crash dialog.

Before a release-default change, include spontaneous dictation, different human
voices, background noise, silence, short utterances, names, numbers, punctuation
and mixed German/English. Check model redistribution terms and memory on a smaller
Windows device. A bigger model is justified only by measured user-relevant gains.
