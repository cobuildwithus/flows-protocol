// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IJBTerminal } from "../interfaces/external/juicebox/IJBTerminal.sol";
import { IJBDirectory } from "../interfaces/external/juicebox/IJBDirectory.sol";
import { JBAccountingContext } from "../interfaces/external/juicebox/structs/JBAccountingContext.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/** @notice A basic terminal implementation for Flows integration with Juicebox */
contract FlowsTerminal is IJBTerminal, UUPSUpgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    //*********************************************************************//
    // -------------------------- constants ----------------------------- //
    //*********************************************************************//

    address public constant ETH = 0x000000000000000000000000000000000000EEEe;

    IJBDirectory public constant DIRECTORY = IJBDirectory(0x0bC9F153DEe4d3D474ce0903775b9b2AAae9AA41);

    uint256 public constant FLOW_PROJECT_ID = 99;

    address public constant FLOWS_TOKEN = 0xa66c1FAEFd257DbE9Da50e56C7816B5710C9E2A1;

    //*********************************************************************//
    // -------------------------- errors ----------------------------- //
    //*********************************************************************//

    error TERMINAL_NOT_FOUND();
    error NO_VALUE();
    error INCORRECT_VALUE();
    error NO_FLOWS_ETH_TERMINAL();
    error NO_DEST_TERMINAL();

    //*********************************************************************//
    // -------------------------- constructors ---------------------------- //
    //*********************************************************************//

    constructor() payable {
        _disableInitializers();
    }

    /** @notice Initializes the FlowsTerminal contract
     * @param _owner The address of the owner of the contract
     */
    function initialize(address _owner) external initializer {
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __ReentrancyGuard_init();

        _transferOwnership(_owner);
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /** @notice Indicates if this contract adheres to the specified interface.
     * @dev See {IERC165-supportsInterface}.
     * @param interfaceId The ID of the interface to check for adherance to.
     * @return A flag indicating if the provided interface ID is supported.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IJBTerminal).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /** @notice Make a payment to a project.
     * @dev This is a stub implementation that always returns 0. In a full implementation,
     * this would process the payment, potentially mint tokens for the beneficiary, and handle
     * any associated hooks or metadata processing.
     * @param projectId The ID of the project being paid.
     * @param token The address of the token being paid with.
     * @param amount The amount of tokens being paid.
     * @param beneficiary The address that will receive any tokens minted from this payment.
     * @param minReturnedTokens The minimum number of tokens expected to be minted for the beneficiary.
     * @param memo A memo to include with the payment.
     * @param metadata Additional metadata for the payment.
     * @return beneficiaryTokenCount The number of tokens minted for the beneficiary.
     */
    function pay(
        uint256 projectId,
        address token,
        uint256 amount,
        address beneficiary,
        uint256 minReturnedTokens,
        string calldata memo,
        bytes calldata metadata
    ) external payable override nonReentrant returns (uint256 beneficiaryTokenCount) {
        if (msg.value == 0) revert NO_VALUE();
        if (msg.value != amount) revert INCORRECT_VALUE();

        // Get the primary terminal for the project, assume payment in ETH.
        IJBTerminal terminal = DIRECTORY.primaryTerminalOf(FLOW_PROJECT_ID, token);

        // If the terminal is not found, revert.
        if (address(terminal) == address(0)) {
            revert NO_FLOWS_ETH_TERMINAL();
        }

        // Pay the terminal.
        uint256 flowsReceived = terminal.pay{ value: msg.value }(
            FLOW_PROJECT_ID,
            ETH, // token in
            msg.value,
            address(this), // router receives $FLOWS
            0,
            memo,
            metadata
        );

        // Get the primary terminal for the project, assume payment in FLOWS.
        IJBTerminal destTerminal = DIRECTORY.primaryTerminalOf(projectId, FLOWS_TOKEN);

        // If the terminal is not found, revert.
        if (address(destTerminal) == address(0)) {
            revert NO_DEST_TERMINAL();
        }

        // Approve the terminal to spend the FLOWS tokens.
        IERC20(FLOWS_TOKEN).approve(address(destTerminal), flowsReceived);

        // Pay the terminal.
        destTerminal.pay(projectId, FLOWS_TOKEN, flowsReceived, beneficiary, minReturnedTokens, memo, metadata);
    }

    /**
     * @notice Get the accounting context for the specified project ID and token.
     * @dev This is a stub implementation that returns an empty context. In a full implementation,
     * accounting contexts would be stored and retrieved based on project configuration.
     * @param projectId The ID of the project to get the accounting context for.
     * @param token The address of the token to get the accounting context for.
     * @return context A `JBAccountingContext` containing the accounting context for the project ID and token.
     */
    function accountingContextForTokenOf(
        uint256 projectId,
        address token
    ) external view override returns (JBAccountingContext memory context) {
        /** Empty implementation - returns default empty context */
    }

    /** @notice Return all the accounting contexts for a specified project ID.
     * @dev This is a stub implementation that returns an empty array. In a full implementation,
     * this would return all configured accounting contexts for the project.
     * @param projectId The ID of the project to get the accounting contexts for.
     * @return contexts An array of `JBAccountingContext` containing the accounting contexts for the project ID.
     */
    function accountingContextsOf(
        uint256 projectId
    ) external view override returns (JBAccountingContext[] memory contexts) {
        /** Empty implementation - returns empty array */
    }

    /** @notice Get the current surplus for a project across multiple accounting contexts.
     * @dev This is a stub implementation that always returns 0. In a full implementation,
     * this would calculate the actual surplus based on the project's balance and configuration.
     * @param projectId The ID of the project to get the surplus for.
     * @param accountingContexts The accounting contexts to calculate surplus across.
     * @param decimals The number of decimals to include in the returned fixed point number.
     * @param currency The currency to express the surplus in.
     * @return The current surplus amount in the specified currency and decimals.
     */
    function currentSurplusOf(
        uint256 projectId,
        JBAccountingContext[] memory accountingContexts,
        uint256 decimals,
        uint256 currency
    ) external view override returns (uint256) {
        /** Empty implementation - always returns 0 */
        return 0;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /** @notice Add accounting contexts for a project.
     * @dev This is a stub implementation that does nothing. In a full implementation,
     * this would store the provided accounting contexts for the specified project.
     * @param projectId The ID of the project to add accounting contexts for.
     * @param accountingContexts The accounting contexts to add.
     */
    function addAccountingContextsFor(
        uint256 projectId,
        JBAccountingContext[] calldata accountingContexts
    ) external override {
        /** Empty implementation - no-op */
    }

    /** @notice Add funds to a project's balance.
     * @dev This is a stub implementation that does nothing. In a full implementation,
     * this would accept the specified tokens and add them to the project's balance.
     * @param projectId The ID of the project to add funds to.
     * @param token The address of the token being added.
     * @param amount The amount of tokens to add.
     * @param shouldReturnHeldFees Whether held fees should be returned.
     * @param memo A memo to include with the balance addition.
     * @param metadata Additional metadata for the balance addition.
     */
    function addToBalanceOf(
        uint256 projectId,
        address token,
        uint256 amount,
        bool shouldReturnHeldFees,
        string calldata memo,
        bytes calldata metadata
    ) external payable override {
        /** Empty implementation - no-op */
    }

    /** @notice Migrate a project's balance from this terminal to another terminal.
     * @dev This is a stub implementation that always returns 0. In a full implementation,
     * this would transfer the project's balance to the specified terminal.
     * @param projectId The ID of the project whose balance is being migrated.
     * @param token The address of the token being migrated.
     * @param to The terminal to migrate the balance to.
     * @return balance The amount of balance that was migrated.
     */
    function migrateBalanceOf(
        uint256 projectId,
        address token,
        IJBTerminal to
    ) external override returns (uint256 balance) {
        /** Empty implementation - always returns 0 */
        return 0;
    }

    //*********************************************************************//
    // -------------------------- internal functions ---------------------- //
    //*********************************************************************//

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
