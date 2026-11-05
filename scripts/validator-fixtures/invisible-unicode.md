Positive control for the invisible-Unicode check, scripts/unicode-scan.py, which install-and-verify.sh runs on this file. Each line below names the code point it holds, between the brackets, so the file can be read without a viewer that shows them.

Tag character U+E0041: [󠁁]
Bidirectional override U+202E: [‮]
Bidirectional isolate U+2066: [⁦]
Left-to-right mark U+200E: [‎]
Arabic letter mark U+061C: [؜]
Zero width space U+200B: [​]
Zero width non-joiner U+200C: [‌]
Word joiner U+2060: [⁠]
Byte order mark U+FEFF, not at the start of the file: [﻿]
Variation selector supplement U+E0100, after a letter: [A󠄀]
Zero width joiner U+200D, between two emoji: [👩‍💻]
Soft hyphen U+00AD, a format character not named above: [­]
A second variation selector U+FE0F after U+FE0F: [⚠️️]
️ <- variation selector U+FE0F at the start of a line, with no base character before it

Look-alikes the check must skip: an emoji with its presentation selector [⚠️], a text-presentation selector [☺︎], other non-ASCII text [café — 中文], and code points named in ASCII (U+200B, U+202E).
It must report exactly 14 findings, one per line from the tag character through the line-start variation selector.
