---
name: python-programmer
description: Python-specific idioms, philosophy, and expert-level patterns. Use when working with Python code, including Jupyter notebooks (.ipynb). Covers Pythonic thinking, common pitfalls from other language backgrounds, testing ecosystem navigation, type hints trade-offs, and when to use modern Python features.
---

# Python Programmer

## Purpose

This skill provides guidance on Python-specific idioms, philosophy, and expert-level judgment calls. Python's design emphasizes readability and "one obvious way" to do things, but achieving truly Pythonic code requires understanding when and why to use Python's idioms. This skill focuses on expert-level decisions, common pitfalls from other language backgrounds, and navigating Python's evolving ecosystem.

## When to Use This Skill

Use this skill when:
- Working with Python code
- Deciding when Python is the right tool for a problem
- Navigating between Python's "obvious ways" and edge cases
- Choosing between testing frameworks, type systems, or async patterns
- Avoiding anti-patterns from Java, C, or JavaScript backgrounds
- Making trade-offs between Pythonic idioms and performance

<core_philosophy>
## Core Philosophy

**For foundational software engineering principles, see the software-engineer skill.**

### The Zen of Python (PEP 20)

Python's design philosophy is captured in "The Zen of Python" (import this to see it). Key principles that guide Pythonic code:

**Quote to remember:** "Explicit is better than implicit. Simple is better than complex. Readability counts." — Tim Peters, PEP 20

**What this means in practice:**
- Favor clarity over cleverness
- One obvious way beats multiple equivalent ways
- Code is read more than written (optimize for readers)
- Practicality beats purity (Python isn't a pure functional or OO language)

**Staff insight:** The Zen is philosophy, not law. Sometimes implicit is fine (context managers hide `__enter__` and `__exit__`). Sometimes there are two ways (list comprehension vs `map`). The Zen guides judgment; it doesn't eliminate it.

<eafp_principle>
### EAFP: Easier to Ask Forgiveness than Permission

Python culture prefers trying operations and handling exceptions over checking conditions first.

**EAFP (Pythonic):**
```python
try:
    value = my_dict[key]
except KeyError:
    value = default
```

**LBYL (Look Before You Leap - unpythonic):**
```python
if key in my_dict:
    value = my_dict[key]
else:
    value = default
```

**When EAFP wins:**
- Operations that might fail (file access, network calls, dict lookups)
- Race conditions matter (checking then acting creates gaps)
- Exceptional cases are rare (exceptions aren't expensive in Python)
- Code reads cleaner without defensive checks

**When LBYL is acceptable:**
- Pre-flight validation before expensive operations
- Control flow where exceptions obscure logic
- Performance-critical tight loops (check once, execute many)

**Staff insight:** EAFP isn't about exceptions being "free" — it's about correctness and clarity. The file existence check has a race condition; the exception handling doesn't. But don't abuse EAFP for control flow in loops.
</eafp_principle>

<duck_typing>
### Duck Typing Over Type Checking

"If it walks like a duck and quacks like a duck, it's a duck." Python prefers protocols (behavior) over explicit types.

**Duck typing:**
- Accept any object that supports needed operations
- Don't check types explicitly (isinstance is a code smell, usually)
- Design for protocols, not inheritance hierarchies

**When duck typing works:**
- Functions accepting "file-like objects" (read, write, close)
- Iterables (anything supporting `__iter__`)
- Mappings (anything supporting `__getitem__`)

**When explicit types help:**
- Type hints for documentation and IDE support
- `isinstance` with abstract base classes (collections.abc)
- Validating user input or external data

**Staff insight:** Type hints and duck typing coexist. Use protocols (`typing.Protocol`) for duck-typed interfaces, not concrete types. Type hints document expectations; duck typing provides flexibility.
</duck_typing>
</core_philosophy>

## Fundamental Principles

### Comprehensions Are the Default for Transformations

List/dict/set comprehensions are the Pythonic way to transform collections. Use them unless clarity suffers.

**When comprehensions win:**
- Simple transformations (`[x*2 for x in numbers]`)
- Filtering (`[x for x in items if condition]`)
- Cartesian products (`[(x,y) for x in a for y in b]`)
- Clarity improves over explicit loops

**When to use explicit loops:**
- Complex logic that obscures comprehension readability
- Side effects (comprehensions shouldn't have side effects)
- Early termination needed (use generator with `next` or explicit loop)

**Staff insight:** "Map/filter vs comprehensions" isn't about performance — comprehensions are usually faster and always more readable in Python. Save `map` for when you already have a function reference. Don't use `map(lambda ...)` — that's unpythonic.

### Context Managers for Resource Management

The `with` statement ensures cleanup happens. Always use it for files, locks, database connections.

**Why context managers matter:**
- Guarantee cleanup even with exceptions
- Make resource lifetime explicit
- Prevent resource leaks

**When to create context managers:**
- Managing paired operations (acquire/release, open/close)
- Temporary state changes (changing directory, mocking)
- Transactions (begin/commit/rollback)

**Staff insight:** The `contextlib` module provides helpers: `contextmanager` decorator for simple cases, `ExitStack` for dynamic resource management. Don't write try/finally when a context manager expresses intent better.

### Iterators and Generators Over Materialized Lists

Python's iterators are lazy by design. Use them to avoid unnecessary memory allocation.

**When generators win:**
- Large or infinite sequences
- One-pass iteration suffices
- Composing transformations (map/filter chains)
- Memory matters more than random access

**When lists are needed:**
- Multiple passes over data
- Random access required
- Length needed upfront
- Debugging (generators can't be inspected without consuming)

**Staff insight:** Generator expressions `(x for x in items)` are like comprehensions but lazy. Use them in function calls that consume iterables: `sum(x**2 for x in numbers)` doesn't build a list. But don't cargo-cult generators — lists are fine for small data.

### Mutable Default Arguments Are Dangerous

Default arguments are evaluated once at function definition, not each call. Mutable defaults (lists, dicts) persist across calls.

**The classic footgun:**
```python
def append_to(element, to=[]):  # BUG: list persists across calls
    to.append(element)
    return to

append_to(1)  # [1]
append_to(2)  # [1, 2] - NOT [2]!
```

**The fix:**
```python
def append_to(element, to=None):
    if to is None:
        to = []
    to.append(element)
    return to
```

**When this matters:**
- Any mutable default (list, dict, set, custom objects)
- Class methods with default arguments
- Cached computation in default arguments (evaluated at import time)

**Staff insight:** This isn't a bug — it's how Python works. Defaults are values, not expressions. Use `None` as a sentinel, or document the sharing behavior if it's intentional (rare).

## When Python Works Well

Python excels in specific problem domains. Recognize when Python's strengths align with your needs.

**Problem characteristics favoring Python:**

**Rapid prototyping and iteration:**
- Fast development cycle matters more than runtime performance
- Requirements are evolving
- Exploratory programming (data science, research)

**Scripting and automation:**
- Glue code between systems
- System administration tasks
- Build and deployment scripts
- Data processing pipelines

**Data analysis and scientific computing:**
- Rich ecosystem (NumPy, pandas, scikit-learn)
- Jupyter notebooks for interactive exploration
- Visualization libraries (matplotlib, seaborn)
- Integration with C/Fortran for performance

**Web services and APIs:**
- Django/Flask for rapid API development
- FastAPI for modern async APIs with type hints
- Mature ecosystem (ORMs, auth, testing)
- Good enough performance for most services

**Education and accessibility:**
- Readable syntax lowers entry barrier
- Interactive REPL for experimentation
- Extensive documentation and community

## When Python Struggles

**Avoid Python when:**

**Performance-critical computation:**
- Tight loops over large data (use NumPy or drop to C/Rust)
- Real-time systems with latency requirements
- Video/audio processing, graphics, games
- High-throughput services (consider Go, Java, Rust)

**Mobile development:**
- No first-class mobile platform support
- Kivy/BeeWare exist but aren't mainstream
- Battery impact of interpreted language
- Distribution and packaging challenges

**Systems programming:**
- Low-level hardware access
- Operating system components
- Device drivers
- Memory layout control needed

**Parallel computation:**
- GIL (Global Interpreter Lock) prevents true parallelism for CPU-bound tasks
- Use multiprocessing (expensive process creation) or drop to C
- Async/await helps with I/O-bound, not CPU-bound

**Large-scale applications with many developers:**
- Dynamic typing can hinder refactoring at scale
- Type hints help but aren't enforced at runtime
- Consider statically-typed languages (Java, C#, TypeScript) for very large teams

**Staff insight:** Python's sweet spot is prototyping, scripting, data processing, and web services. Don't force it into low-level, high-performance, or mobile domains. Use Python where its strengths (development speed, ecosystem, readability) outweigh its weaknesses (performance, GIL, mobile).

## Staff-Level Insights

### Type Hints and Documentation Are Essential

Python 3.5+ supports type hints (PEP 484), and they're mandatory for quality code.

**Why type hints matter:**
- Explicit, machine-readable contracts (unambiguous, can't drift from code)
- Enable static analysis (mypy/pyright) to catch errors before runtime
- **Critical for LLM-assisted development** (type information enables better code generation and reasoning)
- IDE autocomplete and refactoring support
- Self-documenting code (types visible in signatures)
- Large codebases benefit from explicit interfaces

**Where to use type hints (default: everywhere):**
- All public APIs and module boundaries (required)
- All function signatures: parameters and return types (required)
- Class attributes, especially in `__init__` (required)
- Complex data structures (required)
- Internal functions in non-trivial modules (recommended)
- Local variables only when type isn't obvious (optional)

**When type hints can be skipped:**
- Throwaway scripts (< 50 lines, one-time use)
- Local variables with obvious types from context
- When type checker limitations force objectively worse code (rare, file a bug)

**Staff insight:** Type hints aren't optional for production code. They provide explicit contracts that enable both humans and LLMs to reason about code. The "verbosity" argument is weak — good types make code more readable and maintainable. Use them everywhere except throwaway scripts.

**Modern type hint features:**
- `from __future__ import annotations` for forward references (use in 3.7-3.9)
- `TypedDict` for structured dictionaries
- `Protocol` for structural subtyping (duck typing with types)
- `ParamSpec` and `Concatenate` for higher-order functions
- `typing.assert_never` for exhaustiveness checking in match statements

### Sphinx Documentation Is Mandatory

Python documentation uses Sphinx with reStructuredText (or MyST for Markdown). Comprehensive documentation is not optional.

**Documentation requirements:**

**Every module:**
- Module-level docstring explaining purpose and main components
- Examples of common usage patterns
- Important considerations, limitations, or edge cases

**Every public class:**
- Class docstring with clear purpose
- Explanation of responsibilities and invariants
- Usage examples for non-trivial classes
- Attributes documented with `:ivar:` or in class docstring

**Every public function/method:**
- One-sentence summary (first line)
- Detailed description of purpose and behavior
- Parameters documented with `:param:` and `:type:` (even with type hints - doc serves different purpose)
- Return value documented with `:returns:` and `:rtype:`
- Raised exceptions documented with `:raises:`
- Usage examples for non-trivial functions
- Important notes about edge cases, performance, or thread safety

**Every test:**
- Docstring explaining what behavior is being tested
- Why the test exists (what requirement it validates)
- Special considerations (test data setup, known limitations)

**Sphinx docstring format:**

```python
def process_items(
    items: list[Item],
    filter_func: Callable[[Item], bool] | None = None,
    max_count: int = 100
) -> list[Item]:
    """Process a list of items with optional filtering.

    This function processes items by applying an optional filter function
    and limiting results to a maximum count. Processing maintains the
    original order of items.

    :param items: The list of items to process. Must not be empty.
    :type items: list[Item]
    :param filter_func: Optional function to filter items. If None,
        all items are included.
    :type filter_func: Callable[[Item], bool] | None
    :param max_count: Maximum number of items to return. Must be
        positive.
    :type max_count: int
    :returns: Processed and filtered items, up to max_count.
    :rtype: list[Item]
    :raises ValueError: If items list is empty or max_count is not
        positive.
    :raises TypeError: If filter_func is not callable.

    Example usage::

        items = [Item(1), Item(2), Item(3)]
        result = process_items(items, lambda x: x.value > 1, max_count=10)

    .. note::
        This function does not modify the input list. A new list is
        returned.

    .. warning::
        For very large lists (>10000 items), consider using
        :func:`process_items_streaming` instead for better memory
        efficiency.
    """
    # Implementation
```

**Sphinx formatting guidelines:**

**ReStructuredText elements:**
- Use proper reST formatting (no Markdown in docstrings)
- Code examples in `::` blocks with proper indentation
- Cross-references with `:func:`, `:class:`, `:meth:`, `:mod:`
- Emphasis with `*italic*` and `**bold**`
- Inline code with double backticks: ``code``
- Lists with proper bullet/numbered formatting

**Semantic markup:**
- Use `.. note::` for important information
- Use `.. warning::` for critical gotchas or edge cases
- Use `.. deprecated::` for deprecated functionality
- Use `.. versionadded::` and `.. versionchanged::` for API evolution

**Why both type hints AND Sphinx `:type:` annotations:**
- Type hints: Machine-readable, for static analysis and LLMs
- Sphinx `:type:`: Human-readable, can include constraints and context
- Example: Type hint is `int`, Sphinx says ":type: int (must be positive)"

**Documentation philosophy:**
- Document WHY, not just WHAT (explain purpose and design choices)
- Include usage examples for non-obvious functionality
- Explain limitations and edge cases
- Assume readers are junior engineers or LLMs needing context
- Good documentation describes **why something exists** and **how to use it correctly**, not just repeating the signature

**Private members:**
- Private functions/methods still need docstrings (prefix with underscore)
- Explain intended use within the module
- Document assumptions and invariants

**Staff insight:** Comprehensive Sphinx documentation is as important as type hints. Type hints tell you the types; documentation tells you why the function exists, how to use it correctly, and what can go wrong. Both are mandatory for production code.

<python_tooling>
### Python Tooling Requirements

All new Python projects must use modern tooling for dependency management, formatting, linting, and type checking.

**Mandatory tools for all new projects:**

**Hatch (project management):**
- Modern Python project manager replacing setuptools
- Manages environments, builds, and publishing
- Standardized project structure (PEP 621 pyproject.toml)
- Built-in environment isolation
- Use for: All new projects (no exceptions)

**UV (package installation):**
- Ultra-fast Python package installer (10-100x faster than pip)
- Written in Rust, drop-in pip replacement
- Lock file support for reproducible builds
- Use with Hatch for environment management
- Use for: All new projects (no exceptions)

**Black (code formatting):**
- Uncompromising code formatter ("the uncompromising formatter")
- Zero configuration, deterministic formatting
- Ends formatting debates (consistency over personal preference)
- Must be enabled in CI/CD pipeline
- Configure in pyproject.toml, run on all code

**Bandit (security linting):**
- Security vulnerability scanner for Python code
- Catches common security issues (SQL injection, hardcoded passwords, etc.)
- Must be enabled in CI/CD pipeline
- Configure in pyproject.toml

**Flake8 (style guide enforcement):**
- PEP 8 style guide checker
- Enforces code style consistency
- Plugins available for additional checks
- Must be enabled in CI/CD pipeline
- Configure in .flake8 or pyproject.toml

**MyPy (static type checking):**
- Static type checker for Python
- Enforces type hint correctness
- Catches type errors before runtime
- Must be enabled in CI/CD pipeline
- Configure in pyproject.toml with strict settings

**Example Project setup:**

This example file shows how to set up a project using the above requirements. Make sure to check what the latest versions of Python and the various packages used are!

```toml
# pyproject.toml example
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "my-project"
version = "0.1.0"
description = "Project description"
requires-python = ">=3.10"
dependencies = [
    "dependency1>=1.0",
]

[tool.hatch.envs.default]
dependencies = [
    "pytest>=7.0",
    "black>=23.0",
    "flake8>=6.0",
    "mypy>=1.0",
    "bandit>=1.7",
]

[tool.black]
line-length = 88
target-version = ['py310']

[tool.mypy]
python_version = "3.10"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true
disallow_incomplete_defs = true
check_untyped_defs = true
strict = true

[tool.bandit]
exclude_dirs = ["tests", "test_*.py"]
```

### Dependency Version Specification

**NEVER guess or assume dependency versions.** Verify current versions on PyPI before adding any dependency to `pyproject.toml`.

| Constraint | When to Use |
|------------|-------------|
| `>=MAJOR.MINOR` | Default—allows patch updates, guards against old bugs |
| `>=MAJOR.MINOR,<NEXT_MAJOR` | When major version breaks are likely |
| `==EXACT` | Avoid—use lock files for reproducibility instead |

**Staff insight:** LLMs confidently hallucinate version numbers. A guessed `>=0.3` when the current version is `1.1` invites breaking changes; a guessed `>=2.0` for a package at `1.5` fails on install. The cost of a PyPI search is trivial compared to debugging phantom compatibility issues. This is especially critical for fast-moving ecosystems (LangChain, ML libraries) where major versions ship monthly.

**CI/CD integration:**
- All tools must run in CI/CD pipeline (GitHub Actions, GitLab CI, etc.)
- Builds fail if any tool reports errors
- No exceptions for "I'll fix it later"

**Why these tools are mandatory:**
- **Consistency:** Black eliminates formatting arguments
- **Security:** Bandit catches vulnerabilities early
- **Quality:** Flake8 and MyPy enforce code standards
- **Speed:** UV and Hatch make development faster
- **Modern:** These are current best practices (not legacy tools)

**Staff insight:** Don't waste time debating formatting or choosing between pip/setuptools/Poetry. Use Black for formatting (no configuration), Hatch+UV for project management (modern, fast), and enable all linters/type checkers (catch problems early). These tools are mandatory, not optional.
</python_tooling>

<testing_ecosystem>
### Testing Ecosystem: pytest vs unittest

**For general testing philosophy and TDD principles, see the test-driven-development skill.** This section covers Python-specific testing practices.

Python has two major testing frameworks with different philosophies.

**unittest (standard library):**
- Java-style xUnit framework
- Classes, setUp/tearDown methods
- Verbose assertion methods (`self.assertEqual`)
- Built-in, no dependencies

**pytest (third-party, dominant):**
- Plain functions, not classes
- Simple `assert` statements with introspection
- Powerful fixture system
- Rich plugin ecosystem

**When to use pytest:**
- Starting new projects (it's the community standard)
- Want fixtures over setUp/tearDown
- Value concise test code
- Need plugins (coverage, parameterization, markers)

**When unittest is acceptable:**
- Existing unittest codebase (don't rewrite working tests)
- Can't add dependencies (embedded environments)
- Team already knows unittest

**Staff insight:** pytest won. It's more Pythonic (simple assertions, no classes), more powerful (fixtures), and has better tooling. Use pytest unless there's a specific reason not to. The `unittest.mock` module is still useful even with pytest.

**Core testing principle (from test-driven-development skill):** Mock at architectural boundaries (external systems, injected dependencies), not internal implementation details.
</testing_ecosystem>

<async_patterns>
### Async/Await: Not a Silver Bullet

Python 3.5+ has async/await for asynchronous I/O. It's powerful but often misunderstood.

**When async/await wins:**
- I/O-bound tasks (network requests, database queries)
- Many concurrent connections (web servers, websockets)
- Can amortize event loop overhead (not single requests)

**When async/await doesn't help:**
- CPU-bound tasks (GIL still applies)
- Blocking libraries (most DB drivers are synchronous)
- Simple scripts (overhead not justified)

**Common mistakes:**
- Mixing sync and async code (blocking the event loop)
- Not using `async` libraries (sync `requests` blocks async code)
- Premature optimization (threads often suffice)

**Staff insight:** Async isn't "free concurrency." You need async libraries (aiohttp, asyncpg, not requests/psycopg2). The event loop can't help if you're CPU-bound. Start with threads for I/O concurrency; move to async only if you have measurable evidence it helps.
</async_patterns>

### Python 2 vs 3: It's Over

Python 2 reached end-of-life in 2020. Don't write new Python 2 code.

**If maintaining Python 2 code:**
- Six library for compatibility
- 2to3 tool for automated migration
- `__future__` imports for Python 3 behavior

**Python 3 benefits:**
- Unicode strings by default (str, not bytes)
- Better exception handling (chained exceptions)
- Async/await support
- Type hints
- f-strings, pathlib, dataclasses

**Staff insight:** If you're stuck on Python 2, plan migration. If you're writing new code, use Python 3.10+ for modern features (match statements, union types with `|`).

<common_mistakes>
### Common Mistakes from Other Language Backgrounds

<from_java>
**From Java:**
- Java-style getters/setters (use properties or public attributes)
- Inheritance hierarchies (use composition, duck typing)
- Checked exceptions (Python has no checked exceptions)
- Verbose code (Python values conciseness)
</from_java>

<from_c>
**From C/C++:**
- Manual memory management thinking (trust the garbage collector)
- Pointer-like patterns (use references directly)
- Low-level optimization (profile first, most code isn't bottleneck)
</from_c>

<from_javascript>
**From JavaScript:**
- `var`/`let`/`const` thinking (Python has simpler scoping)
- Callback hell (use async/await or just sequential code)
- Prototypal inheritance (Python uses class-based)
</from_javascript>

**Staff insight:** Each language has idioms. Don't write Java in Python. Read "Fluent Python" or "Effective Python" to internalize Pythonic thinking.
</common_mistakes>

### Dataclasses and attrs: Boilerplate Reduction

Python 3.7+ has dataclasses for reducing class boilerplate. The `attrs` library is a more powerful alternative.

**When to use dataclasses:**
- Simple data containers (replacing namedtuples)
- Want `__init__`, `__repr__`, `__eq__` generated
- Type hints for documentation
- Frozen classes for immutability

**When to use attrs:**
- Need validators, converters, or defaults with factories
- Python < 3.7 (attrs works on 2.7+)
- Want more features (slots, metadata)

**When to skip both:**
- Dynamic attributes (use plain class or dict)
- Very few classes (boilerplate isn't a problem)
- Duck typing over structure (dataclasses imply structure)

**Staff insight:** Dataclasses aren't a replacement for all classes — they're for data-focused classes. Use them for configuration, API responses, value objects. Don't shoehorn behavior-heavy classes into dataclasses.

### The GIL and Concurrency

Python's Global Interpreter Lock (GIL) prevents true parallelism for CPU-bound tasks within a single process.

**What the GIL means:**
- Only one thread executes Python bytecode at a time
- Threads help with I/O-bound tasks (release GIL during I/O)
- Threads don't help with CPU-bound tasks (GIL is bottleneck)

**Working around the GIL:**
- multiprocessing for CPU-bound parallelism (separate processes)
- NumPy/Cython release GIL for numerical computation
- async/await for I/O concurrency (not parallelism)

**Staff insight:** The GIL isn't Python's flaw — it's a design choice that simplifies the interpreter and C extension integration. For CPU-bound work, use multiprocessing or drop to native code. For I/O-bound work, threads or async suffice.

### Modern Python Features (3.10+)

**Pattern matching (3.10):**
- Match statements for structural pattern matching
- Good for parsing, dispatching on types/structures
- Don't overuse (if/elif often clearer for simple cases)

**Union types with `|` (3.10):**
- `int | None` instead of `Optional[int]`
- Cleaner type hint syntax

**Structural pattern matching trade-offs:**
- More expressive than if/elif chains for complex cases
- Overkill for simple type checking
- Pattern matching is not switch/case (more powerful)

**Staff insight:** Modern features are nice but not necessary. Use them where they improve clarity. Don't rewrite code just to use new syntax.

<common_pitfalls>
## Common Pitfalls and Anti-Patterns

### Late Binding in Closures

Closures capture variables by reference, not value. This trips up loop-generated functions.

**The problem:**
```python
funcs = [lambda: i for i in range(3)]
[f() for f in funcs]  # [2, 2, 2] - all see final 'i'
```

**The fix (default argument):**
```python
funcs = [lambda i=i: i for i in range(3)]
[f() for f in funcs]  # [0, 1, 2]
```

**Staff insight:** This is Python's scoping behavior. Closures bind variables, not values. Use default arguments to capture values, or use partial application from functools.

### Comparing to True/False/None

Use truthiness checks, not explicit comparisons.

**Unpythonic:**
```python
if x == True:
if len(items) == 0:
if x == None:
```

**Pythonic:**
```python
if x:
if not items:
if x is None:
```

**Exception:** Use `is` for singletons (None, True, False). Use `==` for value comparison.

**Staff insight:** Python's truthiness is powerful. Empty containers, zero, None, False are all falsy. Use it. But be explicit when checking for None specifically (use `is None`, not just `not x`).

### Lambda Assignment

Don't assign lambdas to variables — use `def` instead.

**Unpythonic:**
```python
add = lambda x, y: x + y
```

**Pythonic:**
```python
def add(x, y):
    return x + y
```

**Why:** Lambdas are for anonymous functions passed as arguments. Named functions get better tracebacks and documentation.

**Staff insight:** Linters flag this (PEP 8 E731). Use lambdas inline, not assigned. If it needs a name, use def.

### Global Statement Abuse

Avoid `global` except in rare cases. It makes code hard to reason about.

**When global is acceptable:**
- Module-level configuration (though classes or functions are better)
- Caching/memoization (use `functools.lru_cache` instead)
- Truly global state (rare)

**Better alternatives:**
- Pass parameters explicitly
- Use classes to encapsulate state
- Return values instead of modifying globals

**Staff insight:** Global state is a code smell in any language. Python doesn't forbid it, but avoid it. Explicit is better than implicit.
</common_pitfalls>

<safety_constraints>
## Safety Constraints

- **NEVER** use mutable default arguments (lists, dicts, sets) without the `None` sentinel pattern
- **NEVER** assign lambdas to variables—use `def` for named functions
- **NEVER** use `global` for shared state—use classes or explicit parameter passing
- **NEVER** catch bare `Exception` and swallow errors silently
- **NEVER** use `eval()` or `exec()` on untrusted input
- **ALWAYS** use context managers (`with`) for file handles, locks, and database connections
- **ALWAYS** use parameterized queries—never string concatenation for SQL
- **ALWAYS** validate and sanitize untrusted input at system boundaries
</safety_constraints>

<related_skills>
## Related Skills

- **software-engineer** — Core engineering philosophy, system design principles
- **functional-programmer** — When functional approaches are clearer
- **test-driven-development** — Testing philosophy and TDD principles
</related_skills>

<resources>
## Resources

**Official Documentation:**
- Python Documentation: https://docs.python.org/3/
- PEP Index: https://peps.python.org/
- PEP 8 Style Guide: https://peps.python.org/pep-0008/
- PEP 484 Type Hints: https://peps.python.org/pep-0484/

**Tooling:**
- MyPy Documentation: https://mypy.readthedocs.io/
- pytest Documentation: https://docs.pytest.org/
- Black Documentation: https://black.readthedocs.io/
- Hatch Documentation: https://hatch.pypa.io/

**Style Guides:**
- Google Python Style Guide: https://google.github.io/styleguide/pyguide.html
</resources>

## Summary

Python programming emphasizes:
- **Readability and explicitness** — Code is read more than written
- **Type hints everywhere** — Essential for code quality and LLM-assisted development
- **Comprehensive Sphinx documentation** — Mandatory for all production code
- **Modern tooling** — Hatch+UV for project management, Black/Bandit/Flake8/MyPy for quality
- **EAFP over LBYL** — Try and catch exceptions rather than checking first
- **Duck typing** — Accept behavior, not types
- **Pythonic idioms** — Comprehensions, context managers, iterators
- **Pragmatism over purity** — Python isn't purely functional or OO

Apply Python where it excels (scripting, prototyping, data processing, web APIs) and use other languages where it struggles (performance-critical, mobile, systems programming). **All new projects must use Hatch+UV, with Black, Bandit, Flake8, and MyPy enabled in CI/CD.** Type hints and Sphinx documentation are mandatory for all production code (exceptions: throwaway scripts). Choose pytest over unittest, understand async/await limitations, and avoid anti-patterns from other language backgrounds. Success in Python comes from embracing its philosophy: readable, explicit, well-documented, well-tooled code.
