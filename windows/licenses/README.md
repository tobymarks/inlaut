# Windows dependency licenses and notices

The installer preserves inlaut's GNU GPLv3 license in `../LICENSE`. This folder
contains the separate licenses and notices for redistributed dependencies.
Model attribution, CC BY 4.0 links and the ONNX export/quantization statement are
in `../BETA.md` in the installed application (source: `windows/installer/BETA.md`).

## Files copied from the packages actually published

`Build-Beta.ps1` reads the app's resolved NuGet assets and published runtime config.
It copies the original license and available third-party notice files from these
restored packages into `<package>/<version>/`, and records their exact versions and
NuGet source links in the installed `nuget-packages.json`:

- [System.Numerics.Tensors](https://www.nuget.org/packages/System.Numerics.Tensors),
  which NAudio.Core 3 depends on (MIT and its included third-party notices).
- The packages NAudio asks for: since .NET 10 the Microsoft.Win32.Registry, System.Security.AccessControl and
  System.Security.Principal.Windows packages NAudio asks for are no longer
  restored: the shared framework contains them, so their assemblies and notices
  come with the runtime packages below. Packaging fails if they reappear as packages.
- [Microsoft.NETCore.App.Runtime.win-x64](https://www.nuget.org/packages/Microsoft.NETCore.App.Runtime.win-x64)
  (MIT and its included third-party notices).
- [Microsoft.WindowsDesktop.App.Runtime.win-x64](https://www.nuget.org/packages/Microsoft.WindowsDesktop.App.Runtime.win-x64)
  (MIT); the WPF and WinForms third-party notices absent from that package are
  preserved below from the source commit of the 10.0.14 runtime packages,
  [`dotnet/dotnet@0427b9a`](https://github.com/dotnet/dotnet/tree/0427b9abbead3fa64c6655eb4290c537397131fa)
  (the `<repository>` commit in both runtime packages' nuspec).

Both the app and its self-contained update helper use the same .NET runtime.
No license file is downloaded during packaging. A missing package/license or a
runtime/dependency upgrade requiring refreshed upstream notices fails packaging.

## Pinned upstream originals

The NAudio 3.3.0 NuGet packages (NAudio, Core, Midi, Wasapi, WinMM; MIT, Mark Heath)
declare MIT only in their nuspec and ship no license file. The license is the
upstream original from the `v3.3.0` tag,
[`naudio/NAudio@4f8889e`](https://github.com/naudio/NAudio/tree/4f8889e2bd34c3978a25652c6c172fa1502ccba3);
`nuget-packages.json` lists every restored NAudio package with it. Packaging fails
for any other NAudio version until this file is refreshed.

The sherpa-onnx 1.13.8 NuGet packages declare Apache-2.0 but do not ship the license
text. Its package repository commit is
[`dc5583f49917e4c95f6e7d862bb378e4ed5e9076`](https://github.com/k2-fsa/sherpa-onnx/tree/dc5583f49917e4c95f6e7d862bb378e4ed5e9076)
(Copyright 2019–2023 Xiaomi Corporation, as stated by the package).
Its Windows x64 [CMake dependency](https://github.com/k2-fsa/sherpa-onnx/blob/dc5583f49917e4c95f6e7d862bb378e4ed5e9076/cmake/onnxruntime-win-x64.cmake)
and the packaged DLL identify ONNX Runtime **1.28.2**. The matching MIT license
and complete upstream ThirdPartyNotices are included.

The native sherpa package also contains functionality beyond the FastConformer
recognizer used by inlaut. The license set below preserves notices for its native
build dependencies, including speech synthesis and diarization dependencies;
this does not mean that inlaut enables those features. Versions/commits come from
the pinned sherpa CMake files and their nested dependency files. ONNX Runtime's
complete notice file also includes Eigen's MPL-2.0 license. Source for Eigen 3.4.0
used by kaldi-decoder is at [libeigen/eigen](https://gitlab.com/libeigen/eigen/-/tree/3.4.0).

Files below are unmodified upstream originals. `sources.json` records each exact
source URL and SHA-256; packaging verifies all these hashes before installation.
When dependencies change, update these files and provenance together.

| Installed file | Exact source |
| --- | --- |
| `naudio/LICENSE` | [upstream original](https://raw.githubusercontent.com/naudio/NAudio/4f8889e2bd34c3978a25652c6c172fa1502ccba3/LICENSE) |
| `sherpa-onnx/LICENSE` | [upstream original](https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/dc5583f49917e4c95f6e7d862bb378e4ed5e9076/LICENSE) |
| `onnxruntime/LICENSE` | [upstream original](https://raw.githubusercontent.com/microsoft/onnxruntime/33ca9628233dc8f002435e868d4c2e9f82766ca1/LICENSE) |
| `onnxruntime/ThirdPartyNotices.txt` | [upstream original](https://raw.githubusercontent.com/microsoft/onnxruntime/33ca9628233dc8f002435e868d4c2e9f82766ca1/ThirdPartyNotices.txt) |
| `windowsdesktop-wpf/THIRD-PARTY-NOTICES.TXT` | [upstream original](https://raw.githubusercontent.com/dotnet/dotnet/0427b9abbead3fa64c6655eb4290c537397131fa/src/wpf/THIRD-PARTY-NOTICES.TXT) |
| `windowsdesktop-winforms/THIRD-PARTY-NOTICES.TXT` | [upstream original](https://raw.githubusercontent.com/dotnet/dotnet/0427b9abbead3fa64c6655eb4290c537397131fa/src/winforms/THIRD-PARTY-NOTICES.TXT) |
| `kaldi-native-fbank/LICENSE` | [upstream original](https://raw.githubusercontent.com/csukuangfj/kaldi-native-fbank/b09e686fe2084732ddd30d1ef80acfc0f13eaf01/LICENSE) |
| `kaldi-decoder/LICENSE` | [upstream original](https://raw.githubusercontent.com/k2-fsa/kaldi-decoder/62fda2d74246a90db9570e46fb16b012f813fae7/LICENSE) |
| `kaldifst/LICENSE` | [upstream original](https://raw.githubusercontent.com/k2-fsa/kaldifst/ab5bdd013bdf13921e6aeee77db5722ebf9955fb/LICENSE) |
| `openfst/COPYING` | [upstream original](https://raw.githubusercontent.com/csukuangfj/openfst/f702a6317d600ac953fdbb4978674c3a28b6115c/COPYING) |
| `simple-sentencepiece/LICENSE` | [upstream original](https://raw.githubusercontent.com/pkufool/simple-sentencepiece/62dd423df1d51da5ea06f1c3a046fc04f01b4f39/LICENSE) |
| `piper-phonemize/LICENSE.md` | [upstream original](https://raw.githubusercontent.com/csukuangfj/piper-phonemize/f3ff95afc03640bc1399e113e83361192a2fafb4/LICENSE.md) |
| `piper-phonemize/licenses/uni-algo/LICENSE.md` | [upstream original](https://raw.githubusercontent.com/csukuangfj/piper-phonemize/f3ff95afc03640bc1399e113e83361192a2fafb4/licenses/uni-algo/LICENSE.md) |
| `espeak-ng/COPYING` | [upstream original](https://raw.githubusercontent.com/csukuangfj/espeak-ng/ed530aa113046142eb5115cf2fc9157854d0ffe1/COPYING) |
| `espeak-ng/COPYING.APACHE` | [upstream original](https://raw.githubusercontent.com/csukuangfj/espeak-ng/ed530aa113046142eb5115cf2fc9157854d0ffe1/COPYING.APACHE) |
| `espeak-ng/COPYING.BSD2` | [upstream original](https://raw.githubusercontent.com/csukuangfj/espeak-ng/ed530aa113046142eb5115cf2fc9157854d0ffe1/COPYING.BSD2) |
| `espeak-ng/COPYING.UCD` | [upstream original](https://raw.githubusercontent.com/csukuangfj/espeak-ng/ed530aa113046142eb5115cf2fc9157854d0ffe1/COPYING.UCD) |
| `espeak-ng/src/ucd-tools/COPYING` | [upstream original](https://raw.githubusercontent.com/csukuangfj/espeak-ng/ed530aa113046142eb5115cf2fc9157854d0ffe1/src/ucd-tools/COPYING) |
| `espeak-ng/src/ucd-tools/COPYING.UCD` | [upstream original](https://raw.githubusercontent.com/csukuangfj/espeak-ng/ed530aa113046142eb5115cf2fc9157854d0ffe1/src/ucd-tools/COPYING.UCD) |
| `hclust-cpp/LICENSE` | [upstream original](https://raw.githubusercontent.com/csukuangfj/hclust-cpp/db76039198979ce8d03632ab6ef14fe6accb127c/LICENSE) |
| `json/LICENSE.MIT` | [upstream original](https://raw.githubusercontent.com/nlohmann/json/55f93686c01528224f448c19128836e7df245f72/LICENSE.MIT) |
| `kissfft/COPYING` | [upstream original](https://raw.githubusercontent.com/mborgerding/kissfft/febd4caeed32e33ad8b2e0bb5ea77542c40f18ec/COPYING) |
| `kissfft/LICENSES/BSD-3-Clause` | [upstream original](https://raw.githubusercontent.com/mborgerding/kissfft/febd4caeed32e33ad8b2e0bb5ea77542c40f18ec/LICENSES/BSD-3-Clause) |
| `asio/asio/LICENSE_1_0.txt` | [upstream original](https://raw.githubusercontent.com/chriskohlhoff/asio/147f7225a96d45a2807a64e443177f621844e51c/asio/LICENSE_1_0.txt) |
| `websocketpp/COPYING` | [upstream original](https://raw.githubusercontent.com/zaphoyd/websocketpp/b9aeec6eaf3d5610503439b4fae3581d9aff08e8/COPYING) |
| `portaudio/LICENSE.txt` | [upstream original](https://raw.githubusercontent.com/PortAudio/portaudio/147dd722548358763a8b649b3e4b41dfffbcfbb6/LICENSE.txt) |
| `cargs/LICENSE.md` | [upstream original](https://raw.githubusercontent.com/likle/cargs/5bbcfca833eeb504996afb85ad5b8470c96dc752/LICENSE.md) |
