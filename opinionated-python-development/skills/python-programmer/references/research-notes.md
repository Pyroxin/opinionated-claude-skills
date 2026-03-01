# Research Notes — Python Programmer Skill Update (February 2026)

These notes document the research sources used for the February 2026 skill revision.

## Ruff

- Current version: 0.15.4 (released 2026-02-26)
- Replaces Black + Flake8 + isort + pydocstyle + pyupgrade
- DOC rules (from pydoclint) are ALL in preview; DOC101 (missing parameter) not yet implemented
- D417 (undocumented-param) is stable but only works for Google-style docstrings
- Ruff's S rules provide partial Bandit coverage; not complete for cryptographic checks
- 111M monthly PyPI downloads vs Black's 90M (December 2025)
- Sources:
  - https://pypi.org/project/ruff/
  - https://astral.sh/blog/ruff-v0.15.0
  - https://docs.astral.sh/ruff/rules/
  - https://github.com/astral-sh/ruff/issues/12434 (pydoclint implementation tracker)

## uv vs Hatch

- uv: v0.10.7 (2026-02-27). Handles init, deps, lockfiles, build, publish, script execution
- Hatch: v1.16.5 (2026-02-27). Still actively maintained
- Hatch's unique advantage: declarative matrix testing (`hatch test --all`)
- Community consensus: uv alone for most projects; Hatch alongside for local multi-version testing
- Sources:
  - https://docs.astral.sh/uv/
  - https://hatch.pypa.io/1.16/blog/2025/11/24/hatch-v1160/
  - https://www.reddit.com/r/Python/comments/1k108g3/new_python_project_uv_always_the_solution/

## Python Versions

- 3.14 released October 7, 2025 (current stable, on 3.14.3)
- 3.13 in bugfix maintenance; 3.12 in security-only mode
- 3.15 in alpha (targeting October 2026)
- PEP 695 type parameter syntax: stable in 3.12
- PEP 649/749 deferred annotations: default in 3.14
- PEP 750 t-strings: stable in 3.14
- PEP 779 free-threaded build: officially supported in 3.14 (Phase II)
- `from __future__ import annotations`: not deprecated, mandatory="Never", but superseded by PEP 649
- JIT compiler: still experimental, often slower than interpreter (Ken Jin, July 2025)
- Recommended minimum: 3.12 pragmatic, 3.13 recommended target
- Sources:
  - https://docs.python.org/3/whatsnew/3.14.html
  - https://peps.python.org/pep-0649/
  - https://peps.python.org/pep-0779/
  - https://devguide.python.org/versions/
  - https://blog.python.org/2026/02/python-3143-and-31312-are-now-available.html

## Type Checkers

- mypy: v1.19.1 (December 2025), 58% adoption (2025 Typed Python Survey, n=1,241)
- pyright: dominant IDE checker, richer narrowing, checks unannotated code by default
- basedpyright: v1.38.2 (2026-02-26), community fork with extra LSP features
- ty: v0.0.19 (beta since December 2025), ~15% conformance, very fast, no Pydantic/Django support
- Sources:
  - https://pypi.org/project/mypy/
  - https://astral.sh/blog/ty
  - https://github.com/astral-sh/ty/releases
  - https://www.infoq.com/news/2026/01/facebook-typed-python-survey/
  - https://sinon.github.io/future-python-type-checkers/

## pydoclint

- v0.8.3 (released 2025-11-26)
- Replaces darglint (archived December 2022)
- Supports Sphinx, Google, NumPy styles
- 1,475x faster than darglint on numpy
- Sources:
  - https://pypi.org/project/pydoclint/
  - https://jsh9.github.io/pydoclint/
  - https://github.com/jsh9/pydoclint
