// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;


interface IWorldLibertyFinancialVester {

    // ==================================================
    // ==================== Structs =====================
    // ==================================================

    // One slot: 112 + 112 + 8 + 8 = 240 bits
    struct UserInfo {
        /// @dev total allocation for this user (all segments combined)
        uint112 allocation;
        /// @dev total claimed so far
        uint112 claimed;
        /// @dev user category
        uint8 category;
        /// @dev set at first by the user
        bool initialized;
    }

    // One slot: 112 + 32 + 32 + 32 = 208 bits
    struct Template {
        /// @dev percentage cap for this segment; 1 ether (10 ** 18) equals 100%. The sum of all
        ///      `percentageOfAllocation` for a category should be <= 1 ether (100%)
        uint112 percentageOfAllocation;
        /// @dev linear start (unix time)
        uint32  startTimestamp;
        /// @dev first moment any unlocks; usually == start for cliffed-linear
        uint32  cliffTimestamp;
        /// @dev linear end (unix time)
        uint32  endTimestamp;
    }

    struct CategoryInfo {
        /// @dev Numbered from 0..8
        uint8 templateCount;
        /// @dev True if this category is enabled or not yet
        bool enabled;
    }

    struct VesterStorage {
        /// @dev Up to 8 templates per category, index order = priority (0 highest → 7 lowest).
        mapping(uint8 => Template[8]) categoryTemplates;
        /// @dev Category ID to CategoryInfo
        mapping(uint8 => CategoryInfo) categoryInfo;
        /// @dev All of the legacy users that have activated their vesting account
        mapping(address => UserInfo) users;
        /// @dev The total amount of WLFI that have been claimed by users against this vesting contract
        uint112 totalClaimed;
        /// @dev The total amount of WLFI that have been allocated to users for this vesting contract
        uint112 totalAllocated;
    }

    // ==================================================
    // ===================== Events =====================
    // ==================================================

    event VestActivated(address indexed account, uint8 category, uint112 allocation);
    event VestTransferred(address indexed from, address indexed to);
    event SetCategoryTemplate(uint8 indexed category, uint8 indexed index, Template t);
    event SetCategoryEnabled(uint8 indexed category, bool enabled);
    event SetCategoryTemplateCount(uint8 indexed category, uint8 count);
    event Claimed(address indexed user, uint256 amount);

    // ==================================================
    // ===================== Errors =====================
    // ==================================================

    error Unauthorized();
    error InvalidParameters();
    error InvalidTemplateCount();
    error InvalidTemplateTimestamp();
    error InvalidUser(address user);
    error CategoryNotEnabled(uint8 category);
    error AlreadyInitialized(address user);
    error UserNotInitialized(address user);
    error NothingToClaim();

    // ==================================================
    // ================== Initializers ==================
    // ==================================================

    function initialize() external;

    // ==================================================
    // ================= Owner Functions ================
    // ==================================================

    /**
     * @notice Pause user claims and vest activations.
     * @dev Owner-only guardian switch. Paused state blocks {claim} but allows admin maintenance.
     *
     * @custom:reverts OwnableUnauthorizedAccount   If the caller is not the contract owner.
     * @custom:reverts AlreadyPaused                If the contract is already paused.
     */
    function ownerPause() external;

    /**
     * @notice Unpause user claims.
     * @dev Owner-only guardian switch. Restores {claim} functionality.
     *
     * @custom:reverts OwnableUnauthorizedAccount   If the caller is not the contract owner.
     * @custom:reverts NotPaused                    If the contract is not currently paused.
     */
    function ownerUnpause() external;

    /**
     * @notice Enables a category so their vests may be activated.
     *
     * @param _category The category ID (uint8) that is being enabled
     * @param _enabled  True to enable the category, false to disable it.
     *
     * @custom:reverts OwnableUnauthorizedAccount   If the caller is not the contract owner.
     * @custom:reverts NotPaused                    If the contract is not currently paused.
     */
    function ownerSetCategoryEnabled(uint8 _category, bool _enabled) external;

    /**
     * @notice Configure or update a vesting template for a given category at a given priority index.
     * @dev Each category supports up to 8 template slots (priority order: index 0 highest → 7 lowest).
     *      The `_template` struct uses:
     *        - percentageOfAllocation (uint112):
     *              percentage cap for this segment; 1 ether (10 ** 18) equals 100%. The sum of all
     *              `percentageOfAllocation` for a category should be <= 1 ether (100%)
     *        - startTimestamp (uint32)
     *        - cliffTimestamp (uint32)
     *        - endTimestamp (uint32)
     *              The vesting schedule; linear from (startTimestamp → endTimestamp); cliffTimestamp must be greater
     *              than or equal to startTimestamp.
     *      Setting a higher index than the current count increases the active template count for that category.
     *
     * @param _category  The category ID (uint8) being configured.
     * @param _index     The priority index to set (0..3).
     * @param _template  The vesting template parameters for this slot.
     *
     * @custom:reverts OwnableUnauthorizedAccount   If the caller is not the contract owner.
     * @custom:reverts IndexOutOfRange              If `_index` >= 8.
     * @custom:reverts InvalidTimeOrdering          If `_template.endTimestamp` != 0 and
     *                                              (startTimestamp > cliffTimestamp || cliffTimestamp > endTimestamp).
     */
    function ownerSetCategoryTemplate(uint8 _category, uint8 _index, Template calldata _template) external;

    // ==================================================
    // =============== Guardian Functions ===============
    // ==================================================

    /**
     * @notice Pause vest activation, user claims, owner-assisted claims.
     * @dev Guardian-only circuit breaker. When paused, user-facing functions
     *      (e.g., {claim}, {wlfiActivateVest}, {ownerClaimFor}) MUST revert. Administrative configuration
     *      (e.g., setting templates) may remain allowed depending on implementation.
     *
     * @custom:reverts GuardianUnauthorizedAccount  If the caller is not the designated guardian.
     * @custom:reverts EnforcedPause                If the contract is already in the paused state.
     */
    function guardianPause() external;

    // ==================================================
    // =============== External Functions ===============
    // ==================================================

    /**
     * @notice Activate a user's WLFI vest using offchain–curated data.
     * @dev Callable by the the WLFI token only and used to set up a user's vesting info as well as transfer a Legacy
     *      User's vesting allocation into this vesting contract. Once a user is activated, they can begin calling
     *      {claim}.
     *
     * @param _user      The beneficiary to activate.
     * @param _category  The category the user belongs to.
     * @param _amount    The total WLFI allocation for this user (uint112).
     *
     * @custom:reverts Unauthorized           If the caller is not the WLFI token.
     * @custom:reverts InvalidParameters      If `_user` is the zero address, `_category` is 0, or `_amount` is zero.
     * @custom:reverts AlreadyInitialized     If `_user` is already activated their vest.
     */
    function wlfiActivateVest(address _user, uint8 _category, uint112 _amount) external;

    /**
     * @notice Claim ALL currently available (vested & unclaimed) WLFI for `_user`.
     * @dev Pulls the user’s category pipeline, computes unlocked amounts across up to 8 template
     *      segments in order, subtracts `claimed`, and transfers the claimable amount to the user.
     *      If nothing is claimable, reverts with `NothingToClaim`.
     *
     * @param _user    The user whose vest should be claimed
     * @return amount  The amount of WLFI transferred to the user for this claim.
     *
     * @custom:reverts Unauthorized           If the caller is not the WLFI token.
     * @custom:reverts EnforcedPause          If the contract is paused.
     * @custom:reverts UserNotInitialized     If the user has not been initialized (see {wlfiActivateVest}).
     * @custom:reverts NothingToClaim         If the user's claimable amount is 0
     */
    function wlfiClaimFor(address _user) external returns (uint256);

    /**
     * @notice Reassign a vested account’s ownership from one address to another within the vesting contract.
     * @dev Admin-only maintenance. Moves the in-contract accounting record for `_from` to `_to`
     *      without transferring any tokens. The fields `{allocation, claimed, category, initialized}`
     *      are copied so that the user’s remaining claimable balance is preserved exactly under `_to`.
     *      Intended for support cases (e.g., lost wallets). Does not modify category or totals.
     *
     * @param _from  The current owner of the vested account record.
     * @param _to    The new owner that will assume the vested account record.
     *
     * @custom:effects Copies the entire `UserInfo` for `_from` to `_to`, then clears `_from`’s record.
     *                 No ERC20 transfer occurs. After reallocation, `_to` can call {claim}.
     *
     * @custom:reverts NotAuthorized          If the caller lacks permission to reallocate vest records.
     * @custom:reverts ZeroAddress            If `_to` is the zero address.
     * @custom:reverts SameAddress            If `_to` equals `_from`.
     * @custom:reverts FromNotInitialized     If `_from` has no initialized vesting record in this contract.
     * @custom:reverts ToAlreadyInitialized   If `_to` already has a vesting record (initialized or non-empty).
     * @custom:reverts Paused                 (If implemented) If the contract is paused and reallocations are disallowed.
     *
     * @dev Optional policy notes:
     *      - If your policy requires the new owner to explicitly acknowledge terms, you may reset
     *        `initialized` to false during the move so `_to` must re-initialize before claiming.
     *      - If you disallow moving fully claimed records, add and document `NothingToReallocate`
     *        when `allocation == claimed`.
     */
    function wlfiReallocateFrom(address _from, address _to) external;

    /**
     * @notice Claim ALL currently available (vested & unclaimed) WLFI for the caller.
     * @dev Pulls the user’s category pipeline, computes unlocked amounts across up to 8 template
     *      segments in order, subtracts `claimed`, and transfers the claimable amount to the user.
     *      If nothing is claimable, reverts with `NothingToClaim`.
     *
     * @return amount  The amount of WLFI transferred to the user for this claim.
     *
     * @custom:reverts EnforcedPause          If the contract is paused.
     * @custom:reverts UserNotInitialized     If the user has not been initialized (see {wlfiActivateVest}).
     * @custom:reverts NothingToClaim         If the user's claimable amount is 0
     */
    function claim() external returns (uint256);

    /**
     * @notice View the amount currently claimable by a user.
     * @dev Purely a read: computes unlocked across the user’s category templates and subtracts `claimed`.
     *      Returns 0 for users who are not initialized.
     *
     * @param _user The address to query.
     * @return      The currently claimable WLFI for `_user`.
     */
    function claimable(address _user) external view returns (uint256);

    /**
     * @notice View the amount that has been claimed by a user.
     * @dev Purely a read: computes how many tokens were `claimed`. Returns 0 for users who are not initialized.
     *
     * @param _user The address to query.
     * @return      The amount of WLFI claimed for `_user`.
     */
    function claimed(address _user) external view returns (uint256);

    /**
     * @notice View the amount that has been allocated to a user.  Returns 0 for users who are not initialized.
     * @dev Purely a read: computes how many tokens were `claimed`. Returns 0 for users who are not initialized.
     *
     * @param _user The address to query.
     * @return      The amount of WLFI that has been allocated for `_user`.
     */
    function allocation(address _user) external view returns (uint256);

    /**
     * @notice View the amount that has been unclaimed by the user.  Returns 0 for users who are not initialized.
     * @dev Purely a read: computes how many tokens were `unclaimed`. Returns 0 for users who are not initialized.
     *
     * @param _user The address to query.
     * @return      The amount of WLFI that has been allocated to the `_user` and unclaimed.
     */
    function unclaimed(address _user) external view returns (uint256);

    /**
     * @return  The total amount of WLFI tokens that have been claimed by users
     */
    function totalClaimed() external view returns (uint256);

    /**
     * @return  The total amount of WLFI tokens that have been allocated to users who have activated their wallets
     */
    function totalAllocated() external view returns (uint256);

    /**
     * @return  The total amount of WLFI tokens that have been allocated to users and are unclaimed
     */
    function totalUnclaimed() external view returns (uint256);

    /**
     * @param _category The category whose info should be retrieved.
     * @return The category info for a given category
     */
    function getCategoryInfo(uint8 _category) external view returns (CategoryInfo memory);

    /**
     * @param _category The category whose info should be retrieved.
     * @return All of the templates for a given category. The max length of the array is 8.
     */
    function getAllCategoryTemplates(uint8 _category) external view returns (Template[] memory);
}
