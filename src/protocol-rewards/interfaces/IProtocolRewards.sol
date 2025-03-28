// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

/**
 * @title IProtocolRewards
 * @notice The interface for deposits & withdrawals for Protocol Rewards
 */
interface IProtocolRewards {
    /**
     * @notice Rewards Deposit Event
     * @param builderReferral Builder referral
     * @param purchaseReferral Purchase referral user
     * @param revolution Revolution recipient
     * @param from The caller of the deposit
     * @param builderReferralReward Builder referral reward
     * @param purchaseReferralReward Purchase referral amount
     * @param revolutionReward Revolution amount
     */
    event RewardsDeposit(
        address indexed builderReferral,
        address indexed purchaseReferral,
        address revolution,
        address from,
        uint256 builderReferralReward,
        uint256 purchaseReferralReward,
        uint256 revolutionReward
    );

    /**
     * @notice Deposit Event
     * @param from From user
     * @param to To user (within contract)
     * @param reason Optional bytes4 reason for indexing
     * @param amount Amount of deposit
     * @param comment Optional user comment
     */
    event Deposit(address indexed from, address indexed to, bytes4 indexed reason, uint256 amount, string comment);

    /**
     * @notice Withdraw Event
     * @param from From user
     * @param to To user (within contract)
     * @param amount Amount of deposit
     */
    event Withdraw(address indexed from, address indexed to, uint256 amount);

    /** @notice Cannot send to address zero */
    error ADDRESS_ZERO();

    /** @notice Function argument array length mismatch */
    error ARRAY_LENGTH_MISMATCH();

    /** @notice Invalid deposit */
    error INVALID_DEPOSIT();

    /** @notice Invalid signature for deposit */
    error INVALID_SIGNATURE();

    /** @notice Invalid withdraw */
    error INVALID_WITHDRAW();

    /** @notice Signature for withdraw is too old and has expired */
    error SIGNATURE_DEADLINE_EXPIRED();

    /** @notice Low-level ETH transfer has failed */
    error TRANSFER_FAILED();

    /**
     * @notice Generic function to deposit ETH for a recipient, with an optional comment
     * @param to Address to deposit to
     * @param why Reason system reason for deposit (used for indexing)
     * @param comment Optional comment as reason for deposit
     */
    function deposit(address to, bytes4 why, string calldata comment) external payable;

    /**
     * @notice Generic function to deposit ETH for multiple recipients, with an optional comment
     * @param recipients recipients to send the amount to, array aligns with amounts
     * @param amounts amounts to send to each recipient, array aligns with recipients
     * @param reasons optional bytes4 hash for indexing
     * @param comment Optional comment to include with purchase
     */
    function depositBatch(
        address[] calldata recipients,
        uint256[] calldata amounts,
        bytes4[] calldata reasons,
        string calldata comment
    ) external payable;

    /**
     * @notice Used by Revolution token contracts to deposit protocol rewards
     * @param builderReferral Builder referral
     * @param builderReferralReward Builder referral reward
     * @param purchaseReferral Purchase referral user
     * @param purchaseReferralReward Purchase referral amount
     * @param revolution Revolution recipient
     * @param revolutionReward Revolution amount
     */
    function depositRewards(
        address builderReferral,
        uint256 builderReferralReward,
        address purchaseReferral,
        uint256 purchaseReferralReward,
        address revolution,
        uint256 revolutionReward
    ) external payable;

    /**
     * @notice Withdraw protocol rewards
     * @param to Withdraws from msg.sender to this address
     * @param amount amount to withdraw
     */
    function withdraw(address to, uint256 amount) external;

    /**
     * @notice Execute a withdraw of protocol rewards via signature
     * @param from Withdraw from this address
     * @param to Withdraw to this address
     * @param amount Amount to withdraw
     * @param deadline Deadline for the signature to be valid
     * @param v V component of signature
     * @param r R component of signature
     * @param s S component of signature
     */
    function withdrawWithSig(
        address from,
        address to,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
