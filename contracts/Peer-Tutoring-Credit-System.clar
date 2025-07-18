(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-TUTOR (err u101))
(define-constant ERR-INVALID-STUDENT (err u102))
(define-constant ERR-INVALID-SESSION (err u103))
(define-constant ERR-INSUFFICIENT-CREDITS (err u104))
(define-constant ERR-INVALID-RATING (err u105))
(define-constant ERR-SESSION-EXISTS (err u106))

(define-fungible-token tutoring-credit)

(define-data-var contract-owner principal tx-sender)
(define-data-var credit-per-hour uint u10)
(define-data-var min-session-duration uint u30)

(define-map tutors 
    principal 
    {rating: uint, total-sessions: uint, active: bool})

(define-map students
    principal
    {total-sessions: uint, rewards-claimed: uint})

(define-map tutoring-sessions
    uint
    {tutor: principal,
     student: principal,
     duration: uint,
     status: (string-ascii 20),
     rating: uint,
     timestamp: uint})

(define-data-var session-counter uint u0)

(define-public (register-as-tutor)
    (let ((caller tx-sender))
        (asserts! (is-none (get-tutor-info caller)) ERR-INVALID-TUTOR)
        (map-set tutors caller {
            rating: u5,
            total-sessions: u0,
            active: true
        })
        (ok true)))

(define-public (update-tutor-status (status bool))
    (let ((caller tx-sender))
        (asserts! (is-some (get-tutor-info caller)) ERR-INVALID-TUTOR)
        (map-set tutors caller (merge (unwrap-panic (get-tutor-info caller))
            {active: status}))
        (ok true)))

(define-public (start-tutoring-session (student principal) (duration uint))
    (let ((session-id (+ (var-get session-counter) u1))
          (caller tx-sender))
        (asserts! (is-some (get-tutor-info caller)) ERR-INVALID-TUTOR)
        (asserts! (>= duration (var-get min-session-duration)) ERR-INVALID-SESSION)
        (asserts! (not (is-eq caller student)) ERR-INVALID-STUDENT)
        (var-set session-counter session-id)
        (map-set tutoring-sessions session-id {
            tutor: caller,
            student: student,
            duration: duration,
            status: "ongoing",
            rating: u0,
            timestamp: u0
        })
        (ok session-id)))

(define-public (complete-session (session-id uint))
    (let ((session (unwrap! (map-get? tutoring-sessions session-id) ERR-INVALID-SESSION))
          (caller tx-sender))
        (asserts! (is-eq (get student session) caller) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status session) "ongoing") ERR-INVALID-SESSION)
        (map-set tutoring-sessions session-id (merge session {status: "completed"}))
        (try! (mint-session-credits (get tutor session) (get duration session)))
        (ok true)))

(define-public (rate-session (session-id uint) (rating uint))
    (let ((session (unwrap! (map-get? tutoring-sessions session-id) ERR-INVALID-SESSION))
          (caller tx-sender))
        (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
        (asserts! (is-eq (get student session) caller) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status session) "completed") ERR-INVALID-SESSION)
        (map-set tutoring-sessions session-id (merge session {rating: rating}))
        (try! (update-tutor-rating (get tutor session) rating))
        (ok true)))

(define-private (mint-session-credits (tutor principal) (duration uint))
    (let ((credits-to-mint (* (/ duration u60) (var-get credit-per-hour))))
        (ft-mint? tutoring-credit credits-to-mint tutor)))

(define-private (update-tutor-rating (tutor principal) (new-rating uint))
    (let ((tutor-data (unwrap! (get-tutor-info tutor) ERR-INVALID-TUTOR)))
        (map-set tutors tutor (merge tutor-data 
            {rating: (/ (+ (get rating tutor-data) new-rating) u2),
             total-sessions: (+ (get total-sessions tutor-data) u1)}))
        (ok true)))

(define-read-only (get-tutor-info (tutor principal))
    (map-get? tutors tutor))

(define-read-only (get-session-info (session-id uint))
    (map-get? tutoring-sessions session-id))

(define-read-only (get-credit-balance (account principal))
    (ft-get-balance tutoring-credit account))

(define-public (transfer-credits (recipient principal) (amount uint))
    (ft-transfer? tutoring-credit amount tx-sender recipient))
