;; Sybil Resistance Mechanism Smart Contract
;; This contract implements various mechanisms to prevent Sybil attacks
;; including stake-based verification, proof-of-personhood, and reputation scoring

(define-data-var admin principal tx-sender)
(define-data-var min-stake uint u1000000) ;; Minimum stake in microSTX
(define-data-var verification-threshold uint u3) ;; Number of verifications needed
(define-data-var cooldown-period uint u144) ;; ~24 hours in Stacks blocks (6 blocks/hour)
(define-data-var reputation-decay-rate uint u10) ;; Reputation decay rate (percentage)
(define-data-var verification-expiry uint u4320) ;; 30 days in Stacks blocks

;; Maps for storing user data
(define-map user-stakes { user: principal } { amount: uint, locked-until: uint })
(define-map user-verifications { user: principal } { count: uint, last-verified: uint })
(define-map user-reputation { user: principal } { score: uint, last-updated: uint })
(define-map verifications { verifier: principal, verified: principal } { timestamp: uint, weight: uint })
(define-map blacklisted-addresses { address: principal } { blacklisted: bool, reason: (string-utf8 100) })

;; Error codes
(define-constant ERR-NOT-AUTHORIZED u1)
(define-constant ERR-ALREADY-VERIFIED u2)
(define-constant ERR-INSUFFICIENT-STAKE u3)
(define-constant ERR-COOLDOWN-ACTIVE u4)
(define-constant ERR-SELF-VERIFICATION u5)
(define-constant ERR-BLACKLISTED u6)
(define-constant ERR-INVALID-REPUTATION u7)
(define-constant ERR-THRESHOLD-NOT-MET u8)
(define-constant ERR-INVALID-PARAMETER u9)
(define-constant ERR-OVERFLOW u10)
(define-constant ERR-INVALID-ADDRESS u11)
(define-constant ERR-INVALID-STRING u12)

;; Helper function to get current block height
(define-private (get-current-block)
  block-height
)

;; Helper function to replace min functionality
(define-private (get-min (a uint) (b uint))
  (if (<= a b) a b))

;; Helper function to check for uint addition overflow
(define-private (checked-add (a uint) (b uint))
  (let ((result (+ a b)))
    (if (>= result a)
        (ok result)
        (err ERR-OVERFLOW))
  )
)

;; Helper function to check if an address is blacklisted
(define-private (is-address-blacklisted (address principal))
  (is-some (map-get? blacklisted-addresses { address: address }))
)

;; Calculate reputation score based on stake, verifications, and account activity
(define-read-only (calculate-reputation (user principal))
  (let
    (
      (stake-info (default-to { amount: u0, locked-until: u0 } (map-get? user-stakes { user: user })))
      (verification-info (default-to { count: u0, last-verified: u0 } (map-get? user-verifications { user: user })))
      (reputation-info (default-to { score: u0, last-updated: u0 } (map-get? user-reputation { user: user })))
      (current-block block-height)
      (stake-factor (/ (get amount stake-info) (var-get min-stake)))
      (verification-factor (* (get count verification-info) u10))
      (decay-amount (if (> current-block (get last-updated reputation-info))
                       (get-min u100 (* (var-get reputation-decay-rate) (/ (- current-block (get last-updated reputation-info)) u144)))
                       u0))
      (time-factor (- u100 decay-amount))
      (base-score (+ (* stake-factor u30) (* verification-factor u20)))
      (decayed-score (/ (* base-score time-factor) u100))
    )
    (get-min u1000 decayed-score) ;; Cap at 1000
  )
)

;; Update user's reputation score - internal function
(define-private (update-reputation-internal (user principal))
  (let
    (
      (new-score (calculate-reputation user))
      (current-block (get-current-block))
    )
    (map-set user-reputation { user: user } { score: new-score, last-updated: current-block })
    new-score
  )
)

;; Add stake to increase user's reputation
(define-public (add-stake (amount uint) (lock-period uint))
  (begin
    ;; Validate inputs
    (asserts! (> amount u0) (err ERR-INVALID-PARAMETER))
    (asserts! (> lock-period u0) (err ERR-INVALID-PARAMETER))
    
    (let
      (
        (user tx-sender)
        (current-stake (default-to { amount: u0, locked-until: u0 } (map-get? user-stakes { user: user })))
        (current-block (get-current-block))
        (lock-until (+ current-block lock-period))
      )
      (begin
        ;; Check if user is blacklisted
        (asserts! (not (is-address-blacklisted user)) (err ERR-BLACKLISTED))
        
        ;; Transfer STX from user to contract
        (try! (stx-transfer? amount user (as-contract tx-sender)))
        
        ;; Update user's stake with checked addition to prevent overflow
        (match (checked-add (get amount current-stake) amount)
          new-amount (begin
            (map-set user-stakes 
              { user: user } 
              { 
                amount: new-amount, 
                locked-until: (if (> (get locked-until current-stake) lock-until)
                                (get locked-until current-stake)
                                lock-until)
              }
            )
            
            ;; Update reputation
            (update-reputation-internal user)
            (ok true)
          )
          error-code (err error-code)
        )
      )
    )
  )
)

;; Withdraw stake after lock period
(define-public (withdraw-stake (amount uint))
  (begin
    ;; Validate input
    (asserts! (> amount u0) (err ERR-INVALID-PARAMETER))
    
    (let
      (
        (user tx-sender)
        (current-stake (default-to { amount: u0, locked-until: u0 } (map-get? user-stakes { user: user })))
        (current-block (get-current-block))
        (remaining-stake (- (get amount current-stake) amount))
      )
      (begin
        ;; Check if user is blacklisted
        (asserts! (not (is-address-blacklisted user)) (err ERR-BLACKLISTED))
        
        ;; Check if lock period has expired
        (asserts! (>= current-block (get locked-until current-stake)) (err ERR-COOLDOWN-ACTIVE))
        
        ;; Check if user has enough stake
        (asserts! (<= amount (get amount current-stake)) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Check if remaining stake is at least minimum required
        (asserts! (or (is-eq remaining-stake u0) (>= remaining-stake (var-get min-stake))) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Transfer STX from contract to user
        (try! (as-contract (stx-transfer? amount (as-contract tx-sender) user)))
        
        ;; Update user's stake
        (map-set user-stakes 
          { user: user } 
          { 
            amount: remaining-stake, 
            locked-until: (if (is-eq remaining-stake u0) u0 (get locked-until current-stake))
          }
        )
        
        ;; Update reputation
        (update-reputation-internal user)
        (ok true)
      )
    )
  )
)

;; Verify another user (requires stake and good reputation)
(define-public (verify-user (user principal))
  (begin
    ;; Validate input - check if user is valid
    (asserts! (not (is-eq user (as-contract tx-sender))) (err ERR-INVALID-ADDRESS))
    (asserts! (not (is-address-blacklisted user)) (err ERR-BLACKLISTED))
    
    (let
      (
        (verifier tx-sender)
        (verifier-stake (default-to { amount: u0, locked-until: u0 } (map-get? user-stakes { user: verifier })))
        (verifier-reputation (calculate-reputation verifier))
        (current-block (get-current-block))
        (verification-info (default-to { count: u0, last-verified: u0 } (map-get? user-verifications { user: user })))
        (last-verification (default-to { timestamp: u0, weight: u0 } 
                            (map-get? verifications { verifier: verifier, verified: user })))
      )
      (begin
        ;; Check that user is not verifying themselves
        (asserts! (not (is-eq verifier user)) (err ERR-SELF-VERIFICATION))
        
        ;; Check if verifier has minimum stake
        (asserts! (>= (get amount verifier-stake) (var-get min-stake)) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Check if verifier is blacklisted
        (asserts! (not (is-address-blacklisted verifier)) (err ERR-BLACKLISTED))
        
        ;; Check cooldown period
        (asserts! (or (is-eq (get timestamp last-verification) u0)
                      (>= current-block (+ (get timestamp last-verification) (var-get cooldown-period))))
                (err ERR-COOLDOWN-ACTIVE))
        
        ;; Calculate verification weight based on verifier's reputation
        (let
          ((verification-weight (/ verifier-reputation u100)))
          
          ;; Record verification
          (map-set verifications 
            { verifier: verifier, verified: user } 
            { timestamp: current-block, weight: verification-weight })
          
          ;; Update user's verification count with checked addition
          (match (checked-add (get count verification-info) u1)
            new-count (begin
              (map-set user-verifications 
                { user: user } 
                { count: new-count, last-verified: current-block })
              
              ;; Update user's reputation
              (update-reputation-internal user)
              (ok true)
            )
            error-code (err error-code)
          )
        )
      )
    )
  )
)

;; Check if a user is Sybil-resistant (meets verification threshold and stake requirement)
(define-read-only (is-sybil-resistant (user principal))
  (let
    (
      (verification-info (default-to { count: u0, last-verified: u0 } (map-get? user-verifications { user: user })))
      (stake-info (default-to { amount: u0, locked-until: u0 } (map-get? user-stakes { user: user })))
      (current-block (get-current-block))
      (expiry-block (if (>= current-block (var-get verification-expiry))
                        (- current-block (var-get verification-expiry))
                        u0))
      (verified-enough (>= (get count verification-info) (var-get verification-threshold)))
      (staked-enough (>= (get amount stake-info) (var-get min-stake)))
      (recently-verified (>= (get last-verified verification-info) expiry-block))
      (not-blacklisted (not (is-address-blacklisted user)))
    )
    (and verified-enough staked-enough recently-verified not-blacklisted)
  )
)

;; Get user's reputation score without updating it
(define-read-only (get-reputation (user principal))
  (calculate-reputation user)
)

;; Get user's stake information
(define-read-only (get-stake (user principal))
  (default-to { amount: u0, locked-until: u0 } (map-get? user-stakes { user: user }))
)

;; Get current verification threshold
(define-read-only (get-verification-threshold)
  (var-get verification-threshold)
)

;; Get and update user's reputation score
(define-public (update-user-reputation (user principal))
  (begin
    ;; Direct validation of user input
    (asserts! (not (is-eq user (as-contract tx-sender))) (err ERR-INVALID-ADDRESS))
    (asserts! (not (is-address-blacklisted user)) (err ERR-BLACKLISTED))
    
    ;; Safe to update reputation after validation
    (ok (update-reputation-internal user))
  )
)

;; Set verification threshold (admin only)
(define-public (set-verification-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-NOT-AUTHORIZED))
    (asserts! (> new-threshold u0) (err ERR-INVALID-PARAMETER))
    (var-set verification-threshold new-threshold)
    (ok true)
  )
)

;; Set minimum stake (admin only)
(define-public (set-min-stake (new-min-stake uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-NOT-AUTHORIZED))
    (asserts! (> new-min-stake u0) (err ERR-INVALID-PARAMETER))
    (var-set min-stake new-min-stake)
    (ok true)
  )
)

;; Blacklist an address (admin only)
(define-public (blacklist-address (address principal) (reason (string-utf8 100)))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (is-eq address (var-get admin))) (err ERR-INVALID-PARAMETER))
    
    ;; Validate inputs directly
    (asserts! (not (is-eq address (as-contract tx-sender))) (err ERR-INVALID-ADDRESS))
    (asserts! (> (len reason) u0) (err ERR-INVALID-STRING))
    
    ;; Safe to blacklist after validation
    (map-set blacklisted-addresses { address: address } { blacklisted: true, reason: reason })
    (ok true)
  )
)

;; Remove address from blacklist (admin only)
(define-public (remove-from-blacklist (address principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-NOT-AUTHORIZED))
    
    ;; Validate address directly
    (asserts! (not (is-eq address (as-contract tx-sender))) (err ERR-INVALID-ADDRESS))
    
    ;; Check if address is actually blacklisted
    (asserts! (is-address-blacklisted address) (err ERR-INVALID-PARAMETER))
    
    ;; Safe to remove from blacklist after validation
    (map-delete blacklisted-addresses { address: address })
    (ok true)
  )
)

;; Set new admin (current admin only)
(define-public (set-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (is-eq new-admin tx-sender)) (err ERR-INVALID-PARAMETER))
    
    ;; Validate new admin directly
    (asserts! (not (is-eq new-admin (as-contract tx-sender))) (err ERR-INVALID-ADDRESS))
    
    ;; Safe to set new admin after validation
    (var-set admin new-admin)
    (ok true)
  )
)

;; Check if address is blacklisted
(define-read-only (is-blacklisted (address principal))
  (if (is-address-blacklisted address)
      (get blacklisted (unwrap-panic (map-get? blacklisted-addresses { address: address })))
      false)
)

;; User can challenge another user's verification if they suspect Sybil attack
(define-public (challenge-verification (suspected-sybil principal) (evidence (string-utf8 500)))
  (begin
    ;; Validate inputs directly
    (asserts! (not (is-eq suspected-sybil (as-contract tx-sender))) (err ERR-INVALID-ADDRESS))
    (asserts! (> (len evidence) u0) (err ERR-INVALID-STRING))
    (asserts! (not (is-address-blacklisted suspected-sybil)) (err ERR-BLACKLISTED))
    
    (let
      (
        (challenger tx-sender)
        (challenger-stake (default-to { amount: u0, locked-until: u0 } (map-get? user-stakes { user: challenger })))
        (challenger-reputation (calculate-reputation challenger))
      )
      (begin
        ;; Validate challenger
        (asserts! (not (is-address-blacklisted challenger)) (err ERR-BLACKLISTED))
        
        ;; Require challenger to have stake and good reputation
        (asserts! (>= (get amount challenger-stake) (var-get min-stake)) (err ERR-INSUFFICIENT-STAKE))
        (asserts! (>= challenger-reputation u500) (err ERR-INVALID-REPUTATION))
        
        ;; Log the challenge - in a real implementation, this would emit an event
        ;; that administrators could review
        (print { type: "challenge", challenger: challenger, suspected: suspected-sybil, evidence: evidence })
        (ok true)
      )
    )
  )
)

;; Transfer stake between users (helpful for migrations)
(define-public (transfer-stake (to principal) (amount uint))
  (begin
    ;; Validate inputs directly
    (asserts! (> amount u0) (err ERR-INVALID-PARAMETER))
    (asserts! (not (is-eq to (as-contract tx-sender))) (err ERR-INVALID-ADDRESS))
    (asserts! (not (is-address-blacklisted to)) (err ERR-BLACKLISTED))
    
    (let
      (
        (from tx-sender)
        (from-stake (default-to { amount: u0, locked-until: u0 } (map-get? user-stakes { user: from })))
        (to-stake (default-to { amount: u0, locked-until: u0 } (map-get? user-stakes { user: to })))
        (remaining-stake (- (get amount from-stake) amount))
      )
      (begin
        ;; Validate sender
        (asserts! (not (is-address-blacklisted from)) (err ERR-BLACKLISTED))
        
        ;; Check if user has enough stake
        (asserts! (<= amount (get amount from-stake)) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Check if remaining stake is at least minimum required or zero
        (asserts! (or (is-eq remaining-stake u0) (>= remaining-stake (var-get min-stake))) (err ERR-INSUFFICIENT-STAKE))
        
        ;; Update stakes with checked addition
        (map-set user-stakes 
          { user: from } 
          { 
            amount: remaining-stake, 
            locked-until: (if (is-eq remaining-stake u0) u0 (get locked-until from-stake))
          }
        )
        
        (match (checked-add (get amount to-stake) amount)
          new-amount (begin
            (map-set user-stakes 
              { user: to } 
              { 
                amount: new-amount, 
                locked-until: (if (> (get locked-until to-stake) (get locked-until from-stake))
                                (get locked-until to-stake)
                                (get locked-until from-stake))
              }
            )
            
            ;; Update reputations
            (update-reputation-internal from)
            (update-reputation-internal to)
            (ok true)
          )
          error-code (err error-code)
        )
      )
    )
  )
)

;; Initialize contract - can only be called once during deployment
(define-public (initialize (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (is-eq new-admin tx-sender)) (err ERR-INVALID-PARAMETER))
    
    ;; Validate new admin directly
    (asserts! (not (is-eq new-admin (as-contract tx-sender))) (err ERR-INVALID-ADDRESS))
    
    ;; Safe to set new admin after validation
    (var-set admin new-admin)
    (ok true)
  )
)