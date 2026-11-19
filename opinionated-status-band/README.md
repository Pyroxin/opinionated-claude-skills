# opinionated-status-band

A mod that draws a Powerline-style status row above the Claude Code prompt. Deciding when to compact, pause, or resume a long session takes knowing how full the context window is, how close the account is to its rate limits, and how long the conversation has sat idle, and the stock interface shows these in separate places or only on request. The band puts them in one row.

A mod is a plugin component written as code: a hooks module that Claude Code loads into a session, where it can draw in the interface and intercept the session's events. Claude Code accepts one hooks module per plugin and gives each plugin one row above the prompt, so each mod in this marketplace is a plugin of its own. Mods are an early-access plugin component, so the API this one is written against may change between Claude Code releases.

## What the band shows

The band shows a context gauge with the tokens used and the percentage left before auto-compaction, the model and reasoning effort, the project and git branch, how long the current turn has run or how long ago the last one ended, rate-limit usage with reset times, and the session's cost and turn count. When the terminal is narrow, segments are removed in a fixed order and the context gauge is kept.

The band draws in the Claude Code terminal only; Claude Code's desktop and mobile surfaces show nothing for it, because the row is built from character cells and Powerline glyphs.

The colors are fixed, based on the same Adwaita-inspired colors as the `adwaita-inspired-light` theme in `opinionated-themes`, with light gray blocks and dark text. Each block sets its own background and text, so the band is legible on light and dark terminal backgrounds but does not follow the session's theme.

## How the context gauge counts

The gauge updates after every model response, including during a long turn, and changes color when half the context is left and again when 15% is left.

The gauge counts what responses have reported as used and doesn't predict what the next request will add. The notices of `opinionated-context-management` do add that prediction, so one can arrive slightly before the gauge reaches its threshold.

A response in which Anthropic's API ran a tool itself (e.g., the advisor) reports its usage summed over the several requests Claude Code made, so the gauge adds what that response generated to the figure it already showed and doesn't show the sum; the next response made by one request reports the size exactly.

## Font requirement

The terminal has to be able to draw the Powerline symbols, which it can when its font includes them. The band uses three: the two segment separators (U+E0B0 and U+E0B2) and the branch glyph (U+E0A0). They are in Unicode's Private Use Area, so a font has them only if it was made or patched to include them. Without them the separators typically draw as empty boxes or question marks, while the text stays readable.

If the terminal's font lacks them, [DejaVu Sans Mono for Powerline](https://github.com/powerline/fonts) is the suggested font to install; any other Powerline-patched font, or a [Nerd Font](https://www.nerdfonts.com/), also supplies them. Set it as the terminal's font, or as its fallback font for non-ASCII characters where the terminal has that setting.
