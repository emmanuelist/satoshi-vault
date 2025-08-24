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

;; PROTOCOL ADMINISTRATION

(define-public (emergency-pause-protocol)
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) (err ERR_UNAUTHORIZED_ACCESS))
    (var-set protocol-operations-enabled false)
    (ok true)
  )
)

(define-public (resume-protocol-operations)
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) (err ERR_UNAUTHORIZED_ACCESS))
    (var-set protocol-operations-enabled true)
    (ok true)
  )
)

;; LIQUIDITY PROVISION (LENDING)

;; Deposit STX to earn competitive yields from borrower interest payments
(define-public (provide-stx-liquidity (deposit-amount uint))
  (let (
      (depositor tx-sender)
      (existing-position (map-get? lender-position-ledger { user: depositor }))
      (current-stx-balance (default-to u0 (get stx-deposited existing-position)))
    )
    ;; Comprehensive input validation
    (asserts! (var-get protocol-operations-enabled) (err ERR_UNAUTHORIZED_ACCESS))
    (asserts! (> deposit-amount u0) (err ERR_ZERO_VALUE_OPERATION))

    ;; Refresh interest calculations before processing
    (refresh-protocol-interest)

    ;; Execute STX transfer from depositor to protocol
    (try! (stx-transfer? deposit-amount depositor (as-contract tx-sender)))

    ;; Update depositor's position with new funds
    (map-set lender-position-ledger { user: depositor } {
      stx-deposited: (+ current-stx-balance deposit-amount),
      yield-index-entry: (var-get lender-yield-accumulator),
    })

    ;; Update global liquidity tracking
    (var-set global-stx-liquidity
      (+ (var-get global-stx-liquidity) deposit-amount)
    )

    (ok true)
  )
)

;; Withdraw deposited STX plus accumulated yield rewards
(define-public (withdraw-stx-liquidity (withdrawal-amount uint))
  (let (
      (withdrawer tx-sender)
      (position-data (unwrap! (map-get? lender-position-ledger { user: withdrawer })
        (err ERR_INSUFFICIENT_FUNDS)
      ))
      (deposited-principal (get stx-deposited position-data))
      (accrued-yield (unwrap! (calculate-earned-yield withdrawer)
        (err ERR_EXTERNAL_CONTRACT_ERROR)
      ))
      (total-withdrawable (+ deposited-principal accrued-yield))
      (actual-withdrawal (if (> withdrawal-amount total-withdrawable)
        total-withdrawable
        withdrawal-amount
      ))
    )
    ;; Input validation and safety checks
    (asserts! (var-get protocol-operations-enabled) (err ERR_UNAUTHORIZED_ACCESS))
    (asserts! (> withdrawal-amount u0) (err ERR_ZERO_VALUE_OPERATION))
    (asserts! (>= total-withdrawable withdrawal-amount)
      (err ERR_INVALID_WITHDRAWAL)
    )

    ;; Update interest before withdrawal processing
    (refresh-protocol-interest)

    ;; Calculate remaining position after withdrawal
    (let ((remaining-principal (if (>= deposited-principal withdrawal-amount)
        (- deposited-principal withdrawal-amount)
        u0
      )))
      ;; Update or remove position based on remaining balance
      (if (is-eq remaining-principal u0)
        (map-delete lender-position-ledger { user: withdrawer })
        (map-set lender-position-ledger { user: withdrawer } {
          stx-deposited: remaining-principal,
          yield-index-entry: (var-get lender-yield-accumulator),
        })
      )

      ;; Adjust global liquidity tracking
      (var-set global-stx-liquidity
        (if (>= (var-get global-stx-liquidity) withdrawal-amount)
          (- (var-get global-stx-liquidity) withdrawal-amount)
          u0
        ))

      ;; Execute STX transfer to withdrawer
      (try! (as-contract (stx-transfer? actual-withdrawal tx-sender withdrawer)))

      (ok true)
    )
  )
)

;; Calculate accumulated yield for a specific lender
(define-read-only (calculate-earned-yield (lender principal))
  (let (
      (position-data (map-get? lender-position-ledger { user: lender }))
      (entry-yield-index (default-to u0 (get yield-index-entry position-data)))
      (stx-principal (default-to u0 (get stx-deposited position-data)))
      (current-yield-index (var-get lender-yield-accumulator))
    )
    (if (> current-yield-index entry-yield-index)
      (let ((yield-growth (- current-yield-index entry-yield-index)))
        (ok (/ (* stx-principal yield-growth) PRECISION_BASIS_POINTS))
      )
      (ok u0)
    )
  )
)

;; COLLATERALIZED BORROWING SYSTEM

;; Deposit sBTC collateral and borrow STX in single atomic operation
(define-public (open-collateralized-position
    (sbtc-collateral-amount uint)
    (stx-borrow-request uint)
  )
  (let (
      (borrower tx-sender)
      (existing-collateral (map-get? borrower-collateral-ledger { user: borrower }))
      (current-collateral (default-to u0 (get sbtc-deposited existing-collateral)))
      (total-collateral (+ current-collateral sbtc-collateral-amount))
      (market-price (unwrap! (fetch-sbtc-market-price) (err ERR_PRICE_ORACLE_FAILURE)))
      (collateral-stx-value (* total-collateral market-price))
      (maximum-borrowable (/ (* collateral-stx-value MAX_LOAN_TO_VALUE_RATIO) u100))
      (existing-debt (map-get? borrower-debt-ledger { user: borrower }))
      (current-debt (unwrap! (compute-total-debt borrower) (err ERR_EXTERNAL_CONTRACT_ERROR)))
      (projected-total-debt (+ current-debt stx-borrow-request))
    )
    ;; Comprehensive validation and safety checks
    (asserts! (var-get protocol-operations-enabled) (err ERR_UNAUTHORIZED_ACCESS))
    (asserts! (> sbtc-collateral-amount u0) (err ERR_ZERO_VALUE_OPERATION))
    (asserts! (> stx-borrow-request u0) (err ERR_ZERO_VALUE_OPERATION))
    (asserts! (<= projected-total-debt maximum-borrowable)
      (err ERR_BORROW_LIMIT_EXCEEDED)
    )

    ;; Refresh interest calculations
    (refresh-protocol-interest)

    ;; Update borrower's debt position
    (map-set borrower-debt-ledger { user: borrower } {
      stx-borrowed: projected-total-debt,
      interest-checkpoint: (get-block-timestamp),
    })

    ;; Track global borrowed amount
    (var-set global-stx-borrowed
      (+ (var-get global-stx-borrowed) stx-borrow-request)
    )

    ;; Update collateral position
    (map-set borrower-collateral-ledger { user: borrower } { sbtc-deposited: total-collateral })

    ;; Track global collateral
    (var-set global-sbtc-collateral
      (+ (var-get global-sbtc-collateral) sbtc-collateral-amount)
    )

    ;; Transfer borrowed STX to borrower
    (try! (as-contract (stx-transfer? stx-borrow-request tx-sender borrower)))

    (ok true)
  )
)

;; Repay outstanding debt and optionally retrieve collateral
(define-public (repay-outstanding-debt (repayment-amount uint))
  (let (
      (borrower tx-sender)
      (debt-position (unwrap! (map-get? borrower-debt-ledger { user: borrower })
        (err ERR_INSUFFICIENT_FUNDS)
      ))
      (principal-borrowed (get stx-borrowed debt-position))
      (total-debt-owed (unwrap! (compute-total-debt borrower) (err ERR_EXTERNAL_CONTRACT_ERROR)))
      (collateral-position (map-get? borrower-collateral-ledger { user: borrower }))
      (collateral-sbtc (default-to u0 (get sbtc-deposited collateral-position)))
    )
    ;; Input validation
    (asserts! (var-get protocol-operations-enabled) (err ERR_UNAUTHORIZED_ACCESS))
    (asserts! (> repayment-amount u0) (err ERR_ZERO_VALUE_OPERATION))

    ;; Update interest calculations
    (refresh-protocol-interest)

    ;; Process STX repayment from borrower
    (try! (stx-transfer? repayment-amount borrower (as-contract tx-sender)))

    ;; Calculate remaining debt after repayment
    (let ((remaining-debt (if (>= repayment-amount total-debt-owed)
        u0
        (- total-debt-owed repayment-amount)
      )))
      (if (is-eq remaining-debt u0)
        (begin
          ;; Complete debt repayment - clear all positions
          (map-delete borrower-collateral-ledger { user: borrower })
          (map-delete borrower-debt-ledger { user: borrower })