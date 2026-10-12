# Contributing to inlaut

Thanks for wanting to help. inlaut is a small project with one maintainer, so short and focused contributions work best.

## Questions, bugs and ideas

Open an [issue](https://github.com/tobymarks/inlaut/issues). The issues are also the roadmap. Please write in English; say which inlaut and macOS version you use and, for recognition problems, which language setting and engine. Never attach recordings or dictated text you would not want to be public.

Security problems do not belong in a public issue. See [SECURITY.md](SECURITY.md).

## Pull requests

1. For anything bigger than a small fix, open an issue first so we can agree on the direction.
2. Fork, create a branch from `main` and send a pull request against `main`.
3. Keep one topic per pull request. The commit message explains why the change is needed, not only what it does.
4. GitHub Actions builds the app and runs the tests on every pull request. It has to pass.

How to build and run the tests is described in the [README](README.md#build).

## What a change has to meet

- Swift 6 language mode, no new compiler warnings.
- Code, comments, commit messages and issues are in English and read like the surrounding code.
- User-visible strings are written in English in the source. German lives in `Resources/Localizable.xcstrings`; run `python3 scripts/check-localizations.py` after adding text.
- The product name is always written in lowercase: inlaut.
- Never log or store dictated text. Lengths and timings only.
- No new network connections, accounts or telemetry. inlaut talks to the model host once and to the update feed, and that is part of what it promises.

## Tests

New functionality that can be tested without a microphone or a real key press comes with tests in `Tests/`, and a bug fix comes with a test that fails without it where that is practical. Tests must not touch the general clipboard or the microphone. Behaviour that needs real hardware (hot key, 🌐 key, recording) is checked by hand; say in the pull request what you tried.

## Licence

inlaut is licensed under GPL-3.0-or-later. By contributing you agree that your contribution is published under the same licence. The name, logo and icons are not covered by the GPL, see [design/LICENSE-ASSETS.md](design/LICENSE-ASSETS.md).
