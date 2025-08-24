;; Title: SatoshiVault Protocol
;;
;; Summary: Advanced Bitcoin-collateralized lending infrastructure that bridges
;; Bitcoin's store-of-value properties with Stacks' smart contract capabilities,
;; enabling seamless capital efficiency for the Bitcoin economy.
;;
;; Description: SatoshiVault represents the next evolution of Bitcoin DeFi,
;; creating a trustless lending ecosystem where Bitcoin holders can unlock
;; capital without selling their BTC exposure. Through sophisticated sBTC
;; collateralization mechanics, users access STX liquidity while maintaining
;; Bitcoin position integrity. The protocol features dynamic yield optimization,
;; automated risk management, and capital-efficient liquidation systems designed
;; specifically for Bitcoin's volatile yet appreciating asset characteristics.
;; Built natively on Stacks Layer-2 for maximum Bitcoin alignment and security.

;; ERROR CONSTANTS & PROTOCOL SAFETY

(define-constant ERR_INVALID_WITHDRAWAL u100)
(define-constant ERR_BORROW_LIMIT_EXCEEDED u101)
(define-constant ERR_POSITION_SAFE_FROM_LIQUIDATION u102)
(define-constant ERR_EXISTING_POSITION_CONFLICT u103)
(define-constant ERR_INSUFFICIENT_FUNDS u104)
(define-constant ERR_ZERO_VALUE_OPERATION u105)
(define-constant ERR_PRICE_ORACLE_FAILURE u106)
(define-constant ERR_EXTERNAL_CONTRACT_ERROR u107)
(define-constant ERR_UNAUTHORIZED_ACCESS u108)

;; PROTOCOL CONFIGURATION SETTINGS

(define-constant MAX_LOAN_TO_VALUE_RATIO u70) ;; Conservative 70% LTV for Bitcoin volatility
(define-constant INTEREST_RATE_ANNUAL u10) ;; 10% APR competitive lending rate
(define-constant LIQUIDATION_THRESHOLD u80) ;; 80% threshold provides safety buffer
(define-constant LIQUIDATION_BONUS u10) ;; 10% incentive for liquidators
(define-constant SECONDS_IN_YEAR u31556952) ;; Precise yearly seconds calculation
(define-constant PRECISION_BASIS_POINTS u10000) ;; High precision for yield calculations

;; Protocol governance
(define-constant PROTOCOL_ADMIN tx-sender)

;; GLOBAL PROTOCOL STATE VARS

;; Aggregate collateral tracking across all users
(define-data-var global-sbtc-collateral uint u0)

;; Total STX available for lending (liquidity pool)
(define-data-var global-stx-liquidity uint u1)

;; Outstanding borrowed STX across all positions  
(define-data-var global-stx-borrowed uint u0)

;; Last timestamp when interest was calculated
(define-data-var interest-accrual-checkpoint uint u0)

;; Accumulated yield index for lender rewards (scaled by basis points)
(define-data-var lender-yield-accumulator uint u0)

;; Dynamic sBTC price feed (simplified oracle - 1 sBTC = 50,000 STX baseline)
(define-data-var sbtc-to-stx-exchange-rate uint u50000)

;; Emergency protocol controls
(define-data-var protocol-operations-enabled bool true)

;; USER POSITION DATA STRUCTURES=

;; Individual user collateral tracking
(define-map borrower-collateral-ledger
  { user: principal }
  { sbtc-deposited: uint }
)

;; Lender deposit and yield tracking
(define-map lender-position-ledger
  { user: principal }
  {
    stx-deposited: uint,
    yield-index-entry: uint,
  }
)

;; Borrower debt and interest tracking
(define-map borrower-debt-ledger
  { user: principal }
  {
    stx-borrowed: uint,
    interest-checkpoint: uint,
  }
)

;; PRICE ORACLE & MARKET DATA

;; Retrieve current sBTC market price in STX terms
(define-read-only (fetch-sbtc-market-price)
  (ok (var-get sbtc-to-stx-exchange-rate))
)

;; Administrative price update capability (for static oracle implementation)
(define-public (update-market-price (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) (err ERR_UNAUTHORIZED_ACCESS))
    (asserts! (> new-rate u0) (err ERR_ZERO_VALUE_OPERATION))
    (var-set sbtc-to-stx-exchange-rate new-rate)
    (ok true)
  )
)