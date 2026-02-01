# WealthPlanner

A native iOS app for personal wealth management built with SwiftUI and SwiftData.

## Features

- **Dashboard**: Net worth overview, asset allocation charts, and account summaries
- **Accounts Management**: Track checking, savings, investment, crypto, credit, and loan accounts
- **Investment Tracking**: Monitor holdings with real-time prices, gains/losses, and performance charts
- **Budget Tracking**: Set monthly budgets by category and track spending
- **Financial Goals**: Create savings goals, track progress, and use the retirement calculator
- **Bank Connection**: Connect to financial institutions via Plaid to automatically sync accounts, transactions, and holdings
- **File Import/Export**: Import CSV, OFX, QFX, and QIF files; export data as CSV, JSON, or PDF

## Requirements

- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/WealthPlanner.git
   cd WealthPlanner
   ```

2. Open the project in Xcode:
   ```bash
   open WealthPlanner.xcodeproj
   ```

3. Select a simulator or connected device and run (Cmd+R)

## Sample Data

The app automatically loads sample data on first launch, including:
- 6 sample accounts (checking, savings, investment, crypto, credit card, mortgage)
- Investment holdings (AAPL, GOOGL, MSFT, VTI, BND, BTC, ETH)
- Sample transactions
- Budget categories
- Financial goals

You can also import sample files from the Import screen to test the CSV import functionality.

## Architecture

The app uses MVVM + Repository pattern:

```
Views (SwiftUI) → ViewModels → Repositories → SwiftData
                                    ↓
                              Plaid SDK / File Parsers
```

### Project Structure

```
WealthPlanner/
├── App/
│   └── WealthPlannerApp.swift
├── Models/
│   ├── Account.swift
│   ├── Holding.swift
│   ├── Transaction.swift
│   ├── Goal.swift
│   └── Budget.swift
├── Views/
│   ├── Dashboard/
│   ├── Accounts/
│   ├── Investments/
│   ├── Budget/
│   ├── Goals/
│   ├── Import/
│   └── Settings/
├── ViewModels/
├── Repositories/
├── Services/
│   ├── PlaidService.swift       # Plaid API integration
│   ├── PlaidSyncService.swift   # Sync connected accounts
│   ├── PriceService.swift       # Stock/crypto price updates
│   ├── ImportService.swift      # File import orchestration
│   ├── ExportService.swift      # Data export
│   └── SampleDataService.swift  # Sample data loader
├── Utilities/
│   ├── CSVParser.swift          # CSV import with auto-detection
│   ├── OFXParser.swift          # OFX/QFX file parsing
│   └── Keychain.swift           # Secure token storage
└── Resources/
    ├── Assets.xcassets
    ├── Info.plist
    └── SampleData/
```

## Key Features Explained

### Auto-Detect CSV Import

The app automatically detects:
- Column mappings (date, description, amount, symbol, quantity, etc.)
- Date formats (14 common formats supported)
- Data type (transactions vs holdings)

No manual column mapping required - just select a file and import.

### Plaid Integration

Connect to banks and financial institutions to automatically sync:
- Account balances
- Transactions (last 30 days)
- Investment holdings

Note: Production Plaid integration requires a backend server for secure token exchange. The current implementation uses Plaid Sandbox mode for development.

### Data Privacy

All data is stored locally on-device using SwiftData. No data leaves your device except for:
- Plaid API calls (when connecting banks)
- Stock price API calls (for holdings price updates)

## Screenshots

The app includes:
- Dashboard with net worth and asset allocation
- Accounts list with balances and sync status
- Investment portfolio with holdings and performance
- Budget tracking with category breakdown
- Goals with progress tracking

## License

MIT License
