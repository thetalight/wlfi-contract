// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable2StepUpgradeable} from "../libraries/oz-v5/upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC20Upgradeable} from "../libraries/oz-v5/upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "../libraries/oz-v5/upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from "../libraries/oz-v5/upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20VotesUpgradeable} from "../libraries/oz-v5/upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {IERC20} from "../libraries/oz-v5/immutable/token/ERC20/IERC20.sol";
import {SafeERC20} from "../libraries/oz-v5/immutable/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "../libraries/oz-v5/immutable/utils/cryptography/ECDSA.sol";
import {IWorldLibertyFinancialRegistry} from "./interfaces/IWorldLibertyFinancialRegistry.sol";
import {IWorldLibertyFinancialVester} from "./interfaces/IWorldLibertyFinancialVester.sol";
import {IWorldLibertyFinancialV2} from "./interfaces/IWorldLibertyFinancialV2.sol";


contract WorldLibertyFinancialV2 is
    IWorldLibertyFinancialV2,
    ERC20VotesUpgradeable,
    ERC20PausableUpgradeable,
    ERC20BurnableUpgradeable,
    Ownable2StepUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 private constant WLFIV2StorageLocation = keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.WLFIV2")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ACTIVATION_TYPEHASH = keccak256("Activation(address account)");

    // ===================================================
    // ================ Immutable Fields =================
    // ===================================================

    uint256 public immutable override TRADING_START_TIMESTAMP;
    IWorldLibertyFinancialRegistry public immutable REGISTRY;
    IWorldLibertyFinancialVester public immutable VESTER;

    // ===================================================
    // ================== Mutable Fields =================
    // ===================================================

    // ==========================================
    /// @notice These are inherited from WLFI V1 and cannot be changed. Nor can their ordering be changed.
    // ==========================================

    /// @dev The max amount of voting power a single address can have
    uint256 public override MAX_VOTING_POWER;
    /// @dev Mapping of guardians. More info on this can be read in the interface declaration.
    mapping(address => bool) private _guardians;  // 监护人
    /// @dev    Mapping of allowed transfer agents before transferring can begin. More info on this can be read in the
    ///         interface declaration.
    mapping(address => bool) private _allowListStatus;
    /// @dev Mapping of addresses that cannot vote. More info on this can be read in the interface declaration.
    mapping(address => bool) private _excludedVotingPower;

    modifier onlyGuardian() {
        _checkGuardian();
        _;
    }

    modifier notBlacklisted(address _account) {
        _checkNotBlacklisted(_account);
        _;
    }

    constructor(uint256 _startTimestamp, address _registry, address _vester) {
        _disableInitializers();

        TRADING_START_TIMESTAMP = _startTimestamp;
        REGISTRY = IWorldLibertyFinancialRegistry(_registry);
        VESTER = IWorldLibertyFinancialVester(_vester);
    }

    /**
     * @notice Initialize World Liberty Financial (WLFI) Token
     */
    function initialize(address _authorizedSigner) external reinitializer(/* version = */ 2) {
        __EIP712_init(name(), "2");

        V2 storage $ = _getStorage();
        _ownerSetAuthorizedSigner($, _authorizedSigner);
    }

    // ===================================================
    // ================= Owner Functions =================
    // ===================================================

    function ownerPause() external onlyOwner whenNotPaused {
        _pause();
    }

    function ownerUnpause() external onlyOwner whenPaused {
        _unpause();
    }

    function ownerSetAuthorizedSigner(address _authorizedSigner) external onlyOwner {
        _ownerSetAuthorizedSigner(_getStorage(), _authorizedSigner);
    }

    function ownerSetGuardian(address _guardian, bool _status) external onlyOwner {
        if (_guardian == address(0)) {
            revert InvalidAccount();
        }

        _guardians[_guardian] = _status;
        emit SetGuardian(_guardian, _status);
    }

    function ownerSetMaxVotingPower(uint256 _maxVotingPower) external onlyOwner {
        if (_maxVotingPower > (5_000_000_000 * 1 ether)) {
            revert InvalidMaxVotingPower();
        }

        MAX_VOTING_POWER = _maxVotingPower;
        emit SetMaxVotingPower(_maxVotingPower);
    }

    function ownerSetTransferBeforeStartStatus(
        address _account,
        bool _isAllowed
    ) external onlyOwner {
        _allowListStatus[_account] = _isAllowed;
        emit SetAllowListStatus(_account, _isAllowed);
    }

    function ownerSetVotingPowerExcludedStatus(
        address _account,
        bool _status
    ) external onlyOwner {
        _ownerSetVotingPowerExcludedStatus(_account, _status);
    }

    // owner 把这个合约拥有的_token转走
    function ownerRescueTokens(
        address _recipient,
        address _token,
        uint256 _value
    ) external onlyOwner {
        if (_recipient == address(0)) {
            revert InvalidAccount();
        }
        if (_value == 0) {
            revert InvalidValue();
        }

        uint256 balanceOfToken = IERC20(_token).balanceOf(address(this));
        if (_value > balanceOfToken) {
            _value = balanceOfToken;
        }
        IERC20(_token).safeTransfer(_recipient, _value);
    }

    function ownerReallocateFrom(
        address _from,
        address _to,
        uint256 _value
    ) public onlyOwner {
        if (
            REGISTRY.isLegacyUserAndIsNotActivated(_from)
            && balanceOf(_from) != _value
        ) {
            // Legacy users must re-allocate their full balance if they are not activated
            revert InvalidReallocation();
        }
        if (REGISTRY.isLegacyUser(_to)) {
            revert CannotReallocateToLegacyUser(_from, _to);
        }

        if (_value != 0) {
            _burn(_from, _value);
            _mint(_to, _value);
        }

        bool isLegacyUser = false;
        if (REGISTRY.isLegacyUserAndIsNotActivated(_from)) {
            isLegacyUser = true;
            REGISTRY.wlfiReallocateFrom(_from, _to);
        } else if (REGISTRY.isLegacyUserAndIsActivated(_from)) {
            isLegacyUser = true;
            REGISTRY.wlfiReallocateFrom(_from, _to);
            VESTER.wlfiReallocateFrom(_from, _to);
        }

        emit Reallocated(_from, _to, _value, isLegacyUser);
    }

    function ownerSetBlacklistStatus(address _account, bool _isBlacklisted) external onlyOwner {
        _setBlacklistStatus(_account, _isBlacklisted);
    }

    function ownerActivateAccount(address _account, bool _bypassVester) external onlyOwner {
        _activateAccount(_account,_bypassVester);
    }

    function ownerClaimVestFor(address _user) external whenNotPaused onlyOwner returns (uint256) {
        return VESTER.wlfiClaimFor(_user);
    }

    function renounceOwnership() public override view onlyOwner {
        revert NotImplemented();
    }

    // ==================================================
    // =============== Guardian Functions ===============
    // ==================================================

    function guardianPause() external onlyGuardian whenNotPaused {
        _pause();
    }

    function guardianSetBlacklistStatus(address _account, bool _isBlacklisted) external onlyGuardian {
        _setBlacklistStatus(_account, _isBlacklisted);
    }

    // ==================================================
    // ================ Public Functions ================
    // ==================================================

    function activateAccount(bytes calldata _signature) external {
        address account = _msgSender();
        _validateSignatureForAccountActivationAndActivate(account, _signature);
    }

    function activateAccountAndClaimVest(bytes calldata _signature) external whenNotPaused returns (uint256) {
        address account = _msgSender();
        _validateSignatureForAccountActivationAndActivate(account, _signature);
        if (VESTER.claimable(account) == 0) {
            // Prevent reversion if there is nothing to claim. For a better UX
            return 0;
        }

        return VESTER.wlfiClaimFor(_msgSender());
    }

    function claimVest() external whenNotPaused returns (uint256) {
        return VESTER.wlfiClaimFor(_msgSender());
    }

    function getAllowListStatus(
        address _account
    ) public view returns (bool) {
        return _allowListStatus[_account];
    }

    function isGuardian(
        address _guardian
    ) public view returns (bool) {
        return _guardians[_guardian];
    }

    function isVoterExcluded(
        address _account
    ) public view returns (bool excludedStatus) {
        return _excludedVotingPower[_account];
    }

    function isBlacklisted(
        address _account
    ) public view returns (bool blacklistStatus) {
        return _getStorage().blacklistStatus[_account];
    }

    function getVotes(
        address _account
    ) public view override returns (uint256) {
        if (isVoterExcluded(_account) || isBlacklisted(_account)) {
            return 0;
        }

        // Get delegated votes + vesting votes
        // Tokens in the vester contract that are owned by `_account` cannot be delegated
        uint256 votingPower = super.getVotes(_account) + VESTER.unclaimed(_account);

        if (delegates(_account) == address(0)) {
            // If the user has not delegated yet, add their balance to reduce UX burden of calling `delegate`
            votingPower += super.balanceOf(_account);
        }

        if (votingPower > MAX_VOTING_POWER) {
            return MAX_VOTING_POWER;
        }
        return votingPower;
    }

    function isReadyToTransact(address _account) public view returns (bool) {
        return !REGISTRY.isLegacyUser(_account) || REGISTRY.isLegacyUserAndIsActivated(_account);
    }

    function authorizedSigner() public view returns (address) {
        return _getStorage().authorizedSigner;
    }

    function isAfterTradingStartTimestamp() public view returns (bool) {
        return block.timestamp >= TRADING_START_TIMESTAMP;
    }

    // ==================================================
    // =============== Internal Functions ===============
    // ==================================================

    function _delegate(
        address _account,
        address _delegatee
    )
        notBlacklisted(_msgSender())
        notBlacklisted(_account)
        notBlacklisted(_delegatee)
        whenNotPaused
        internal
        override
    {
        if (isVoterExcluded(_account)) {
            revert VoterIsExcluded(_account);
        }
        super._delegate(_account, _delegatee);
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _value,
        bool _emitEvent
    )
        notBlacklisted(_msgSender())
        notBlacklisted(_owner)
        notBlacklisted(_spender)
        whenNotPaused
        internal
        override
    {
        super._approve(_owner, _spender, _value, _emitEvent);
    }

    function _update(
        address _from,
        address _to,
        uint256 _value
    )
        notBlacklisted(_msgSender())
        notBlacklisted(_from)
        notBlacklisted(_to)
        internal
        override(
            ERC20Upgradeable,
            ERC20VotesUpgradeable,
            ERC20PausableUpgradeable
        )
    {
        if (_to == address(this)) {
            revert InvalidAccount();
        }

        if (!isAfterTradingStartTimestamp()) {
            if ((_msgSender() == address(VESTER) && _to == address(VESTER)) || _msgSender() == owner()) {
                // GUARD STATEMENT
                // Only `owner()` or `VESTER` can move tokens
                return super._update(_from, _to, _value);
            }

            // GUARD STATEMENT #2
            if (!_allowListStatus[_from]) {
                revert TransferNotAllowedYet();
            }

            return super._update(_from, _to, _value);
        }

        if (REGISTRY.isLegacyUserAndIsNotActivated(_from)) {
            // The registry is updated prior to the transfer occurring, so we don't need to check if the funds are
            // going to the vester
            revert AccountNotActivated(_from);
        }
        if (REGISTRY.isLegacyUserAndIsNotActivated(_to)) {
            revert AccountNotActivated(_to);
        }

        return super._update(_from, _to, _value);
    }

    function _ownerSetVotingPowerExcludedStatus(
        address _account,
        bool _isExcluded
    ) internal {
        if (_isExcluded) {
            // Undelegate the user's voting power
            _delegate(_account, address(0));
        }

        _excludedVotingPower[_account] = _isExcluded;
        emit SetVotingPowerExcludedStatus(_account, _isExcluded);
    }

    function _setBlacklistStatus(address _account, bool _isBlacklisted) internal {
        if (_isBlacklisted) {
            // Undelegate the user's voting power
            _delegate(_account, address(0));
        }

        _getStorage().blacklistStatus[_account] = _isBlacklisted;
        emit SetBlacklistStatus(_account, _isBlacklisted);
    }

    function _ownerSetAuthorizedSigner(V2 storage $, address _authorizedSigner) internal {
        if (_authorizedSigner == address(0)) {
            revert InvalidAuthorizedSigner();
        }

        $.authorizedSigner = _authorizedSigner;
        emit SetAuthorizedSigner(_authorizedSigner);
    }

    function _validateSignatureForAccountActivationAndActivate(address _account, bytes calldata _signature) internal {
        bytes32 hash = _hashTypedDataV4(keccak256(abi.encode(ACTIVATION_TYPEHASH, _account)));

        if (authorizedSigner() != ECDSA.recover(hash, _signature)) {
            revert InvalidSignature();
        }

        _activateAccount(_account, /* _bypassVester = */ false);
    }

    function _activateAccount(address _account, bool _bypassVester) internal {
        REGISTRY.wlfiActivateAccount(_account);
        uint8 category = REGISTRY.getLegacyUserCategory(_account);
        uint112 allocation = REGISTRY.getLegacyUserAllocation(_account);

        if (!_bypassVester) {
            // Reset the allowance
            _approve(_account, address(VESTER), 0);
            _approve(_account, address(VESTER), allocation);

            VESTER.wlfiActivateVest(_account, category, allocation);
            assert(allowance(_account, address(VESTER)) == 0);
        }
    }

    function _checkGuardian() internal view {
        address caller = _msgSender();
        if (!_guardians[caller]) {
            revert GuardianUnauthorizedAccount(caller);
        }
    }

    function _checkNotBlacklisted(address _account) internal view {
        if (_account != address(0) && _getStorage().blacklistStatus[_account]) {
            revert Blacklisted(_account);
        }
    }

    function _getStorage() private pure returns (V2 storage $) {
        bytes32 location = WLFIV2StorageLocation;
        assembly {
            $.slot := location
        }
    }

    uint256[50] private __gap; // reserve space for upgradeability storage slot. Inherited from WLFI V1
}
