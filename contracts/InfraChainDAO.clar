;; InfraChainDAO - IoT-Driven Predictive Maintenance
;; Manages infrastructure maintenance through IoT sensor data and automated payments

;; Constants and Error Codes
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-ASSET-NOT-FOUND (err u404))
(define-constant ERR-INVALID-DATA (err u400))
(define-constant ERR-ALREADY-EXISTS (err u409))

;; Asset and Job Status Constants
(define-constant ACTIVE "active")
(define-constant MAINTENANCE "maintenance")
(define-constant COMPLETED "completed")
(define-constant PENDING "pending")

;; Data Variables
(define-data-var dao-admin principal tx-sender)
(define-data-var current-job-id uint u0)

;; IoT Sensor Thresholds
(define-data-var critical-threshold uint u80)  ;; Percentage threshold for immediate maintenance
(define-data-var warning-threshold uint u60)   ;; Percentage threshold for warning
(define-data-var maintenance-interval uint u1000) ;; Blocks between routine checks

;; Maps for Infrastructure Management
(define-map infrastructure-assets 
    {id: uint} 
    {
        name: (string-ascii 100),
        location: (string-ascii 100),
        sensor-id: (buff 32),
        last-reading: uint,
        last-maintenance: uint,
        status: (string-ascii 20),
        maintenance-count: uint
    }
)

;; IoT Sensor Data Storage
(define-map sensor-readings
    {asset-id: uint, timestamp: uint}
    {
        reading: uint,         ;; Current sensor reading (percentage of optimal)
        temperature: uint,     ;; Temperature reading if applicable
        vibration: uint,      ;; Vibration reading if applicable
        alert-level: (string-ascii 20)
    }
)

;; Maintenance Jobs
(define-map maintenance-jobs
    {job-id: uint}
    {
        asset-id: uint,
        contractor: principal,
        sensor-reading: uint,
        start-time: uint,
        completion-time: uint,
        status: (string-ascii 20),
        payment-amount: uint
    }
)

;; Core Infrastructure Management Functions

;; Register new infrastructure asset with IoT sensor
(define-public (register-asset 
    (asset-id uint)
    (name (string-ascii 100))
    (location (string-ascii 100))
    (sensor-id (buff 32)))
    (begin
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (ok (map-set infrastructure-assets
            {id: asset-id}
            {
                name: name,
                location: location,
                sensor-id: sensor-id,
                last-reading: u0,
                last-maintenance: block-height,
                status: ACTIVE,
                maintenance-count: u0
            }))))

;; Submit IoT sensor reading and trigger maintenance if needed
(define-public (submit-sensor-reading
    (asset-id uint)
    (reading uint)
    (temperature uint)
    (vibration uint))
    (let (
        (asset (unwrap! (get-asset asset-id) ERR-ASSET-NOT-FOUND))
        (current-time block-height)
        )
        (begin
            ;; Store sensor reading
            (map-set sensor-readings
                {asset-id: asset-id, timestamp: current-time}
                {
                    reading: reading,
                    temperature: temperature,
                    vibration: vibration,
                    alert-level: (get-alert-level reading)
                })
            ;; Check if maintenance is needed and return job-id or success
            (if (>= reading (var-get critical-threshold))
                (trigger-maintenance asset-id reading)
                (ok u0)))))  ;; Return 0 when no maintenance needed

;; Trigger maintenance based on sensor data
(define-public (trigger-maintenance (asset-id uint) (reading uint))
    (let (
        (job-id (+ (var-get current-job-id) u1))
        )
        (begin
            (map-set maintenance-jobs
                {job-id: job-id}
                {
                    asset-id: asset-id,
                    contractor: (var-get dao-admin),
                    sensor-reading: reading,
                    start-time: block-height,
                    completion-time: u0,
                    status: PENDING,
                    payment-amount: u0
                })
            (var-set current-job-id job-id)
            (ok job-id))))

;; Helper Functions
(define-private (get-alert-level (reading uint))
    (if (>= reading (var-get critical-threshold))
        "critical"
        (if (>= reading (var-get warning-threshold))
            "warning"
            "normal")))

;; Getters
(define-read-only (get-asset (asset-id uint))
    (map-get? infrastructure-assets {id: asset-id}))

(define-read-only (get-latest-reading (asset-id uint))
    (map-get? sensor-readings 
        {asset-id: asset-id, timestamp: block-height}))

(define-read-only (get-maintenance-job (job-id uint))
    (map-get? maintenance-jobs {job-id: job-id}))
