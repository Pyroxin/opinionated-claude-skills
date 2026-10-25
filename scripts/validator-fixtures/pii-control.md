# PII scan positive control

The PII scan reads this file to show that each detector responds before its
clean result on real content is believed. Every value below except the email
address comes from Presidio's own tests, so it's known to be detectable (see
Sources).

Card on file: 4111111111111111.

Social security number: 219-09-9999.

Taxpayer identification number (ITIN): 911-70-1234.

Contact the account holder, Dan Tailor, at dan.tailor@example.org or by phone
at (415) 555-0132.

Bank account IBAN: GB29 NWBK 6016 1331 9268 19.

## Sources

Every sample except the email address comes from Presidio's own tests, so it's
known to be detectable (data-privacy-stack/presidio at commit
fd78e974fbf9e15dad1f90de4fc125db39ef4200):

- Card: presidio-analyzer/tests/test_credit_card_recognizer.py, line 39
  (https://github.com/data-privacy-stack/presidio/blob/fd78e974fbf9e15dad1f90de4fc125db39ef4200/presidio-analyzer/tests/test_credit_card_recognizer.py#L39)
- SSN: presidio-analyzer/tests/test_us_ssn_recognizer.py, line 43
  (https://github.com/data-privacy-stack/presidio/blob/fd78e974fbf9e15dad1f90de4fc125db39ef4200/presidio-analyzer/tests/test_us_ssn_recognizer.py#L43)
- ITIN: presidio-analyzer/tests/test_us_itin_recognizer.py, line 23
  (https://github.com/data-privacy-stack/presidio/blob/fd78e974fbf9e15dad1f90de4fc125db39ef4200/presidio-analyzer/tests/test_us_itin_recognizer.py#L23)
- Phone: presidio-analyzer/tests/test_phone_recognizer.py, line 19
  (https://github.com/data-privacy-stack/presidio/blob/fd78e974fbf9e15dad1f90de4fc125db39ef4200/presidio-analyzer/tests/test_phone_recognizer.py#L19)
- IBAN: presidio-analyzer/tests/test_iban_recognizer.py, line 324
  (https://github.com/data-privacy-stack/presidio/blob/fd78e974fbf9e15dad1f90de4fc125db39ef4200/presidio-analyzer/tests/test_iban_recognizer.py#L324)
- Name: presidio-analyzer/tests/test_spacy_recognizer.py, line 51
  (https://github.com/data-privacy-stack/presidio/blob/fd78e974fbf9e15dad1f90de4fc125db39ef4200/presidio-analyzer/tests/test_spacy_recognizer.py#L51)

Person names are detected by a statistical model rather than a fixed pattern,
so the name's test shows that Presidio's model tags it, not that every model
version must. The phone number is also in 555-0100 through 555-0199, which the
North American Numbering Plan Administrator reserves as "fictitious,
non-working numbers" (https://nanpa.com/numbering/555-line-numbers). The email
domain is example.org.
