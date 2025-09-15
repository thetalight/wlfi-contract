// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "../../libraries/oz-v5/upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from "../../libraries/oz-v5/upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20BurnableUpgradeable} from "../../libraries/oz-v5/upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20VotesUpgradeable} from "../../libraries/oz-v5/upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {Ownable2StepUpgradeable} from "../../libraries/oz-v5/upgradeable/access/Ownable2StepUpgradeable.sol";
import {IERC20} from "../../libraries/oz-v5/immutable/token/ERC20/IERC20.sol";


interface IWorldLibertyFinancialV2 is IERC20 {

    // ==================================================
    // ==================== Structs =====================
    // ==================================================

    struct V2 {
        /// @dev Whether or not a user can approve or transfer tokens
        mapping(address => bool) blacklistStatus;
        address authorizedSigner;
    }

    // ==================================================
    // ===================== Events =====================
    // ==================================================

    event SetAuthorizedSigner(address indexed authorizedSigner);
    event SetGuardian(address indexed guardian, bool isGuardian);
    event SetAllowListStatus(address indexed account, bool isTransferAllowed);
    event SetVotingPowerExcludedStatus(address indexed account, bool isExcluded);
    event SetBlacklistStatus(address indexed account, bool isBlacklisted);
    event SetMaxVotingPower(uint256 maxVotingPower);
    event Reallocated(address from, address to, uint256 amount, bool didTransferRegistry);

    // ==================================================
    // ===================== Errors =====================
    // ==================================================

    error AccountNotActivated(address account);
    error Blacklisted(address account);
    error GuardianUnauthorizedAccount(address _account);
    error InvalidReallocation();
    error CannotReallocateToLegacyUser(address from, address to);
    error InvalidAccount();
    error InvalidAuthorizedSigner();
    error InvalidMaxVotingPower();
    error InvalidSignature();
    error InvalidValue();
    error NotImplemented();
    error TransferNotAllowedYet();
    error VoterIsExcluded(address account);

    // ==================================================
    // ================== Initializers ==================
    // ==================================================

    function initialize(address _authorizedSigner) external;

    // ===================================================
    // ================= Owner Functions =================
    // ===================================================

    /**
     * @notice Pauses token transfers and approvals on the WLFI token
     * @dev Only owner can invoke this function
     */
    function ownerPause() external;

    /**
     * @notice Pauses token transfers and approvals on the WLFI token
     * @dev Only owner can invoke this function
     */
    function ownerUnpause() external;

    /**
     * @notice  Set the authorized signer for this contract. This signer is used to enable the transferring of tokens by
     *          "Legacy Users"
     * @param _authorizedSigner The authorized signer address
     * @dev Only owner can invoke this function
     */
    function ownerSetAuthorizedSigner(address _authorizedSigner) external;

    /**
     * @notice Set guardian status for address. Guardians are used to call `guardian`-designated functions
     * @param _guardian Guardian address
     * @param _status Guardian status
     * @dev Only owner can invoke this function
     */
    function ownerSetGuardian(address _guardian, bool _status) external;

    /**
     * @notice Set max voting power
     * @param _maxVotingPower Max voting power for an account
     * @dev Only owner can invoke this function
     */
    function ownerSetMaxVotingPower(uint256 _maxVotingPower) external;

    /**
     * @notice  Set account transferability status. Only used before `START_TIMESTAMP` is passed by `block.timestamp`.
     *          The storage for this function inherits state from V1 `_allowList`.
     * @param _account The account whose status should be set
     * @param _isAllowed True to allow transferring before `START_TIMESTAMP`. False to disallow it.
     * @dev Only owner can invoke this function
     */
    function ownerSetTransferBeforeStartStatus(
        address _account,
        bool _isAllowed
    ) external;

    /**
     * @notice Set excluded account voting power
     * @param _account Account address
     * @param _isExcluded True to exclude this user's voting power, false to include it
     * @dev Only owner can invoke this function
     */
    function ownerSetVotingPowerExcludedStatus(
        address _account,
        bool _isExcluded
    ) external;

    /**
     * @notice Rescue accidental tokens that are stuck in the contract
     * @param _recipient Treasury address
     * @param _token Token address
     * @param _value Value to rescue
     * @dev Only owner can invoke this function
     */
    function ownerRescueTokens(
        address _recipient,
        address _token,
        uint256 _value
    ) external;

    /**
     * @notice  Burn tokens from a malicious account without requiring allowance. Mints the corresponding tokens on the
     *          other account. This is meant to be used only if a user loses access to their wallet prior to vesting
     *          beginning or when a malicious account acquires WLFI via exploit. Emits the {Reallocated} event.
     *
     * @param _from Account address to burn tokens from
     * @param _to Account address to mint the tokens to
     * @param _value Amount of tokens to re-allocate
     * @dev Only owner can invoke this function
     */
    function ownerReallocateFrom(
        address _from,
        address _to,
        uint256 _value
    ) external;

    /**
     * @notice Blacklist an account from transacting with WLFI
     * @dev Only owner can invoke this function
     * @param _account The account whose blacklist status should be changed
     * @param _isBlacklisted True to blacklist the account, false to remove it from the blacklist
     */
    function ownerSetBlacklistStatus(address _account, bool _isBlacklisted) external;

    /**
     * @notice  Activates a legacy user's vesting contract and moves their tokens into the vesting contract. Upon
     *          activation, the user may begin sending or receiving WLFI tokens.
     * @param _account      The legacy user that should be activated
     * @param _bypassVester true if the user should bypass moving their funds into the vester and therefore be instantly
     *                      unlocked. Setting this to false emulates the behavior from {activateAccount}. This parameter
     *                      is mainly used for treasury assets or tokens that should remain under the user's control.
     */
    function ownerActivateAccount(address _account, bool _bypassVester) external;

    /**
     * @notice  Claims any available WLFI for `_user`
     * @param _user The user whose vest should be claimed
     * @return The amount of WLFI claimed for the caller
     */
    function ownerClaimVestFor(address _user) external returns (uint256);

    // ==================================================
    // =============== Guardian Functions ===============
    // ==================================================

    /**
     * @notice Pauses token transfers and approvals on the WLFI token
     * @dev Only a guardian can invoke this function
     */
    function guardianPause() external;

    /**
     * @notice Blacklist an account from transacting with WLFI
     * @dev Only a guardian can invoke this function
     */
    function guardianSetBlacklistStatus(address _account, bool _isBlacklisted) external;

    // ==================================================
    // ================ Public Functions ================
    // ==================================================

    /**
     * @notice  Activates a legacy user's vesting contract and moves their tokens into the vesting contract. Upon
     *          activation, the user may begin sending or receiving WLFI tokens.
     * @param _signature    The signature that was sent by the `authorizedSigner` amount of
     */
    function activateAccount(bytes calldata _signature) external;

    /**
     * @notice  Claims any available WLFI for `msg.sender`
     * @return The amount of WLFI claimed for the caller
     */
    function claimVest() external returns (uint256);

    /**
     * @notice  Activates a user's account and claims any available WLFI for `msg.sender`
     * @return The amount of WLFI claimed for the caller
     */
    function activateAccountAndClaimVest(bytes calldata _signature) external returns (uint256);

    /**
     * @notice Get account transferability status
     * @param _sender Sender address
     */
    function getAllowListStatus(address _sender) external view returns (bool status);

    /**
     * @notice View authorized guardians
     * @param _guardian Guardian address
     */
    function isGuardian(address _guardian) external view returns (bool guardianStatus);

    /**
     * @notice  Check if an address's voting power is excluded. If it is excluded, `balanceOfVotes` and
     *          `getVotesWithBalanceFallback` will return 0 for the user
     * @param _account The address of the account to check if their voting power is excluded
     */
    function isVoterExcluded(address _account) external view returns (bool excludedStatus);

    /**
     * @notice Check if an account is blacklisted
     * @param _account The address of the account
     */
    function isBlacklisted(address _account) external view returns (bool blacklistStatus);

    /**
     * @notice  Checks if the provided `_account` is able to transfer or receive tokens
     * @param _account  The account to check if its ready to transact
     * @return  True fi the user can send or receive tokens. False if they are not able to yet.
     */
    function isReadyToTransact(address _account) external view returns (bool);

    /**
     * @return The address of the authorized signer that can approve a Legacy User's activation.
     */
    function authorizedSigner() external view returns (address);

    /**
     * @return True if the current block's timestamp is equal to or after the `TRADING_START_TIMESTAMP`.
     */
    function isAfterTradingStartTimestamp() external view returns (bool);

    /**
     * @return The max voting power an account can have
     */
    function MAX_VOTING_POWER() external view returns (uint256);

    /**
     * @return The timestamp at which trading and general transfers can begin for the WLFI token.
     */
    function TRADING_START_TIMESTAMP() external view returns (uint256);
}
