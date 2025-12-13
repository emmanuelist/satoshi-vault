# SatoshiVault Protocol

**Advanced Bitcoin-collateralized lending infrastructure bridging Bitcoin's store-of-value properties with Stacks' smart contract capabilities**

## Overview

SatoshiVault represents the next evolution of Bitcoin DeFi, creating a trustless lending ecosystem where Bitcoin holders can unlock capital without selling their BTC exposure. Through sophisticated sBTC collateralization mechanics, users access STX liquidity while maintaining Bitcoin position integrity. The protocol features dynamic yield optimization, automated risk management, and capital-efficient liquidation systems designed specifically for Bitcoin's volatile yet appreciating asset characteristics.

**✨ Clarity 4 Upgrade**: This contract has been migrated to Clarity 4 (activated November 18, 2025 at Bitcoin block 923222) with enhanced security features including the new `as-contract?` function with explicit asset allowances.

## Key Features

- **sBTC Collateralized Lending**: Deposit sBTC as collateral to borrow STX
- **Liquidity Provision**: Earn competitive yields by providing STX liquidity
- **Dynamic Interest Accrual**: Real-time interest calculation and yield distribution
- **Risk Management**: Automated liquidation system with health factor monitoring
- **Capital Efficiency**: 70% Loan-to-Value ratio optimized for Bitcoin volatility
- **Emergency Controls**: Protocol pause/resume functionality for security

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    SatoshiVault Protocol                        │
├─────────────────────────────────────────────────────────────────┤
│  Lenders (STX)           Protocol Core           Borrowers      │
│      │                       │                      │          │
│      ▼                       ▼                      ▼          │
│ ┌─────────┐            ┌──────────┐            ┌─────────┐      │
│ │Liquidity│◄──────────►│ Interest │◄──────────►│Collateral│     │
│ │   Pool  │            │ Management│            │ Positions│     │
│ └─────────┘            └──────────┘            └─────────┘      │
│      │                       │                      │          │
│      ▼                       ▼                      ▼          │
│ ┌─────────┐            ┌──────────┐            ┌─────────┐      │
│ │  Yield  │            │ Oracle & │            │ Health  │      │
│ │Distribution│          │ Pricing  │            │Monitoring│     │
│ └─────────┘            └──────────┘            └─────────┘      │
└─────────────────────────────────────────────────────────────────┘
```

### Contract Architecture

The protocol consists of five main components:

1. **Price Oracle & Market Data**
   - sBTC/STX price feed management
   - Administrative price updates
   - Market rate validation

2. **Liquidity Provision System**
   - STX deposit/withdrawal functionality
   - Yield calculation and distribution
   - Lender position tracking

3. **Collateralized Borrowing**
   - sBTC collateral management
   - STX borrowing with LTV validation
   - Debt tracking with interest accrual

4. **Risk Management & Liquidation**
   - Position health monitoring
   - Automated liquidation triggers
   - Liquidator incentive system

5. **Protocol Administration**
   - Emergency pause/resume controls
   - Parameter governance
   - Global state management

### Data Structures

#### Global State Variables

```clarity
;; Aggregate protocol metrics
global-sbtc-collateral      ; Total sBTC locked as collateral
global-stx-liquidity        ; Total STX available for lending
global-stx-borrowed         ; Outstanding borrowed STX
interest-accrual-checkpoint ; Last interest calculation timestamp
lender-yield-accumulator    ; Accumulated yield index for rewards
sbtc-to-stx-exchange-rate  ; Current sBTC price in STX
protocol-operations-enabled ; Emergency pause state
```

#### User Position Maps

```clarity
;; Individual user tracking
borrower-collateral-ledger  ; sBTC collateral per user
lender-position-ledger      ; STX deposits and yield tracking
borrower-debt-ledger        ; Debt positions with interest
```

### Data Flow

#### Lending Flow

```
1. Lender deposits STX → provide-stx-liquidity()
2. Protocol updates global liquidity pool
3. Interest accrues from borrower payments
4. Yield distributed proportionally to lenders
5. Lender withdraws STX + yield → withdraw-stx-liquidity()
```

#### Borrowing Flow

```
1. User deposits sBTC collateral → open-collateralized-position()
2. Protocol validates LTV ratio (≤70%)
3. STX borrowed against collateral
4. Interest accrues on debt over time
5. User repays debt → repay-outstanding-debt()
6. Collateral released upon full repayment
```

#### Liquidation Flow

```
1. Position health degrades below threshold (80%)
2. Liquidator calls execute-liquidation()
3. Protocol validates liquidation conditions
4. Collateral seized, debt cleared
5. Liquidator receives bonus (10%)
```

## Protocol Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Max LTV** | 70% | Maximum loan-to-value ratio |
| **Interest Rate** | 10% APR | Annual borrowing cost |
| **Liquidation Threshold** | 80% | Health factor trigger |
| **Liquidation Bonus** | 10% | Liquidator incentive |
| **Base Price** | 50,000 STX | 1 sBTC baseline price |

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u100 | `ERR_INVALID_WITHDRAWAL` | Withdrawal amount exceeds balance |
| u101 | `ERR_BORROW_LIMIT_EXCEEDED` | Loan exceeds LTV limit |
| u102 | `ERR_POSITION_SAFE_FROM_LIQUIDATION` | Position healthy, cannot liquidate |
| u103 | `ERR_EXISTING_POSITION_CONFLICT` | Position already exists |
| u104 | `ERR_INSUFFICIENT_FUNDS` | Insufficient balance for operation |
| u105 | `ERR_ZERO_VALUE_OPERATION` | Zero amount not allowed |
| u106 | `ERR_PRICE_ORACLE_FAILURE` | Price feed unavailable |
| u107 | `ERR_EXTERNAL_CONTRACT_ERROR` | External contract failure |
| u108 | `ERR_UNAUTHORIZED_ACCESS` | Admin-only function |

## Public Functions

### Liquidity Provision

- `provide-stx-liquidity(amount)` - Deposit STX to earn yield
- `withdraw-stx-liquidity(amount)` - Withdraw STX plus earned interest

### Borrowing

- `open-collateralized-position(sbtc-amount, stx-amount)` - Deposit sBTC, borrow STX
- `repay-outstanding-debt(amount)` - Repay borrowed STX

### Administration

- `update-market-price(rate)` - Update sBTC/STX price (admin only)
- `emergency-pause-protocol()` - Pause all operations (admin only)
- `resume-protocol-operations()` - Resume operations (admin only)

### Liquidation

- `execute-liquidation(borrower)` - Liquidate unhealthy position

## Read-Only Functions

### User Queries

- `query-user-collateral(account)` - Get user's sBTC collateral
- `query-user-liquidity-deposits(account)` - Get user's STX deposits
- `query-user-borrowed-amount(account)` - Get user's debt amount
- `query-position-health-factor(account)` - Calculate position health

### Protocol Queries

- `query-protocol-analytics()` - Get comprehensive protocol metrics
- `fetch-sbtc-market-price()` - Get current sBTC price
- `compute-total-debt(borrower)` - Calculate debt with interest
- `calculate-earned-yield(lender)` - Calculate accrued yield

## Development

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) - Stacks development environment (Clarity 4 compatible)
- Node.js & npm - For testing framework

### Setup

```bash
# Clone repository
git clone <repository-url>
cd satoshi-vault

# Install dependencies
npm install

# Check contract syntax
clarinet check

# Run tests
npm test
```

### Clarity 4 Migration Notes

This contract has been upgraded from Clarity 1-3 to Clarity 4. Key changes include:

- **`as-contract?` Migration**: Replaced all `as-contract` calls with `as-contract?` which now requires explicit asset allowances
- **Asset Allowances**: All contract-initiated transfers now use `(with-stx amount)` allowances for enhanced security
- **Response Handling**: Updated to handle the new `(response A uint)` return type from `as-contract?`

Example of the new pattern:
```clarity
;; Old Clarity 1-3 syntax
(try! (stx-transfer? amount sender (as-contract tx-sender)))

;; New Clarity 4 syntax
(try! (as-contract? ((with-stx amount))
  (begin
    (try! (stx-transfer? amount sender tx-sender))
    true
  )
))
```

### Testing

```bash
# Run contract validation
clarinet check

# Execute test suite
npm test

# Format code
clarinet fmt --in-place
```

## Security Considerations

1. **Oracle Dependency**: Current implementation uses simplified oracle - production requires robust price feeds
2. **Interest Calculation**: Uses block timestamps - consider MEV implications
3. **Liquidation Timing**: Race conditions possible during high volatility
4. **Admin Controls**: Centralized price updates and emergency controls
5. **Integer Overflow**: All arithmetic operations use safe math practices
6. **Clarity 4 Asset Allowances**: Enhanced security with explicit asset allowances in `as-contract?` - all transfers now explicitly declare maximum amounts that can be moved

## Risk Factors

- **Bitcoin Volatility**: Rapid price movements may trigger cascading liquidations
- **Liquidity Risk**: Insufficient STX liquidity may prevent withdrawals
- **Smart Contract Risk**: Code vulnerabilities or unexpected behavior
- **Oracle Risk**: Price feed manipulation or failure
- **Regulatory Risk**: DeFi lending regulations may impact operations

## Roadmap

- [x] Clarity 4 upgrade with enhanced security features
- [ ] Decentralized price oracle integration
- [ ] Multi-collateral support (STX, other tokens)
- [ ] Variable interest rates based on utilization
- [ ] Governance token implementation
- [ ] Cross-chain collateral bridging
- [ ] Flash loan functionality
- [ ] Insurance pool integration

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
