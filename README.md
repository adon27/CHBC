# Office of Examinations — Back Office

A back-office application for managing the events shown in
`Events_Office of Examinations.html` — the CHRIST (Deemed to be University),
Lavasa Campus "Important Dates" email template — without hand-editing HTML.

## 0. Why this is a browser-only app (read this first)

This was built on a machine with **no Node.js, Python, PHP, or Docker
installed**. There was no way to install, run, or test a conventional
server + database backend on this machine. Rather than hand you an untested
Express/SQL codebase, this is a **self-contained browser application**:

- **No install, no build step, no server required.** Open `index.html` (or
  run `serve.ps1` — see below) and it works.
- **Data persistence**: browser **IndexedDB**, with an automatic
  **localStorage** fallback if IndexedDB is unavailable in your browser
  context. Everything lives in *your browser*, scoped to wherever you open
  the app from (see "Deployment" below for why that matters).
- **This is a real, honest architectural tradeoff**, not a toy demo: every
  requirement from the spec that doesn't strictly require a server (CRUD,
  month/year management, the template engine, integrity checking, audit
  logging, versioning, validation, tests) is fully implemented. The
  requirements that *do* assume a server (session cookies, CSRF tokens,
  server-side SQL) are replaced with the closest honest browser-native
  equivalent — see [Security model](#4-security-model) for exactly what that
  means and does *not* mean.
- If Node.js later becomes available (on this machine or a deployment
  server), see [Path to a server backend](#10-path-to-a-server-backend) for
  how this design carries over.

## 1. Quick start

1. Open `index.html` directly in a modern browser (Chrome/Edge), **or**, if
   your browser restricts storage under `file://`, run the bundled
   zero-install server:
   ```powershell
   powershell -ExecutionPolicy Bypass -File serve.ps1
   ```
   then open `http://localhost:8899/`.
2. On first run there are no admin accounts — you'll be asked to create one
   (username + password, min. 8 characters).
3. The original **August 2026** dataset (all 13 events from the supplied
   master template) is imported automatically on first run, marked
   `published`, so you immediately have real data to explore.

## 2. Architecture — three layers, kept separate

```
Layer 1: Back Office UI          assets/ui.js, assets/app.js, styles.css
              |
Layer 2: Event Data              assets/data.js, assets/db.js  (IndexedDB/localStorage)
              |
Layer 3: Public HTML Template    assets/master-template.js (verbatim embed)
              |                  assets/templateEngine.js  (the ONLY code that
              v                   writes public HTML)
       Generated public HTML
```

The admin UI never assembles public HTML by hand. `templateEngine.js` is the
single choke point that produces it, and it works by **cloning real DOM
nodes harvested from the master template**, not by string-templating
hand-written markup that merely *looks* similar. See
[The template engine](#5-the-template-engine-how-fidelity-is-guaranteed).

## 3. Data model

**Event**
| Field | Type | Notes |
|---|---|---|
| `id` | string | generated |
| `monthId` | string | `"YYYY-MM"`, foreign key to Month |
| `startDate` | `YYYY-MM-DD` | required |
| `endDate` | `YYYY-MM-DD` | required only if `isDateRange` |
| `isDateRange` | boolean | |
| `category` | string | one of the 7 built-in categories, or an admin-added one |
| `title` | string | max 300 chars |
| `sortOrder` | integer | tiebreaker / manual-order key |
| `createdAt` / `updatedAt` | ISO datetime | |

`displayDate` / `displayMonth` / `displayMonthRange` are **never stored** —
they are always *computed* from `startDate`/`endDate`/`isDateRange` by
`assets/dateFormat.js`, exactly per spec section 4 ("the administrator must
NOT have to manually type the formatted display string").

**Month**
`id` (`YYYY-MM`), `year`, `month`, `status` (`draft`|`published`),
`orderMode` (`chronological`|`manual`), `createdAt`, `updatedAt`,
`publishedAt`, `lastGeneratedAt`.

Months are independent, permanent records — selecting a different month
never touches another month's events (spec section 17).

## 4. Security model

Being direct about what this does and doesn't provide, since the original
spec assumes a server:

| Spec ask | What's implemented | Honest caveat |
|---|---|---|
| Authentication | Username/password gate, PBKDF2-SHA256 (150k iterations, random salt per user) via Web Crypto | This is *client-side* access control. Anyone with file access to the browser profile's IndexedDB, or to the source, is not blocked by a server. It stops casual/accidental editing, not a determined local attacker. |
| Sessions | `sessionStorage`-backed session, 30-min idle timeout | Not a server session; clears when the tab closes. |
| CSRF | N/A | There is no server request to forge — all writes are local IndexedDB transactions. |
| Rate limiting | 5 failed logins -> 5-minute lockout per username, tracked in `sessionStorage` | Client-side only; a new tab/session resets it. Documented, not hidden. |
| SQL injection | N/A — no SQL | |
| XSS / output escaping | **Enforced twice**: (1) event text only ever reaches the public HTML via `Node.textContent`, never `innerHTML`, so `<script>`/`onerror=` payloads are inert by construction; (2) the admin UI itself escapes all user text before any `innerHTML` use. Covered by an automated test (`tests.js`: "generated event content is HTML-escaped"). | |
| Audit logging | Full append-only log: every create/update/delete/duplicate/reorder/generate/publish/login/login\_failed/template\_integrity\_block, with user, timestamp, before/after | |
| Password handling | PBKDF2 (never plaintext, never reversible), salted per-account | |
| Protection against arbitrary template modification | SHA-256 checksum of the embedded master template, verified before every generation; independent structural re-verification of every generated card row (see below) | |

If/when this runs behind a real server, swap `assets/auth.js` and
`assets/db.js` for server-backed equivalents — `templateEngine.js`,
`dateFormat.js`, and `validation.js` are pure/DOM-only and need no changes.

## 5. The template engine — how fidelity is guaranteed

`assets/templateEngine.js` never writes public-facing HTML as a string
template. Instead, on every `generate()` call it:

1. **Verifies** `assets/master-template.js`'s embedded string against a
   hardcoded SHA-256 checksum. Mismatch -> generation blocked immediately,
   before touching anything else.
2. **Re-parses the pristine master template from scratch** (never a
   previously-mutated tree) and harvests real DOM nodes from it: the
   heading's `<span>`, one event-card `<tr>`, the leading/trailing spacer
   rows, and even the original document's whitespace text nodes between
   rows (the source HTML is hand-indented — dropping those would be a real,
   detectable structural diff, not a cosmetic one).
3. **Clones** the harvested card row once per event and sets *only*:
   `.dnum` class+style+text, `.dmon` style+text, `.badge` text, `.title`
   text, and the card wrapper's `padding` (the *only* two padding variants
   that exist in the master: normal, and zero-bottom for whichever card
   ends up last). Nothing else on the row is ever touched.
4. Serializes the result, then **independently re-parses that serialized
   string** (not the live tree that built it) and re-verifies:
   - everything outside the heading text and the events region is
     byte-identical to the master (hero, logo, gold rule, footer, social
     links, signature, "Please Note", all inline CSS, all MSO conditional
     comments);
   - every card row's dynamic slots hold one of the *known-good* variants
     (never an arbitrary value);
   - resetting those slots back to the master's own values makes the row
     byte-identical to the master's card — proving nothing else on the row
     drifted.
5. Only if **all** of the above hold does `generate()` return `{ok:true,
   html}`. Any failure returns `{ok:false, blocked:true, errors:[...]}`
   with a specific message per problem — the UI renders this as a red
   **"TEMPLATE INTEGRITY ERROR"** panel and refuses to show a preview or
   enable Download/Publish. Nothing is ever silently "fixed."

This is exercised by `tests.js`, including a test that deliberately corrupts
the in-memory master template and asserts generation is blocked.

### Regression proof

The test suite regenerates **August 2026 from the original 13-event seed
data** and diffs it character-for-character against the real master file.
The only accepted differences are two well-known, unavoidable HTML
serialization conventions (see next section) — anything else fails the
test. This is the strongest fidelity guarantee available without a
byte-for-byte file diff tool, and it currently passes.

### Two accepted "harmless serialization differences"

The spec explicitly allows harmless, unavoidable serialization differences
(section 34/35). There are exactly two, both consequences of how browsers
serialize DOM (not choices made by this app's code):

1. **Void elements**: the master file writes `<img ... />` (XHTML style);
   a browser's native `outerHTML` always serializes void elements as
   `<img ...>`, without the slash. Cosmetic only — renders identically.
2. **Trailing newline**: the master *file* ends with a newline after
   `</table>`; `outerHTML` only ever serializes the element itself, never a
   file-level trailing newline that was a sibling of it, not part of it.

Neither affects DOM structure, rendering, or email-client compatibility.

### One important, deliberate technical note: line endings

The master file on disk uses CRLF line endings. The ECMAScript spec
normalizes CRLF -> LF when computing a template literal's string value, so
the in-browser copy of the master (and therefore all generated output) uses
LF only. This is standard, unavoidable browser behavior, not a choice this
app makes — and since it happens identically to both "sides" of every
comparison this app performs, it never causes a false pass or false
negative in the integrity checks.

### A deliberate, tracked exception: title alignment

Every rule above is about proving the generator *never* deviates from the
master's typography. Title alignment is the one deliberate exception, added
after explicit confirmation that it should be a real, permanent expansion
of what's allowed to vary — not a bug fix. Each event now carries an
optional `textAlign` field (`left` | `right` | `center` | `justify`, in
the Add/Edit form under "Title alignment").

The important part is how it stays consistent with everything above it:

- **`left` (or no value at all) produces a `.title` style attribute
  byte-identical to the untouched master.** The master's `.title` cell has
  no `text-align` property to begin with — browsers left-align by default —
  so the default case introduces zero drift. This is what keeps the
  August-2026 regression test passing unchanged.
- The other three **append** `text-align:right/center/justify;` to the
  master's own harvested style string — never replace it, never touch any
  other property on that cell.
- The integrity checker was updated alongside this: it now verifies a
  card's `.title` style is *exactly* the master's style plus one of those
  four known suffixes — nothing else. A test deliberately forges a
  `text-align:diagonal;` value into generated output and confirms the
  checker still blocks it, the same way it already blocks a tampered
  `.dnum`/`.dmon` variant.

**Design recommendation (not enforced by the app):** left is the only
option that doesn't visually fight the rest of the card, which is entirely
left-aligned (date, divider, month, badge). Right-aligning a multi-line
paragraph makes it hard to read (ragged left edge), center creates a
disconnected "zigzag" block, and justify tends to produce uneven
word-spacing gaps — especially on these titles, which wrap often due to
hyphenated codes (`BSc-CSDS`, `MA-EDH`, etc.). Left remains the default for
every new event; the others are there if a specific one-off case calls for
them.

### Tidy line wrapping (`assets/textFormatting.js`)

A second, smaller fit-and-finish helper, also opt-in from the Add/Edit
form's title field ("Tidy line wrapping" button) — and also a pure text
substitution, never a structure/CSS change. It fixes two specific awkward
wraps that show up often in this university's real titles:

- A parenthetical group splitting mid-bracket — e.g. `(I, III, V, VII, IX)`
  breaking after `(I,` with the rest of the group continuing on the next
  line. Fixed by replacing the spaces *inside* every `(...)` group with
  non-breaking spaces (U+00A0), so the whole group wraps as one atomic
  unit: it either fits on the line whole, or the entire group moves down
  together — it's never split internally.
- A short hyphenated code splitting across lines — e.g. `BSc-CSDS` breaking
  into `BSc-` / `CSDS`. Fixed by replacing that specific hyphen with a
  non-breaking hyphen (U+2011). A numeric range like `24-27` and a spaced
  dash used as punctuation (`" - Lavasa Campus"`) are deliberately left
  alone — both should stay naturally breakable.

Both are invisible, reversible character swaps (no words change, nothing
is added or removed) — click the button, review the live preview, then
Cancel or Save like any other edit. Internally the two non-breaking
characters are built via `String.fromCharCode()` rather than pasted as
literal characters or `\uXXXX` escapes in the source: both of those render
identically to an ordinary space/hyphen in an editor, which made an
earlier draft of this file silently no-op after a routine edit flattened
the character without any visible diff. A numeric char code can't be
silently flattened that way.

## 6. Date formatting rules (computed, never hand-typed)

| Input | Output | Card style |
|---|---|---|
| Single day `2026-08-07` | `07` / `AUG` | `dnum` 50px, `dmon` normal |
| Same-month range `2026-08-24 → 2026-08-27` | `24-27` / `AUG` | `dnum dnum-r` 34px, `dmon` normal |
| Cross-month range `2026-08-31 → 2026-09-04` | `31-4` / `AUG-SEP` | `dnum dnum-r` 34px, `dmon` condensed (smaller, tighter letter-spacing, matching the master's own `31-4`/`AUG-SEP` card) |
| Cross-year range `2026-12-30 → 2027-01-03` | `30-3` / `DEC-JAN` | same as cross-month — the card has no room to show a year, matching the template's own design language |

Range day numbers are shown as plain numbers (`31-4`, not `31-04`) —
matching the one example the master template itself contains. Single-day
numbers are always zero-padded (`07`) — also matching the master.

## 7. Feature walkthrough

- **Dashboard** — selected month stats (event count, upcoming count,
  categories in use, status, last updated), template integrity badge,
  quick links.
- **Event Manager** — table of Date / Category / Title / Actions
  (Edit, Duplicate, Delete, ↑/↓), search/filter, "Sort chronologically",
  "+ Add Event". Reordering with ↑/↓ switches the month to `manual` order
  mode (its `sortOrder` values now win); "Sort chronologically" switches it
  back and recomputes `sortOrder` to match date order.
- **Add/Edit Event** — Single Day / Date Range radio, real `<input
  type=date>` pickers, category dropdown (+ inline "add a new category"),
  title textarea, and a **live preview** that renders the event through the
  *real* template engine (`TemplateEngine.previewCard`) — not a hand-drawn
  approximation.
- **Bulk Import** (Event Manager → "Bulk Import") — select a range of cells
  in Excel and paste into the textarea. A header row is auto-detected.
  Nothing is saved until you review a preview table and click **Import**.
  Three column layouts are supported, auto-detected by column count:
  - `Start Date | End Date | Category | Title` (End Date blank for
    single-day events).
  - `Start Date | Category | Title` — no End Date column, every row treated
    as a single day.
  - `Date(s) | Title` — no Category column at all (real data often looks
    like this: a two-column "Dates" / "Event details" list with no explicit
    category or year). Each row's category is **auto-detected from its
    title** (see "Category auto-suggestion" below). If a title can't be
    confidently matched, Parse stops short of the normal preview and shows
    a **"N event(s) need a category"** resolution step instead — a
    dropdown per unresolved row, a "set all remaining to…" quick-fill for
    when several genuinely share one category, and a "Skip" per row to
    leave it out. Import stays unreachable until every flagged row is
    either resolved or explicitly skipped. There is no default/fallback
    category applied automatically to anything — every category on every
    row is either auto-detected with a keyword the preview shows you, or a
    choice you made yourself in that dialog. The `Date(s)` cell can hold a
    single date *or* a whole range written as free text — `24-27 August`,
    `24th- 27th August`, `31st August to 4th September`, or even a range
    crossing years like `12 August - 15 January` (correctly rolls into the
    following year) all parse correctly.

  Dates accept `2026-08-07`, `07-Aug-2026`/`Aug 7, 2026`, `07/08/2026`, an
  Excel date serial number (what a "General"-formatted date cell pastes
  as), or a year-less form like `7th August`/`7 August` — ordinal suffixes
  (`7th`, `21st`, `24th`) are stripped automatically, and the year is
  inferred from whichever month/year is currently selected.

  **A cell containing a manual line break is handled correctly.** Excel
  wraps a cell in double quotes on copy whenever it contains one (Alt+Enter
  inside the cell) — for plain tab-separated clipboard data too, not just
  `.csv` files. The parser walks the whole pasted block character-by-
  character rather than splitting on every newline up front, so a newline
  *inside* an open quote is treated as part of that cell's content
  (collapsed to a single space) instead of a bogus extra row, and a doubled
  quote (`""`) inside a quoted cell is unescaped to a literal `"`.

  Nothing is ever silently guessed and hidden:
  - `DD/MM/YYYY`-style numeric dates are genuinely ambiguous when both
    parts are ≤12 — the parser assumes `DD/MM` and flags every such row
    with an "assumed DD/MM — verify" note in the preview.
  - A category not already in the list is shown as "new category — will be
    created" and summarized up top; nothing is auto-created until Import is
    clicked.
  - Rows that fail to parse (bad date, empty title, wrong column count,
    etc.) are shown in red with the specific reason and are excluded from
    the import count — they never fail silently or block the valid rows
    around them.

  See `assets/bulkImport.js` — pure parsing logic, no DOM/DB dependency,
  covered by its own tests in `tests.js`, including a regression test built
  from a real admin's actual pasted data (2-column, ordinal dates, both
  range styles, no category).
- **Category auto-suggestion** (`assets/categoryInference.js`) — a
  rule-based (not ML) matcher that scores an event's title text against
  every known category (built-in and admin-added) and suggests the
  highest-confidence match. It's used in two places:
  - **Bulk Import's `Date(s) | Title` layout** — the primary use case,
    since that data has no Category column at all. Verified against the
    real 13-event August 2026 dataset: every single row auto-detects to its
    actual historical category (`Deadline`, `Submission`, `Portal Opens`,
    `Application Opens`, `Application Closes`, `Orientation`,
    `Examination`) — see the regression test in `tests.js`. When a title
    genuinely can't be matched (e.g. "PRAPM Reports" with the word
    "Submission" dropped), that row is never assigned anything — it's
    handed to the resolution dialog described above for an explicit choice.
  - **The single Add/Edit Event form** — as you type a title, a
    "Suggested category: X — Use" chip appears next to the dropdown *only*
    when the suggestion differs from what's currently selected. It never
    changes the dropdown on its own; you click "Use" to accept it.

  How it decides: domain-tuned keyword rules (`deadline`, `submission`,
  `marks` as a secondary Submission signal, `portal`, `application
  opens/closes`, `orientation`, `exam`/`mte`/`mse`, a low-weight `cia`)
  tuned against this template's actual terminology, plus a generic rule
  that matches a category's own name (or a significant word from a
  multi-word custom category, at lower confidence) appearing in the title.
  The `marks` signal exists specifically because a title can legitimately
  name several exam acronyms (`CIA`/`MTE`/`MSE`) while still being about
  *submitting* something — e.g. "CIA 2/MTE/MSE Marks Submission" — and
  without it, three stacked exam-acronym hits could outweigh a single
  `submission` match and misclassify the row as `Examination`. **It never
  guesses**: a title matching two categories equally (a genuine tie) or
  matching nothing returns no suggestion at all, rather than picking
  arbitrarily — see the dedicated tie/no-match tests. This is a heuristic
  tuned for this university's terminology, not a general-purpose
  classifier — always glance at the preview/chip before trusting it, the
  same as every other auto-detected value in this app.
- **Preview & Generate** — "Generate HTML" runs the full integrity-checked
  pipeline and renders the actual generated HTML in an iframe (what you see
  is exactly what gets downloaded). "Download HTML" saves it as a
  standalone file. "Publish" marks the month `published` and snapshots a
  version.
- **Audit Log** — every administrative action, who/what/when, with
  before/after values available.
- **Admin & Settings** — manage admin accounts, change your password,
  manage categories (built-in 7 are permanent; more can be added, never
  removed), export/import a full JSON backup of the entire database.
- **Test Suite** — runs the full automated test suite (see below) in-browser
  with a pass/fail report.

## 8. Backup & version history

- Every successful **Generate** and **Publish** snapshots the month's event
  list (and the generated HTML, for Publish) into a `versions` store —
  nothing is lost by continuing to edit after generating.
- **Admin & Settings -> Export full backup** downloads the entire database
  (all months, events, versions, audit log, categories — not admin password
  hashes' plaintext, obviously) as JSON. **Import backup** merges a
  previously exported file back in. Because everything lives in browser
  storage local to wherever you opened the app from, **export regularly** —
  this is the one manual step a real server would otherwise handle for you.

## 9. Testing

Open the **Test Suite** tab and click **Run all tests**, or from the
console: `AdminTests.runAll().then(console.log)`. There is no Node.js test
runner available in this environment, so this is a small in-browser
assertion runner (see `assets/tests.js`) — but it covers real behavior, not
mocks:

- Date formatting: single day, same-month range, cross-month range,
  cross-year range, invalid-range rejection.
- Validation: empty title, unknown category, missing end date, invalid
  month/year.
- Data CRUD: create/update/duplicate/delete round-trip, manual reorder
  (against a disposable scratch month — your real data is never touched).
- Template integrity: checksum match, **generation blocked when the master
  template is tampered with**, generation blocked on invalid events.
- **Regression**: generating August 2026 from the seed data reproduces the
  master template (see above).
- Card count correctness, HTML-escaping of injected markup.

All 64 tests pass as shipped (includes bulk-import parsing: header
detection across all 3 column layouts, all supported date formats
(including ordinal/year-less dates, malformed ordinals like "17 th", and
free-text ranges — same-month, cross-month, and cross-*year*, e.g.
"12 August - 15 January" correctly rolling into the next year), quoted
multi-line cells (an embedded line break collapses to a space instead of
splitting into a bogus extra row; a doubled `""` unescapes to a literal
quote), the ambiguous-DD/MM assumption note, needsCategory/resolution-step
behavior, column-count mismatches, the missing-year guard for the
2-column layout, and end-to-end pasted-rows-through-`generate()` checks —
three of them built from real admin pastes; category auto-suggestion:
exact reproduction of all 13 original events' real historical categories,
tie/no-match handling, custom-category word matching, and the
marks-vs-exam-acronym weighting fix; title alignment: byte-identical
default output, all three non-default variants, validation, a
mixed-alignment month generating cleanly, and a forged alignment value
still being blocked by the integrity checker; and tidy-line-wrapping:
parenthetical/hyphenated-code protection, numeric ranges and punctuation
dashes correctly left alone, and a real reported title pushed end-to-end
through `generate()` to confirm the non-breaking characters survive
serialization intact.

## 10. Path to a server backend

If Node.js (or any server runtime) becomes available later, this design
carries over directly:

- `assets/dateFormat.js`, `assets/validation.js`, and the *logic* inside
  `assets/templateEngine.js` are pure/DOM-only — portable as-is to a
  server-side DOM library (e.g. `jsdom` + Node) with no behavioral changes.
- Replace `assets/db.js` with real API calls to a database-backed service;
  replace `assets/auth.js` with real server sessions + CSRF. `assets/ui.js`
  only talks to `Data`/`Auth`/`Audit`, so the UI layer barely changes.
- The integrity-checking approach (checksum + structural re-verification of
  independently-parsed output) is equally valid server-side.

## 11. File manifest

```
admin/
  index.html                     Admin app shell
  serve.ps1                      Optional zero-install local server (PowerShell/.NET only)
  README.md                      This file
  original-template/
    Events_Office of Examinations.html   Untouched copy of the supplied master template
  assets/
    master-template.js           Verbatim embed of the master template (checksummed)
    dateFormat.js                Pure date -> display-string logic
    validation.js                Event / month-year validation
    categoryInference.js         Title -> suggested category (pure, no DOM/DB)
    bulkImport.js                Paste-from-Excel parsing (pure, no DOM/DB)
    textFormatting.js            Non-breaking space/hyphen line-wrap helpers (pure)
    crypto-utils.js              SHA-256 + PBKDF2 helpers (Web Crypto)
    db.js                        IndexedDB (localStorage-fallback) persistence layer
    data.js                      Months/Events/Versions/Settings services + August 2026 seed
    auth.js                      Login gate, sessions, lockout
    audit.js                     Append-only audit log
    templateEngine.js            THE template engine — the only code producing public HTML
    ui.js                        All admin screens
    tests.js                     In-browser automated test suite
    app.js                       Bootstrap
    styles.css                   Admin UI styling (independent of the public template's design)
```

## 12. Known limitations

- Client-side auth (see [Security model](#4-security-model)) — appropriate
  for a small trusted-admin tool, not for an internet-facing deployment
  without a real backend.
- Data is per-browser-profile. Opening the app from a different browser, a
  different machine, or an incognito window starts with an empty database
  (until you import a backup).
- No email-sending / distribution feature — this app produces the HTML
  file; sending it is outside its scope, matching the original file's own
  scope (it's a static template, not a mailer).
