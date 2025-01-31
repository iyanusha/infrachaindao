;; Predictive Maintenance DAO Core Contract
;; Handles infrastructure management, sensor data integration, and contractor payments

(define-data-var dao-name (string-utf8 100) "PredictiveMaintenanceDAO")
(define-map infrastructure-assets 
    {asset-id: uint}
    {
        name: (string-utf8 100),
        location: (string-utf8 100),
        sensor-threshold: uint,
        maintenance-interval: uint,
        last-maintenance: uint,
        contractor: principal,
        status: (string-utf8 20)
    }
)

(define-map sensor-data
    {asset-id: uint, timestamp: uint}
    {
        reading: uint,
        alert-level: (string-utf8 20)
    }
)

(define-map contractors
    {contractor-address: principal}
    {
        name: (string-utf8 100),
        reputation-score: uint,
        completed-jobs: uint,
        active: bool
    }
)

;; Function to register new infrastructure asset
(define-public (register-asset (asset-id uint) 
                             (name (string-utf8 100))
                             (location (string-utf8 100))
                             (threshold uint)
                             (interval uint))
    (let ((caller tx-sender))
        (if (is-dao-member caller)
            (ok (map-set infrastructure-assets
                {asset-id: asset-id}
                {
                    name: name,
                    location: location,
                    sensor-threshold: threshold,
                    maintenance-interval: interval,
                    last-maintenance: block-height,
                    contractor: caller,
                    status: "active"
                }))
            (err u403))))

;; Function to update sensor data
(define-public (update-sensor-reading (asset-id uint) 
                                    (reading uint))
    (let ((current-time block-height))
        (ok (map-set sensor-data
            {asset-id: asset-id, timestamp: current-time}
            {
                reading: reading,
                alert-level: (get-alert-level reading asset-id)
            }))))

;; Function to trigger maintenance based on sensor data
(define-public (trigger-maintenance (asset-id uint))
    (let ((asset (unwrap-panic (get-asset asset-id)))
          (latest-reading (unwrap-panic (get-latest-reading asset-id))))
        (if (> (get reading latest-reading) (get sensor-threshold asset))
            (ok (initiate-maintenance asset-id))
            (err u404))))

;; Function to process contractor payment
(define-public (process-payment (asset-id uint) 
                              (amount uint))
    (let ((contractor (get-asset-contractor asset-id)))
        (if (and 
                (is-work-completed asset-id)
                (is-payment-approved asset-id))
            (ok (transfer-stx amount contractor))
            (err u403))))
            