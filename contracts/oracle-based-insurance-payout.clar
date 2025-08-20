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

(define-data-var next-policy-id uint u1)
(define-data-var oracle-address principal tx-sender)
(define-data-var oracle-fee uint u1000000)
(define-data-var min-premium uint u5000000)
(define-data-var max-payout-ratio uint u300)

(define-map policies 
    { policy-id: uint }
    { 
        policyholder: principal,
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
        
        (map-set policies
            { policy-id: policy-id }
            {
                policyholder: tx-sender,
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
                    
                    (try! (as-contract (stx-transfer? payout-amount tx-sender (get policyholder policy))))
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

(define-public (withdraw-funds (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (>= (stx-get-balance (as-contract tx-sender)) amount) err-insufficient-funds)
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (ok amount)
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
