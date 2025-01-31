;; InfraChainDAO - Core Smart Contract Architecture

;; Constants and Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-ASSET-NOT-FOUND (err u404))
(define-constant ERR-INVALID-DATA (err u400))

;; Data Variables
(define-data-var dao-admin principal tx-sender)
(define-data-var min-reputation uint u50)
(define-data-var maintenance-threshold uint u80)

;; Data Maps
(define-map assets 
    {id: uint} 
    {
        name: (string-utf8 100),
        location: (string-utf8 100),
        sensor-id: (buff 32),
        threshold: uint,
        last-maintenance: uint,
        status: (string-utf8 20),
        owner: principal
    }
)

(define-map sensor-readings
    {asset-id: uint, timestamp: uint}
    {
        reading: uint,
        verified: bool,
        reported-by: principal
    }
)

(define-map contractors
    {address: principal}
    {
        name: (string-utf8 100),
        reputation: uint,
        total-jobs: uint,
        active: bool,
        stake: uint
    }
)

(define-map maintenance-jobs
    {job-id: uint}
    {
        asset-id: uint,
        contractor: principal,
        start-time: uint,
        end-time: uint,
        status: (string-utf8 20),
        payment-amount: uint
    }
)

;; Administrative Functions
(define-public (set-dao-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (ok (var-set dao-admin new-admin))))

;; Asset Management
(define-public (register-asset 
    (asset-id uint)
    (name (string-utf8 100))
    (location (string-utf8 100))
    (sensor-id (buff 32))
    (threshold uint))
    (let ((caller tx-sender))
        (asserts! (is-eq caller (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (ok (map-set assets
            {id: asset-id}
            {
                name: name,
                location: location,
                sensor-id: sensor-id,
                threshold: threshold,
                last-maintenance: block-height,
                status: "active",
                owner: caller
            }))))

;; Sensor Data Management
(define-public (submit-sensor-reading
    (asset-id uint)
    (reading uint))
    (let ((caller tx-sender))
        (asserts! (is-valid-sensor caller asset-id) ERR-NOT-AUTHORIZED)
        (ok (map-set sensor-readings
            {asset-id: asset-id, timestamp: block-height}
            {
                reading: reading,
                verified: false,
                reported-by: caller
            }))))

;; Maintenance Management
(define-public (initiate-maintenance
    (asset-id uint)
    (contractor principal))
    (let ((asset (unwrap-panic (get-asset asset-id)))
          (contractor-data (unwrap-panic (get-contractor contractor))))
        (asserts! (>= (get reputation contractor-data) (var-get min-reputation)) 
                 ERR-NOT-AUTHORIZED)
        (ok (create-maintenance-job asset-id contractor))))

;; Payment Processing
(define-public (process-payment
    (job-id uint))
    (let ((job (unwrap-panic (get-maintenance-job job-id))))
        (asserts! (is-job-complete job) ERR-INVALID-DATA)
        (asserts! (verify-job-completion job-id) ERR-INVALID-DATA)
        (ok (stx-transfer? 
            (get payment-amount job)
            tx-sender
            (get contractor job)))))

;; Helper Functions
(define-private (is-valid-sensor (sensor principal) (asset-id uint))
    (let ((asset (unwrap-panic (get-asset asset-id))))
        (is-eq sensor (get owner asset))))

(define-private (is-job-complete (job {
        asset-id: uint,
        contractor: principal,
        start-time: uint,
        end-time: uint,
        status: (string-utf8 20),
        payment-amount: uint
    }))
    (and 
        (is-eq (get status job) "completed")
        (> (get end-time job) (get start-time job))
        (> (get payment-amount job) u0)))

(define-private (verify-job-completion (job-id uint))
    (let ((job (unwrap-panic (get-maintenance-job job-id))))
        (and
            (is-eq (get status job) "completed")
            (>= block-height (+ (get start-time job) u100))  ;; Minimum time check
            (< block-height (+ (get end-time job) u10000))   ;; Maximum time check
            (> (get payment-amount job) u0))))

(define-private (create-maintenance-job (asset-id uint) (contractor principal))
    (let ((job-id (+ (var-get current-job-id) u1)))
        (map-set maintenance-jobs
            {job-id: job-id}
            {
                asset-id: asset-id,
                contractor: contractor,
                start-time: block-height,
                end-time: u0,
                status: "initiated",
                payment-amount: u0
            })
        (var-set current-job-id job-id)
        job-id))

;; Getters
(define-read-only (get-asset (asset-id uint))
    (map-get? assets {id: asset-id}))

(define-read-only (get-contractor (address principal))
    (map-get? contractors {address: address}))

(define-read-only (get-maintenance-job (job-id uint))
    (map-get? maintenance-jobs {job-id: job-id}))

;; Initialize contract
(define-data-var current-job-id uint u0)
