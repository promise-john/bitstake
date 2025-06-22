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