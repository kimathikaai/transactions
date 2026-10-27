# transactions

View your finances. A personal finance dashboard for macOS built with SwiftUI and Swift Charts.
It reads your bank's CSV exports, categorizes transactions with editable regex rules, and shows
net worth, monthly cash flow, savings rate, spending by category, and savings goals ("reserves").

Everything stays local: data lives in plain JSON and CSV files on disk. No accounts, no network,
no external dependencies.

## Requirements

- macOS 26.3+
- Xcode 26+

## Build and run

```bash
open transactions-ui.xcodeproj   # then Cmd+R

# or from the command line
xcodebuild -scheme transactions-ui -destination 'platform=macOS' build
xcodebuild test -scheme transactions-ui -destination 'platform=macOS'
```

## Data profiles

The app reads from `transactions-ui/Data/<profile>/`:

| Profile | Folder | Tracked in git |
|---------|--------|----------------|
| Demo | `Data/demo/` | Yes. Synthetic sample data |
| Real | `Data/real/` | **No.** Gitignored, for your own data |

A fresh clone opens on the **demo** profile. Once `Data/real/` exists, it becomes the default.
You can switch profiles at any time from the **Developer** page in the sidebar.

> **Note:** DEBUG builds read and write these folders directly in the source tree (located via
> `#filePath`), so your edits land next to the code. Release builds are not supported yet.

## Using your own data

1. On the **Developer** page, switch to the **Real** profile. The app starts empty, and `Data/real/` is
   created on the first save.
2. Optional: copy `Data/demo/categories.json` into `Data/real/` to start from the sample category
   catalog instead of an empty one.
3. On the Accounts page, add an account and upload its CSV export.

Want version control for your data? `Data/real/` can be its own (private!) git repository. The
parent repo ignores it.

### CSV format

Four columns, with an optional header row:

```
Date,Details,Debit,Credit
2026-01-15,PAYROLL DEPOSIT GLOBEX CORP,,2600.00
2026-01-16,SOBEYS,36.20,
```

- `Date` is `YYYY-MM-DD`
- `Debit` is money out, `Credit` is money in (leave the other one empty)

This matches CIBC's headerless export. Other banks may need their columns rearranged first.
Uploading new exports supports both *overwrite* and *append* (append only adds rows it hasn't
seen yet).

## Categories

Categories are editable in the Categories panel. Each one holds a list of case-insensitive regex
patterns matched against a transaction's `Details`. Transfers between your own accounts are
detected by keyword (`transactions-ui/Services/GeneratedConfig.swift`).

## License

[MIT](LICENSE)
