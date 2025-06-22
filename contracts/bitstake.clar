;; Title: BitStake Protocol - Decentralized Bitcoin-Native Staking & Governance
;;
;; Summary: A sophisticated liquid staking protocol that enables STX holders to earn
;; yield while participating in decentralized governance, built for Bitcoin's L2 ecosystem
;;
;; Description: 
;; BitStake Protocol revolutionizes Bitcoin Layer 2 staking by providing a trustless,
;; tiered staking system that rewards long-term commitment while maintaining liquidity.
;; Users can stake STX tokens to earn BITSTAKE governance tokens, participate in 
;; protocol decisions, and unlock premium features based on their tier level.
;;
;; Key Features:
;; - Multi-tier staking system with enhanced rewards for larger stakes
;; - Time-locked staking bonuses for committed participants  
;; - Decentralized governance with voting power based on stake size
;; - Emergency safeguards and contract pause functionality
;; - Bitcoin-native design optimized for Stacks ecosystem

;; TOKEN DEFINITION

(define-fungible-token BITSTAKE-TOKEN u0)

;; CONSTANTS & ERROR CODES

;; Contract Authority
(define-constant CONTRACT-OWNER tx-sender)

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-PROTOCOL (err u1001))
(define-constant ERR-INVALID-AMOUNT (err u1002))
(define-constant ERR-INSUFFICIENT-STX (err u1003))
(define-constant ERR-COOLDOWN-ACTIVE (err u1004))
(define-constant ERR-NO-STAKE (err u1005))
(define-constant ERR-BELOW-MINIMUM (err u1006))
(define-constant ERR-PAUSED (err u1007))

;; STATE VARIABLES  

;; Contract Control States
(define-data-var contract-paused bool false)
(define-data-var emergency-mode bool false)
(define-data-var stx-pool uint u0)

;; Staking Configuration Parameters
(define-data-var base-reward-rate uint u500) ;; 5% annual base rate (100 = 1%)
(define-data-var bonus-rate uint u100) ;; 1% additional bonus for time-locks
(define-data-var minimum-stake uint u1000000) ;; 1 STX minimum stake (1,000,000 uSTX)
(define-data-var cooldown-period uint u1440) ;; 24 hour unstaking cooldown (blocks)
(define-data-var proposal-count uint u0) ;; Total governance proposals created

;; DATA STRUCTURES

;; Governance Proposal Structure
(define-map Proposals
  { proposal-id: uint }
  {
    creator: principal,
    description: (string-utf8 256),
    start-block: uint,
    end-block: uint,
    executed: bool,
    votes-for: uint,
    votes-against: uint,
    minimum-votes: uint,
  }
)

;; User Account Comprehensive Data
(define-map UserPositions
  principal
  {
    total-collateral: uint,
    total-debt: uint,
    health-factor: uint,
    last-updated: uint,
    stx-staked: uint,
    analytics-tokens: uint,
    voting-power: uint,
    tier-level: uint,
    rewards-multiplier: uint,
  }
)

;; Individual Staking Position Details
(define-map StakingPositions
  principal
  {
    amount: uint,
    start-block: uint,
    last-claim: uint,
    lock-period: uint,
    cooldown-start: (optional uint),
    accumulated-rewards: uint,
  }
)

;; Tier System Configuration Matrix
(define-map TierLevels
  uint
  {
    minimum-stake: uint,
    reward-multiplier: uint,
    features-enabled: (list 10 bool),
  }
)

;; PUBLIC FUNCTIONS  

;; CONTRACT INITIALIZATION  

(define-public (initialize-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    ;; Configure Bronze Tier (Entry Level)
    (map-set TierLevels u1 {
      minimum-stake: u1000000, ;; 1 STX minimum
      reward-multiplier: u100, ;; 1x base rewards
      features-enabled: (list true false false false false false false false false false),
    })
    ;; Configure Silver Tier (Premium Access)
    (map-set TierLevels u2 {
      minimum-stake: u5000000, ;; 5 STX minimum
      reward-multiplier: u150, ;; 1.5x rewards boost
      features-enabled: (list true true true false false false false false false false),
    })
    ;; Configure Gold Tier (Elite Benefits)
    (map-set TierLevels u3 {
      minimum-stake: u10000000, ;; 10 STX minimum
      reward-multiplier: u200, ;; 2x rewards multiplier
      features-enabled: (list true true true true true false false false false false),
    })
    (ok true)
  )
)

;; STAKING OPERATIONS   

(define-public (stake-stx
    (amount uint)
    (lock-period uint)
  )
  (let ((current-position (default-to {
      total-collateral: u0,
      total-debt: u0,
      health-factor: u0,
      last-updated: u0,
      stx-staked: u0,
      analytics-tokens: u0,
      voting-power: u0,
      tier-level: u0,
      rewards-multiplier: u100,
    }
      (map-get? UserPositions tx-sender)
    )))
    ;; Validation Checks
    (asserts! (is-valid-lock-period lock-period) ERR-INVALID-PROTOCOL)
    (asserts! (not (var-get contract-paused)) ERR-PAUSED)
    (asserts! (>= amount (var-get minimum-stake)) ERR-BELOW-MINIMUM)
    ;; Transfer STX to Contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let (
        (new-total-stake (+ (get stx-staked current-position) amount))
        (tier-info (get-tier-info new-total-stake))
        (lock-multiplier (calculate-lock-multiplier lock-period))
      )
      ;; Create Staking Position
      (map-set StakingPositions tx-sender {
        amount: amount,
        start-block: stacks-block-height,
        last-claim: stacks-block-height,
        lock-period: lock-period,
        cooldown-start: none,
        accumulated-rewards: u0,
      })
      ;; Update User Position
      (map-set UserPositions tx-sender
        (merge current-position {
          stx-staked: new-total-stake,
          tier-level: (get tier-level tier-info),
          rewards-multiplier: (* (get reward-multiplier tier-info) lock-multiplier),
          voting-power: new-total-stake,
        })
      )
      ;; Update Contract State
      (var-set stx-pool (+ (var-get stx-pool) amount))
      (ok true)
    )
  )
)

;; UNSTAKING OPERATIONS 

(define-public (initiate-unstake (amount uint))
  (let (
      (staking-position (unwrap! (map-get? StakingPositions tx-sender) ERR-NO-STAKE))
      (current-amount (get amount staking-position))
    )
    ;; Validation Checks
    (asserts! (>= current-amount amount) ERR-INSUFFICIENT-STX)
    (asserts! (is-none (get cooldown-start staking-position)) ERR-COOLDOWN-ACTIVE)
    ;; Initiate Cooldown Period
    (map-set StakingPositions tx-sender
      (merge staking-position { cooldown-start: (some stacks-block-height) })
    )
    (ok true)
  )
)

(define-public (complete-unstake)
  (let (
      (staking-position (unwrap! (map-get? StakingPositions tx-sender) ERR-NO-STAKE))
      (cooldown-start (unwrap! (get cooldown-start staking-position) ERR-NOT-AUTHORIZED))
    )
    ;; Verify Cooldown Period Completion
    (asserts!
      (>= (- stacks-block-height cooldown-start) (var-get cooldown-period))
      ERR-COOLDOWN-ACTIVE
    )
    ;; Return Staked STX to User
    (try! (as-contract (stx-transfer? (get amount staking-position) tx-sender tx-sender)))
    ;; Clean Up Staking Position
    (map-delete StakingPositions tx-sender)
    ;; Update Contract STX Pool
    (var-set stx-pool (- (var-get stx-pool) (get amount staking-position)))
    (ok true)
  )
)

;; GOVERNANCE OPERATIONS 

(define-public (create-proposal
    (description (string-utf8 256))
    (voting-period uint)
  )
  (let (
      (user-position (unwrap! (map-get? UserPositions tx-sender) ERR-NOT-AUTHORIZED))
      (proposal-id (+ (var-get proposal-count) u1))
    )
    ;; Validation Checks
    (asserts! (>= (get voting-power user-position) u1000000) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-description description) ERR-INVALID-PROTOCOL)
    (asserts! (is-valid-voting-period voting-period) ERR-INVALID-PROTOCOL)
    ;; Create New Proposal
    (map-set Proposals { proposal-id: proposal-id } {
      creator: tx-sender,
      description: description,
      start-block: stacks-block-height,
      end-block: (+ stacks-block-height voting-period),
      executed: false,
      votes-for: u0,
      votes-against: u0,
      minimum-votes: u1000000,
    })
    ;; Update Proposal Counter
    (var-set proposal-count proposal-id)
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal
    (proposal-id uint)
    (vote-for bool)
  )
  (let (
      (proposal (unwrap! (map-get? Proposals { proposal-id: proposal-id })
        ERR-INVALID-PROTOCOL
      ))
      (user-position (unwrap! (map-get? UserPositions tx-sender) ERR-NOT-AUTHORIZED))
      (voting-power (get voting-power user-position))
      (max-proposal-id (var-get proposal-count))
    )
    ;; Validation Checks
    (asserts! (< stacks-block-height (get end-block proposal)) ERR-NOT-AUTHORIZED)
    (asserts! (and (> proposal-id u0) (<= proposal-id max-proposal-id))
      ERR-INVALID-PROTOCOL
    )
    ;; Record Vote
    (map-set Proposals { proposal-id: proposal-id }
      (merge proposal {
        votes-for: (if vote-for
          (+ (get votes-for proposal) voting-power)
          (get votes-for proposal)
        ),
        votes-against: (if vote-for
          (get votes-against proposal)
          (+ (get votes-against proposal) voting-power)
        ),
      })
    )
    (ok true)
  )
)

;; CONTRACT ADMINISTRATION 

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (resume-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

;; READ-ONLY FUNCTIONS 

(define-read-only (get-contract-owner)
  (ok CONTRACT-OWNER)
)

(define-read-only (get-stx-pool)
  (ok (var-get stx-pool))
)

(define-read-only (get-proposal-count)
  (ok (var-get proposal-count))
)

(define-read-only (get-user-position (user principal))
  (ok (map-get? UserPositions user))
)

(define-read-only (get-staking-position (user principal))
  (ok (map-get? StakingPositions user))
)

(define-read-only (get-proposal-details (proposal-id uint))
  (ok (map-get? Proposals { proposal-id: proposal-id }))
)

(define-read-only (is-contract-paused)
  (ok (var-get contract-paused))
)

;; PRIVATE FUNCTIONS 

;; TIER CALCULATION   

(define-private (get-tier-info (stake-amount uint))
  (if (>= stake-amount u10000000) ;; Gold Tier: 10+ STX
    {
      tier-level: u3,
      reward-multiplier: u200,
    }
    (if (>= stake-amount u5000000) ;; Silver Tier: 5-9.99 STX
      {
        tier-level: u2,
        reward-multiplier: u150,
      }
      {
        tier-level: u1,
        reward-multiplier: u100,
      } ;; Bronze Tier: 1-4.99 STX
    )
  )
)