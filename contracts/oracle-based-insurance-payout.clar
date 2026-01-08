(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-policy-expired (err u104))
(define-constant err-policy-not-active (err u105))
(define-constant err-oracle-not-authorized (err u106))
(define-constant err-invalid-data (err u107))
(define-constant err-payout-already-processed (err u108))
(define-constant err-insufficient-consensus (err u109))
(define-constant err-oracle-already-registered (err u110))
(define-constant err-stake-locked (err u111))
(define-constant err-insufficient-stake (err u112))
(define-constant err-no-rewards (err u113))

(define-data-var next-policy-id uint u1)
(define-data-var oracle-address principal tx-sender)
(define-data-var oracle-fee uint u1000000)
(define-data-var min-premium uint u5000000)
(define-data-var max-payout-ratio uint u300)
(define-data-var min-consensus-weight uint u100)
(define-data-var total-oracle-weight uint u0)
(define-data-var total-staked uint u0)
(define-data-var total-premium-fees uint u0)
(define-data-var premium-fee-percentage uint u10)
(define-data-var stake-lock-period uint u144)

(define-map policies 
    { policy-id: uint }
    { 
        policyholder: principal,
        beneficiary: principal,
        premium-paid: uint,
        coverage-amount: uint,
        start-block: uint,
        end-block: uint,
        trigger-condition: uint,
        trigger-operator: (string-ascii 2),
        status: (string-ascii 10),
        payout-processed: bool
    }
)

(define-map oracle-data
    { data-key: (string-ascii 20) }
    { 
        value: uint,
        timestamp: uint,
        block-height: uint,
        reporter: principal
    }
)

(define-map policy-claims
    { policy-id: uint }
    {
        claim-amount: uint,
        claim-timestamp: uint,
        data-used: uint,
        processed: bool
    }
)

(define-map registered-oracles
    { oracle: principal }
    {
        weight: uint,
        active: bool,
        total-reports: uint
    }
)

(define-map oracle-reports
    { data-key: (string-ascii 20), oracle: principal }
    {
        value: uint,
        timestamp: uint,
        block-height: uint
    }
)

(define-map consensus-data
    { data-key: (string-ascii 20) }
    {
        consensus-value: uint,
        total-weight: uint,
        report-count: uint,
        last-updated: uint
    }
)

(define-map stakers
    { staker: principal }
    {
        amount-staked: uint,
        stake-block: uint,
        last-claim-block: uint,
        total-rewards-claimed: uint
    }
)

(define-public (set-oracle-address (new-oracle principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set oracle-address new-oracle)
        (ok true)
    )
)

(define-public (set-oracle-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set oracle-fee new-fee)
        (ok true)
    )
)

(define-public (update-oracle-data (data-key (string-ascii 20)) (value uint))
    (let ((current-oracle (var-get oracle-address)))
        (asserts! (is-eq tx-sender current-oracle) err-oracle-not-authorized)
        (asserts! (> value u0) err-invalid-data)
        (map-set oracle-data 
            { data-key: data-key }
            {
                value: value,
                timestamp: burn-block-height,
                block-height: burn-block-height,
                reporter: tx-sender
            }
        )
        (ok true)
    )
)

(define-public (create-policy 
    (coverage-amount uint)
    (duration-blocks uint)
    (trigger-condition uint)
    (trigger-operator (string-ascii 2))
)
    (let 
        (
            (policy-id (var-get next-policy-id))
            (premium (calculate-premium coverage-amount duration-blocks))
        )
        (asserts! (>= (stx-get-balance tx-sender) premium) err-insufficient-funds)
        (asserts! (>= premium (var-get min-premium)) err-insufficient-funds)
        (asserts! (> coverage-amount u0) err-invalid-data)
        (asserts! (> duration-blocks u0) err-invalid-data)
        
        (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
        
        (let ((premium-fee (/ (* premium (var-get premium-fee-percentage)) u100)))
            (var-set total-premium-fees (+ (var-get total-premium-fees) premium-fee))
            
            (map-set policies
                { policy-id: policy-id }
                {
                    policyholder: tx-sender,
                    beneficiary: tx-sender,
                    premium-paid: premium,
                    coverage-amount: coverage-amount,
                    start-block: burn-block-height,
                    end-block: (+ burn-block-height duration-blocks),
                    trigger-condition: trigger-condition,
                    trigger-operator: trigger-operator,
                    status: "active",
                    payout-processed: false
                }
            )
            
            (var-set next-policy-id (+ policy-id u1))
            (ok policy-id)
        )
    )
)

(define-public (submit-claim (policy-id uint) (data-key (string-ascii 20)))
    (let 
        (
            (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
            (oracle-info (unwrap! (map-get? oracle-data { data-key: data-key }) err-not-found))
        )
        (asserts! (is-eq (get policyholder policy) tx-sender) err-owner-only)
        (asserts! (is-eq (get status policy) "active") err-policy-not-active)
        (asserts! (> (get end-block policy) burn-block-height) err-policy-expired)
        (asserts! (not (get payout-processed policy)) err-payout-already-processed)
        
        (let ((condition-met (evaluate-condition 
                (get value oracle-info)
                (get trigger-condition policy)
                (get trigger-operator policy))))
            (if condition-met
                (let 
                    (
                        (payout-amount (calculate-payout-amount policy-id (get value oracle-info)))
                        (contract-balance (stx-get-balance (as-contract tx-sender)))
                    )
                    (asserts! (>= contract-balance payout-amount) err-insufficient-funds)
                    
                    (map-set policy-claims
                        { policy-id: policy-id }
                        {
                            claim-amount: payout-amount,
                            claim-timestamp: burn-block-height,
                            data-used: (get value oracle-info),
                            processed: true
                        }
                    )
                    
                    (map-set policies
                        { policy-id: policy-id }
                        (merge policy { status: "paid-out", payout-processed: true })
                    )
                    
                    (try! (as-contract (stx-transfer? payout-amount tx-sender (get beneficiary policy))))
                    (ok payout-amount)
                )
                (begin
                    (map-set policies
                        { policy-id: policy-id }
                        (merge policy { status: "expired", payout-processed: true })
                    )
                    (ok u0)
                )
            )
        )
    )
)

(define-public (cancel-policy (policy-id uint))
    (let 
        ((policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found)))
        (asserts! (is-eq (get policyholder policy) tx-sender) err-owner-only)
        (asserts! (is-eq (get status policy) "active") err-policy-not-active)
        (asserts! (not (get payout-processed policy)) err-payout-already-processed)
        
        (let ((refund-amount (/ (get premium-paid policy) u2)))
            (map-set policies
                { policy-id: policy-id }
                (merge policy { status: "cancelled", payout-processed: true })
            )
            (try! (as-contract (stx-transfer? refund-amount tx-sender (get policyholder policy))))
            (ok refund-amount)
        )
    )
)

(define-public (extend-policy (policy-id uint) (additional-blocks uint))
    (let 
        (
            (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
            (extension-premium (calculate-premium (get coverage-amount policy) additional-blocks))
        )
        (asserts! (> additional-blocks u0) err-invalid-data)
        (asserts! (is-eq (get policyholder policy) tx-sender) err-owner-only)
        (asserts! (is-eq (get status policy) "active") err-policy-not-active)
        (asserts! (not (get payout-processed policy)) err-payout-already-processed)
        (asserts! (>= (stx-get-balance tx-sender) extension-premium) err-insufficient-funds)
        (try! (stx-transfer? extension-premium tx-sender (as-contract tx-sender)))
        (let ((premium-fee (/ (* extension-premium (var-get premium-fee-percentage)) u100)))
            (var-set total-premium-fees (+ (var-get total-premium-fees) premium-fee))
            (map-set policies
                { policy-id: policy-id }
                (merge policy {
                    premium-paid: (+ (get premium-paid policy) extension-premium),
                    end-block: (+ (get end-block policy) additional-blocks)
                })
            )
            (ok (get end-block (unwrap-panic (map-get? policies { policy-id: policy-id }))))
        )
    )
)

(define-public (withdraw-funds (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (>= (stx-get-balance (as-contract tx-sender)) amount) err-insufficient-funds)
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (ok amount)
    )
)

(define-public (register-oracle (oracle principal) (weight uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> weight u0) err-invalid-data)
        (asserts! (is-none (map-get? registered-oracles { oracle: oracle })) err-oracle-already-registered)
        
        (map-set registered-oracles
            { oracle: oracle }
            {
                weight: weight,
                active: true,
                total-reports: u0
            }
        )
        
        (var-set total-oracle-weight (+ (var-get total-oracle-weight) weight))
        (ok true)
    )
)

(define-public (deactivate-oracle (oracle principal))
    (let ((oracle-info (unwrap! (map-get? registered-oracles { oracle: oracle }) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (get active oracle-info) err-policy-not-active)
        
        (map-set registered-oracles
            { oracle: oracle }
            (merge oracle-info { active: false })
        )
        
        (var-set total-oracle-weight (- (var-get total-oracle-weight) (get weight oracle-info)))
        (ok true)
    )
)

(define-public (submit-oracle-report (data-key (string-ascii 20)) (value uint))
    (let ((oracle-info (unwrap! (map-get? registered-oracles { oracle: tx-sender }) err-oracle-not-authorized)))
        (asserts! (get active oracle-info) err-policy-not-active)
        (asserts! (> value u0) err-invalid-data)
        
        (map-set oracle-reports
            { data-key: data-key, oracle: tx-sender }
            {
                value: value,
                timestamp: burn-block-height,
                block-height: burn-block-height
            }
        )
        
        (map-set registered-oracles
            { oracle: tx-sender }
            (merge oracle-info { total-reports: (+ (get total-reports oracle-info) u1) })
        )
        
        (unwrap-panic (update-consensus-data data-key))
        (ok true)
    )
)

(define-public (submit-consensus-claim (policy-id uint) (data-key (string-ascii 20)))
    (let 
        (
            (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
            (consensus-info (unwrap! (map-get? consensus-data { data-key: data-key }) err-not-found))
        )
        (asserts! (is-eq (get policyholder policy) tx-sender) err-owner-only)
        (asserts! (is-eq (get status policy) "active") err-policy-not-active)
        (asserts! (> (get end-block policy) burn-block-height) err-policy-expired)
        (asserts! (not (get payout-processed policy)) err-payout-already-processed)
        (asserts! (>= (get total-weight consensus-info) (var-get min-consensus-weight)) err-insufficient-consensus)
        
        (let ((condition-met (evaluate-condition 
                (get consensus-value consensus-info)
                (get trigger-condition policy)
                (get trigger-operator policy))))
            (if condition-met
                (let 
                    (
                        (payout-amount (calculate-payout-amount policy-id (get consensus-value consensus-info)))
                        (contract-balance (stx-get-balance (as-contract tx-sender)))
                    )
                    (asserts! (>= contract-balance payout-amount) err-insufficient-funds)
                    
                    (map-set policy-claims
                        { policy-id: policy-id }
                        {
                            claim-amount: payout-amount,
                            claim-timestamp: burn-block-height,
                            data-used: (get consensus-value consensus-info),
                            processed: true
                        }
                    )
                    
                    (map-set policies
                        { policy-id: policy-id }
                        (merge policy { status: "paid-out", payout-processed: true })
                    )
                    
                    (try! (as-contract (stx-transfer? payout-amount tx-sender (get beneficiary policy))))
                    (ok payout-amount)
                )
                (begin
                    (map-set policies
                        { policy-id: policy-id }
                        (merge policy { status: "expired", payout-processed: true })
                    )
                    (ok u0)
                )
            )
        )
    )
)

(define-public (set-policy-beneficiary (policy-id uint) (beneficiary principal))
    (let 
        (
            (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
        )
        (asserts! (is-eq (get policyholder policy) tx-sender) err-owner-only)
        (asserts! (is-eq (get status policy) "active") err-policy-not-active)
        (asserts! (not (get payout-processed policy)) err-payout-already-processed)
        (map-set policies
            { policy-id: policy-id }
            (merge policy { beneficiary: beneficiary })
        )
        (ok beneficiary)
    )
)

(define-public (stake-liquidity (amount uint))
    (let ((current-stake (map-get? stakers { staker: tx-sender })))
        (asserts! (> amount u0) err-invalid-data)
        (asserts! (>= (stx-get-balance tx-sender) amount) err-insufficient-funds)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (if (is-some current-stake)
            (let ((stake-info (unwrap-panic current-stake)))
                (map-set stakers
                    { staker: tx-sender }
                    (merge stake-info { 
                        amount-staked: (+ (get amount-staked stake-info) amount)
                    })
                )
            )
            (map-set stakers
                { staker: tx-sender }
                {
                    amount-staked: amount,
                    stake-block: burn-block-height,
                    last-claim-block: burn-block-height,
                    total-rewards-claimed: u0
                }
            )
        )
        
        (var-set total-staked (+ (var-get total-staked) amount))
        (ok amount)
    )
)

(define-public (unstake-liquidity (amount uint))
    (let 
        (
            (stake-info (unwrap! (map-get? stakers { staker: tx-sender }) err-not-found))
            (lock-end (+ (get stake-block stake-info) (var-get stake-lock-period)))
        )
        (asserts! (> amount u0) err-invalid-data)
        (asserts! (>= (get amount-staked stake-info) amount) err-insufficient-stake)
        (asserts! (>= burn-block-height lock-end) err-stake-locked)
        
        (let ((new-stake (- (get amount-staked stake-info) amount)))
            (if (is-eq new-stake u0)
                (map-delete stakers { staker: tx-sender })
                (map-set stakers
                    { staker: tx-sender }
                    (merge stake-info { amount-staked: new-stake })
                )
            )
        )
        
        (var-set total-staked (- (var-get total-staked) amount))
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (ok amount)
    )
)

(define-public (claim-staking-rewards)
    (let 
        (
            (stake-info (unwrap! (map-get? stakers { staker: tx-sender }) err-not-found))
            (rewards (calculate-staker-rewards tx-sender))
        )
        (asserts! (> rewards u0) err-no-rewards)
        (asserts! (>= (var-get total-premium-fees) rewards) err-insufficient-funds)
        
        (map-set stakers
            { staker: tx-sender }
            (merge stake-info { 
                last-claim-block: burn-block-height,
                total-rewards-claimed: (+ (get total-rewards-claimed stake-info) rewards)
            })
        )
        
        (var-set total-premium-fees (- (var-get total-premium-fees) rewards))
        (try! (as-contract (stx-transfer? rewards tx-sender tx-sender)))
        (ok rewards)
    )
)

(define-read-only (calculate-premium (coverage-amount uint) (duration-blocks uint))
    (let 
        (
            (base-rate u50)
            (duration-factor (/ duration-blocks u1000))
            (coverage-factor (/ coverage-amount u1000000))
        )
        (+ 
            (var-get min-premium)
            (* base-rate duration-factor coverage-factor)
        )
    )
)

(define-read-only (calculate-payout-amount (policy-id uint) (oracle-value uint))
    (let 
        ((policy (unwrap-panic (map-get? policies { policy-id: policy-id }))))
        (let 
            (
                (base-payout (get coverage-amount policy))
                (severity-multiplier (get-severity-multiplier oracle-value (get trigger-condition policy)))
            )
            (let ((calculated-payout (* base-payout severity-multiplier)))
                (if (< calculated-payout base-payout)
                    calculated-payout
                    base-payout))
        )
    )
)

(define-read-only (get-severity-multiplier (oracle-value uint) (trigger-value uint))
    (let ((difference (if (> oracle-value trigger-value)
                         (- oracle-value trigger-value)
                         (- trigger-value oracle-value))))
        (let ((calculated-multiplier (+ u1 (/ difference u100))))
            (if (< calculated-multiplier u3)
                calculated-multiplier
                u3))
    )
)

(define-read-only (evaluate-condition (oracle-value uint) (trigger-value uint) (operator (string-ascii 2)))
    (if (is-eq operator "gt")
        (> oracle-value trigger-value)
        (if (is-eq operator "lt")
            (< oracle-value trigger-value)
            (if (is-eq operator "eq")
                (is-eq oracle-value trigger-value)
                (if (is-eq operator "ge")
                    (>= oracle-value trigger-value)
                    (if (is-eq operator "le")
                        (<= oracle-value trigger-value)
                        false
                    )
                )
            )
        )
    )
)

(define-read-only (get-policy (policy-id uint))
    (map-get? policies { policy-id: policy-id })
)

(define-read-only (get-policy-beneficiary (policy-id uint))
    (get beneficiary (unwrap-panic (map-get? policies { policy-id: policy-id })))
)

(define-read-only (get-oracle-data (data-key (string-ascii 20)))
    (map-get? oracle-data { data-key: data-key })
)

(define-read-only (get-policy-claim (policy-id uint))
    (map-get? policy-claims { policy-id: policy-id })
)

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-next-policy-id)
    (var-get next-policy-id)
)

(define-read-only (get-oracle-address)
    (var-get oracle-address)
)

(define-read-only (get-oracle-fee)
    (var-get oracle-fee)
)

(define-read-only (get-min-premium)
    (var-get min-premium)
)

(define-private (update-consensus-data (data-key (string-ascii 20)))
    (let 
        (
            (current-consensus (map-get? consensus-data { data-key: data-key }))
            (weighted-sum u0)
            (total-weight u0)
            (report-count u0)
        )
        (let ((consensus-result (calculate-consensus data-key weighted-sum total-weight report-count)))
            (map-set consensus-data
                { data-key: data-key }
                {
                    consensus-value: (get consensus-value consensus-result),
                    total-weight: (get total-weight consensus-result),
                    report-count: (get report-count consensus-result),
                    last-updated: burn-block-height
                }
            )
            (ok true)
        )
    )
)

(define-private (calculate-consensus (data-key (string-ascii 20)) (weighted-sum uint) (total-weight uint) (report-count uint))
    (let 
        (
            (oracle-list (get-oracle-list))
            (final-weighted-sum (fold sum-weighted-reports oracle-list { data-key: data-key, weighted-sum: u0, total-weight: u0, report-count: u0 }))
        )
        (let ((consensus-value (if (> (get total-weight final-weighted-sum) u0)
                                   (/ (get weighted-sum final-weighted-sum) (get total-weight final-weighted-sum))
                                   u0)))
            {
                consensus-value: consensus-value,
                total-weight: (get total-weight final-weighted-sum),
                report-count: (get report-count final-weighted-sum)
            }
        )
    )
)

(define-private (sum-weighted-reports (oracle principal) (acc { data-key: (string-ascii 20), weighted-sum: uint, total-weight: uint, report-count: uint }))
    (let 
        (
            (oracle-info (map-get? registered-oracles { oracle: oracle }))
            (report (map-get? oracle-reports { data-key: (get data-key acc), oracle: oracle }))
        )
        (if (and (is-some oracle-info) (is-some report) (get active (unwrap-panic oracle-info)))
            {
                data-key: (get data-key acc),
                weighted-sum: (+ (get weighted-sum acc) (* (get value (unwrap-panic report)) (get weight (unwrap-panic oracle-info)))),
                total-weight: (+ (get total-weight acc) (get weight (unwrap-panic oracle-info))),
                report-count: (+ (get report-count acc) u1)
            }
            acc
        )
    )
)

(define-private (get-oracle-list)
    (list 
        (var-get oracle-address)
    )
)

(define-read-only (get-consensus-data (data-key (string-ascii 20)))
    (map-get? consensus-data { data-key: data-key })
)

(define-read-only (get-oracle-info (oracle principal))
    (map-get? registered-oracles { oracle: oracle })
)

(define-read-only (get-oracle-report (data-key (string-ascii 20)) (oracle principal))
    (map-get? oracle-reports { data-key: data-key, oracle: oracle })
)

(define-read-only (get-total-oracle-weight)
    (var-get total-oracle-weight)
)

(define-read-only (get-min-consensus-weight)
    (var-get min-consensus-weight)
)

(define-read-only (calculate-staker-rewards (staker principal))
    (let 
        (
            (stake-info (map-get? stakers { staker: staker }))
            (total-pool (var-get total-staked))
        )
        (if (and (is-some stake-info) (> total-pool u0))
            (let 
                (
                    (info (unwrap-panic stake-info))
                    (stake-share (/ (* (get amount-staked info) u1000000) total-pool))
                    (available-fees (var-get total-premium-fees))
                )
                (/ (* available-fees stake-share) u1000000)
            )
            u0
        )
    )
)

(define-read-only (get-staker-info (staker principal))
    (map-get? stakers { staker: staker })
)

(define-read-only (get-total-staked)
    (var-get total-staked)
)

(define-read-only (get-total-premium-fees)
    (var-get total-premium-fees)
)

(define-read-only (get-pool-apy)
    (let 
        (
            (total-pool (var-get total-staked))
            (total-fees (var-get total-premium-fees))
        )
        (if (> total-pool u0)
            (/ (* total-fees u10000) total-pool)
            u0
        )
    )
)

(define-read-only (get-stake-lock-period)
    (var-get stake-lock-period)
)
