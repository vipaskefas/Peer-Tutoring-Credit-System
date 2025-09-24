(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-TUTOR (err u101))
(define-constant ERR-INVALID-STUDENT (err u102))
(define-constant ERR-INVALID-SESSION (err u103))
(define-constant ERR-INSUFFICIENT-CREDITS (err u104))
(define-constant ERR-INVALID-RATING (err u105))
(define-constant ERR-SESSION-EXISTS (err u106))
(define-constant ERR-DISPUTE-EXISTS (err u107))
(define-constant ERR-DISPUTE-NOT-FOUND (err u108))
(define-constant ERR-DISPUTE-CLOSED (err u109))
(define-constant ERR-ALREADY-VOTED (err u110))
(define-constant ERR-VOTE-PERIOD-ENDED (err u111))
(define-constant ERR-ACHIEVEMENT-NOT-FOUND (err u112))
(define-constant ERR-ACHIEVEMENT-ALREADY-EARNED (err u113))

(define-fungible-token tutoring-credit)

(define-data-var contract-owner principal tx-sender)
(define-data-var credit-per-hour uint u10)
(define-data-var min-session-duration uint u30)

(begin
    (var-set achievement-counter u1)
    (map-set achievements u1 {
        name: "First Steps",
        description: "Complete your first tutoring session",
        reward-credits: u5,
        requirement-type: "sessions",
        requirement-value: u1
    })
    (var-set achievement-counter u2)
    (map-set achievements u2 {
        name: "Mentor",
        description: "Complete 10 tutoring sessions",
        reward-credits: u25,
        requirement-type: "sessions",
        requirement-value: u10
    })
    (var-set achievement-counter u3)
    (map-set achievements u3 {
        name: "Excellence",
        description: "Maintain a 4.5+ rating",
        reward-credits: u15,
        requirement-type: "rating",
        requirement-value: u450
    })
    (var-set achievement-counter u4)
    (map-set achievements u4 {
        name: "Veteran",
        description: "Complete 50 tutoring sessions",
        reward-credits: u100,
        requirement-type: "sessions",
        requirement-value: u50
    }))

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
(define-data-var dispute-counter uint u0)
(define-data-var dispute-voting-period uint u1440)

(define-map achievements
    uint
    {name: (string-ascii 50),
     description: (string-ascii 200),
     reward-credits: uint,
     requirement-type: (string-ascii 20),
     requirement-value: uint})

(define-map user-achievements
    {user: principal, achievement-id: uint}
    {earned-at: uint, claimed: bool})

(define-data-var achievement-counter uint u0)

(define-map session-disputes
    uint
    {session-id: uint,
     disputer: principal,
     reason: (string-ascii 100),
     status: (string-ascii 20),
     votes-for: uint,
     votes-against: uint,
     expiry-block: uint})

(define-map dispute-votes
    {dispute-id: uint, voter: principal}
    bool)

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
    (let ((tutor-data (unwrap! (get-tutor-info tutor) ERR-INVALID-TUTOR))
          (new-session-count (+ (get total-sessions tutor-data) u1))
          (new-avg-rating (/ (+ (* (get rating tutor-data) (get total-sessions tutor-data)) new-rating) new-session-count)))
        (map-set tutors tutor (merge tutor-data 
            {rating: new-avg-rating,
             total-sessions: new-session-count}))
        (try! (check-and-award-achievements tutor new-session-count new-avg-rating))
        (ok true)))

(define-read-only (get-tutor-info (tutor principal))
    (map-get? tutors tutor))

(define-read-only (get-session-info (session-id uint))
    (map-get? tutoring-sessions session-id))

(define-read-only (get-credit-balance (account principal))
    (ft-get-balance tutoring-credit account))

(define-public (transfer-credits (recipient principal) (amount uint))
    (ft-transfer? tutoring-credit amount tx-sender recipient))

(define-public (create-dispute (session-id uint) (reason (string-ascii 100)))
    (let ((session (unwrap! (map-get? tutoring-sessions session-id) ERR-INVALID-SESSION))
          (dispute-id (+ (var-get dispute-counter) u1))
          (caller tx-sender))
        (asserts! (is-eq (get status session) "completed") ERR-INVALID-SESSION)
        (asserts! (or (is-eq (get tutor session) caller) (is-eq (get student session) caller)) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (get match (get-dispute-by-session session-id))) ERR-DISPUTE-EXISTS)
        (var-set dispute-counter dispute-id)
        (map-set session-disputes dispute-id {
            session-id: session-id,
            disputer: caller,
            reason: reason,
            status: "open",
            votes-for: u0,
            votes-against: u0,
            expiry-block: (+ stacks-block-height (var-get dispute-voting-period))
        })
        (ok dispute-id)))

(define-public (vote-on-dispute (dispute-id uint) (vote-for bool))
    (let ((dispute (unwrap! (map-get? session-disputes dispute-id) ERR-DISPUTE-NOT-FOUND))
          (caller tx-sender)
          (vote-key {dispute-id: dispute-id, voter: caller}))
        (asserts! (is-eq (get status dispute) "open") ERR-DISPUTE-CLOSED)
        (asserts! (< stacks-block-height (get expiry-block dispute)) ERR-VOTE-PERIOD-ENDED)
        (asserts! (is-none (map-get? dispute-votes vote-key)) ERR-ALREADY-VOTED)
        (asserts! (is-some (get-tutor-info caller)) ERR-INVALID-TUTOR)
        (map-set dispute-votes vote-key vote-for)
        (if vote-for
            (map-set session-disputes dispute-id (merge dispute 
                {votes-for: (+ (get votes-for dispute) u1)}))
            (map-set session-disputes dispute-id (merge dispute 
                {votes-against: (+ (get votes-against dispute) u1)})))
        (ok true)))

(define-public (resolve-dispute (dispute-id uint))
    (let ((dispute (unwrap! (map-get? session-disputes dispute-id) ERR-DISPUTE-NOT-FOUND)))
        (asserts! (is-eq (get status dispute) "open") ERR-DISPUTE-CLOSED)
        (asserts! (>= stacks-block-height (get expiry-block dispute)) ERR-VOTE-PERIOD-ENDED)
        (if (> (get votes-for dispute) (get votes-against dispute))
            (begin
                (map-set session-disputes dispute-id (merge dispute {status: "resolved-favor"}))
                (try! (reverse-session-credits (get session-id dispute))))
            (map-set session-disputes dispute-id (merge dispute {status: "resolved-against"})))
        (ok true)))

(define-private (reverse-session-credits (session-id uint))
    (let ((session (unwrap! (map-get? tutoring-sessions session-id) ERR-INVALID-SESSION)))
        (let ((credits-to-burn (* (/ (get duration session) u60) (var-get credit-per-hour))))
            (ft-burn? tutoring-credit credits-to-burn (get tutor session)))))

(define-private (get-dispute-by-session (target-session-id uint))
    (fold check-dispute-match (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) 
        {target: target-session-id, match: none}))

(define-private (check-dispute-match (dispute-id uint) (state {target: uint, match: (optional uint)}))
    (if (is-some (get match state))
        state
        (match (map-get? session-disputes dispute-id)
            dispute (if (is-eq (get session-id dispute) (get target state)) 
                       {target: (get target state), match: (some dispute-id)} 
                       state)
            state)))

(define-read-only (get-dispute-info (dispute-id uint))
    (map-get? session-disputes dispute-id))

(define-read-only (get-user-vote (dispute-id uint) (voter principal))
    (map-get? dispute-votes {dispute-id: dispute-id, voter: voter}))

(define-private (check-and-award-achievements (user principal) (session-count uint) (rating uint))
    (begin
        (try! (check-session-achievements user session-count))
        (try! (check-rating-achievements user rating))
        (ok true)))

(define-private (check-session-achievements (user principal) (session-count uint))
    (let ((achievement-1 (map-get? achievements u1))
          (achievement-2 (map-get? achievements u2))
          (achievement-4 (map-get? achievements u4)))
        (begin
            (if (and (is-some achievement-1) (>= session-count (get requirement-value (unwrap-panic achievement-1))))
                (try! (award-achievement user u1)) true)
            (if (and (is-some achievement-2) (>= session-count (get requirement-value (unwrap-panic achievement-2))))
                (try! (award-achievement user u2)) true)
            (if (and (is-some achievement-4) (>= session-count (get requirement-value (unwrap-panic achievement-4))))
                (try! (award-achievement user u4)) true)
            (ok true))))

(define-private (check-rating-achievements (user principal) (rating uint))
    (let ((achievement-3 (map-get? achievements u3)))
        (begin
            (if (and (is-some achievement-3) (>= rating (get requirement-value (unwrap-panic achievement-3))))
                (try! (award-achievement user u3)) true)
            (ok true))))

(define-private (award-achievement (user principal) (achievement-id uint))
    (let ((achievement (unwrap! (map-get? achievements achievement-id) ERR-ACHIEVEMENT-NOT-FOUND))
          (user-achievement-key {user: user, achievement-id: achievement-id}))
        (asserts! (is-none (map-get? user-achievements user-achievement-key)) ERR-ACHIEVEMENT-ALREADY-EARNED)
        (map-set user-achievements user-achievement-key {
            earned-at: stacks-block-height,
            claimed: false
        })
        (ft-mint? tutoring-credit (get reward-credits achievement) user)))

(define-public (claim-achievement (achievement-id uint))
    (let ((user-achievement-key {user: tx-sender, achievement-id: achievement-id})
          (user-achievement (unwrap! (map-get? user-achievements user-achievement-key) ERR-ACHIEVEMENT-NOT-FOUND)))
        (asserts! (not (get claimed user-achievement)) ERR-ACHIEVEMENT-ALREADY-EARNED)
        (map-set user-achievements user-achievement-key (merge user-achievement {claimed: true}))
        (ok true)))

(define-read-only (get-achievement-info (achievement-id uint))
    (map-get? achievements achievement-id))

(define-read-only (get-user-achievement (user principal) (achievement-id uint))
    (map-get? user-achievements {user: user, achievement-id: achievement-id}))

(define-read-only (has-achievement (user principal) (achievement-id uint))
    (is-some (map-get? user-achievements {user: user, achievement-id: achievement-id})))
