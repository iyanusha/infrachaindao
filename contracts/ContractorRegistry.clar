;; ContractorRegistry - InfraChainDAO Contractor Management
;; Handles contractor registration, reputation, and job assignment

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-ALREADY-REGISTERED (err u409))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-INSUFFICIENT-STAKE (err u403))
(define-constant ERR-JOB-NOT-FOUND (err u404))
(define-constant ERR-INVALID-SCORE (err u400))

;; Constants
(define-constant MINIMUM-STAKE u1000)  ;; Minimum STX stake required
(define-constant MIN-REPUTATION u50)   ;; Minimum reputation to accept jobs
(define-constant MAX-ACTIVE-JOBS u5)   ;; Maximum concurrent jobs per contractor

;; Data Variables
(define-data-var registry-admin principal tx-sender)

;; Contractor Status
(define-map contractor-profiles
    {address: principal}
    {
        name: (string-ascii 100),
        specialization: (string-ascii 50),
        reputation: uint,
        total-jobs: uint,
        active-jobs: uint,
        staked-amount: uint,
        verified: bool
    }
)

;; Active Job Tracking
(define-map contractor-jobs
    {contractor: principal, job-id: uint}
    {
        start-time: uint,
        asset-id: uint,
        status: (string-ascii 20)
    }
)

;; Reputation History
(define-map reputation-history
    {contractor: principal, job-id: uint}
    {
        old-score: uint,
        new-score: uint,
        reason: (string-ascii 100)
    }
)

;; Public Functions

;; Register as a contractor with initial stake
(define-public (register-contractor 
    (name (string-ascii 100))
    (specialization (string-ascii 50)))
    (let (
        (caller tx-sender)
        (stake-amount MINIMUM-STAKE)
        )
        (asserts! (is-none (get-contractor-profile caller)) ERR-ALREADY-REGISTERED)
        (try! (stx-transfer? stake-amount caller (as-contract tx-sender)))
        (ok (map-set contractor-profiles
            {address: caller}
            {
                name: name,
                specialization: specialization,
                reputation: u100,          ;; Initial reputation
                total-jobs: u0,
                active-jobs: u0,
                staked-amount: stake-amount,
                verified: false
            }))))

;; Accept a maintenance job
(define-public (accept-job (job-id uint))
    (let (
        (contractor tx-sender)
        (profile (unwrap! (get-contractor-profile contractor) ERR-NOT-FOUND))
        )
        (asserts! (>= (get reputation profile) MIN-REPUTATION) ERR-NOT-AUTHORIZED)
        (asserts! (< (get active-jobs profile) MAX-ACTIVE-JOBS) ERR-NOT-AUTHORIZED)
        (try! (update-contractor-jobs contractor job-id))
        (ok (map-set contractor-profiles
            {address: contractor}
            (merge profile 
                  {active-jobs: (+ (get active-jobs profile) u1)})))))

;; Complete a job and update reputation
(define-public (complete-job 
    (job-id uint)
    (quality-score uint))
    (let (
        (contractor tx-sender)
        (profile (unwrap! (get-contractor-profile contractor) ERR-NOT-FOUND))
        (job (unwrap! (get-contractor-job contractor job-id) ERR-JOB-NOT-FOUND))
        (old-reputation (get reputation profile))
        )
        (asserts! (and (>= quality-score u0) (<= quality-score u100)) ERR-INVALID-SCORE)
        (try! (verify-job-completion contractor job-id))
        (let (
            (new-reputation (calculate-new-reputation old-reputation quality-score))
            )
            (map-set reputation-history
                {contractor: contractor, job-id: job-id}
                {
                    old-score: old-reputation,
                    new-score: new-reputation,
                    reason: "Job completion"
                })
            (ok (map-set contractor-profiles
                {address: contractor}
                (merge profile 
                    {
                        reputation: new-reputation,
                        total-jobs: (+ (get total-jobs profile) u1),
                        active-jobs: (- (get active-jobs profile) u1)
                    }))))))

;; Helper Functions

;; Update contractor jobs map
(define-private (update-contractor-jobs (contractor principal) (job-id uint))
    (begin
        (asserts! (is-some (get-contractor-profile contractor)) ERR-NOT-FOUND)
        (ok (map-set contractor-jobs
            {contractor: contractor, job-id: job-id}
            {
                start-time: block-height,
                asset-id: u0,
                status: "accepted"
            }))))

;; Verify job completion
(define-private (verify-job-completion (contractor principal) (job-id uint))
    (let (
        (job (unwrap! (get-contractor-job contractor job-id) ERR-JOB-NOT-FOUND))
        )
        (asserts! (is-eq (get status job) "accepted") ERR-NOT-AUTHORIZED)
        (ok true)))

;; Calculate new reputation score
(define-private (calculate-new-reputation (old-score uint) (quality-score uint))
    (let (
        (weighted-old (mul-down old-score u900))    ;; 90% weight to history
        (weighted-new (mul-down quality-score u100)) ;; 10% weight to new score
        )
        (add-down weighted-old weighted-new)))

;; Arithmetic helpers
(define-private (mul-down (a uint) (b uint))
    (/ (* a b) u1000))

(define-private (add-down (a uint) (b uint))
    (/ (+ (* a u1000) (* b u1000)) u1000))

;; Getters
(define-read-only (get-contractor-profile (address principal))
    (map-get? contractor-profiles {address: address}))

(define-read-only (get-contractor-job (contractor principal) (job-id uint))
    (map-get? contractor-jobs {contractor: contractor, job-id: job-id}))

(define-read-only (get-reputation-change (contractor principal) (job-id uint))
    (map-get? reputation-history {contractor: contractor, job-id: job-id}))
