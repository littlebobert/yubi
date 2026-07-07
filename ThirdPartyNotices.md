# Third-Party Notices

## wordfreq

Yubi can generate its bundled word-frequency dictionary from the `wordfreq` Python package during the keyboard extension build.

- Project: `wordfreq`
- Author: Robyn Speer
- Repository: https://github.com/rspeer/wordfreq
- Package license: Apache License 2.0
- Included/derived frequency data: Creative Commons Attribution-ShareAlike 4.0

If `wordfreq` is used to generate `YubiKeyboard/Generated/WordFrequencies.json`, that generated dictionary is derived from `wordfreq` data and should be redistributed with the applicable attribution and share-alike notices.

The generated dictionary is intentionally ignored by git. Regenerate it locally with:

```sh
python3 -m pip install wordfreq
python3 Scripts/generate_word_frequencies.py YubiKeyboard/Generated/WordFrequencies.json 30000
```

`wordfreq` documents additional source attributions for data including Google Books Ngrams, Wikipedia, OpenSubtitles, SUBTLEX, and other corpora. See the upstream project for the complete notice text.
