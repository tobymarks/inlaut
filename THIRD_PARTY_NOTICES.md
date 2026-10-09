# Third-party notices

inlaut downloads or bundles the following components.

## Speech model (downloaded on first start)

**Parakeet Ultra** — post-training of NVIDIA Parakeet TDT 0.6B v3 by [moondream](https://huggingface.co/moondream/parakeet-ultra), Core ML export by [FluidInference](https://huggingface.co/FluidInference/parakeet-ultra-coreml).
Licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Used unmodified, pinned to revision `95eaa59a39d4394f047a4dc5cce480388a60d1b6`.

Based on **NVIDIA Parakeet TDT 0.6B v3** — [nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

## Libraries (bundled)

**FluidAudio** 0.17.7 — Copyright FluidInference and contributors, [Apache License 2.0](https://github.com/FluidInference/FluidAudio/blob/v0.17.7/LICENSE). Runs the speech model with Core ML on the Neural Engine. Built without its optional NemoTextProcessing component. Includes fastcluster (BSD 2-Clause). Licenses in `Resources/Licenses/FluidAudio.txt` and in the app bundle.

**Sparkle** 2.10.0 — Copyright Sparkle Project contributors, [MIT License](https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE). Used for signed application updates. Its license and third-party notices are included in `Resources/Licenses/Sparkle.txt` and in the app bundle.
