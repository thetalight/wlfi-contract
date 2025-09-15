// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;


interface IWorldLibertyFinancialRegistry {

    // ==================================================
    // ==================== Structs =====================
    // ==================================================

    /// @dev The entirety of this struct should compact down into one storage slot
    struct LegacyUser {
        /// @dev This is data type is big enough to fit the whole WLFI supply
        uint112 amount;
        /// @dev Incremental categories, where 0 represents NONE and should be considered unset
        uint8 category;
        /// @dev True if the user has "activated" their account by transferring their funds into the vester
        bool isActivated;
    }

    struct RegistryStorage {
        uint256 nonce;
        mapping(address => LegacyUser) legacyUserMap;
    }

    // ==================================================
    // ===================== Events =====================
    // ==================================================

    event NonceUpdated(uint256 nonce);
    event LegacyUserUpdated(address indexed user, uint256 amount, uint8 category, bool isActivated);
    event LegacyUserTransferred(address indexed from, address indexed to);

    // ==================================================
    // ===================== Errors =====================
    // ==================================================

    error InvalidNonce();
    error InvalidBulkInsertLegacyUsersParams();
    error InvalidBulkInsertLegacyUserAtIndex(uint256 index);
    error InvalidBulkInsertLegacyUserBalance(address user);
    error InvalidUser(address user);
    error AlreadyInitialized(address user);
    error Unauthorized();

    // ==================================================
    // ================== Initializers ==================
    // ==================================================

    function initialize() external;

    // ===================================================
    // =============== External Functions ================
    // ===================================================

    /**
     * @notice  Allows the WLFI token to activate a legacy user. This is the typical flow most Legacy Users will follow
     *          to initialize their vesting account.
     *
     * @param _user     The address of the user whose account will be activated
     */
    function wlfiActivateAccount(address _user) external;

    /**
     * @notice  Transfers the registration of `_from` account to the `_to` account. Reverts if `_to` is already
     *          registered. `_to` account must be a fresh wallet. Reverts if `_from` is not a legacy user
     *
     * @param _from The from account whose registration is being transferred.
     * @param _to   The to account whose registration is being received by `_from`.
     */
    function wlfiReallocateFrom(address _from, address _to) external;

    /**
     * @notice  Allows the whitelist agent or owner to add Legacy Users to this registry. Each user is assigned an
     *          amount of WLFI they have and a category. Categories are useful for partitioning users (between founders,
     *          public sale recipient, OTC sale recipient, etc.). The lengths of these arrays must match and be > 0.
     *
     * @param _expectedNonce    The nonce that is expected be set in storage at the time of this call. Used for
     *                          coordination with the offchain script.
     * @param _users            The Legacy Users that will be added to the registry
     * @param _amounts          The amount of WLFI that each Legacy User has. Must be equal to the Legacy User's balance
     * @param _categories       The category in which each Legacy User resides
     */
    function agentBulkInsertLegacyUsers(
        uint256 _expectedNonce,
        address[] calldata _users,
        uint256[] calldata _amounts,
        uint8[] calldata _categories
    ) external;

    /**
     *
     * @return  The nonce of the latest insertion from calling {agentBulkInsertLegacyUsers}
     */
    function nonce() external view returns (uint256);

    /**
     *
     * @param _user The user to check if they are considered a Legacy User or not
     * @return  True if the user is considered a Legacy User or false otherwise
     */
    function isLegacyUser(address _user) external view returns (bool);

    /**
     *
     * @param _user The user to check if they are considered a Legacy User and if their status is activated yet
     * @return  True if the user is considered a Legacy User and they have been activated or false otherwise
     */
    function isLegacyUserAndIsActivated(address _user) external view returns (bool);

    /**
     *
     * @param _user The user to check if they are considered a Legacy User and if their status is not activated yet
     * @return  True if the user is considered a Legacy User and they have not been activated yet. False otherwise
     */
    function isLegacyUserAndIsNotActivated(address _user) external view returns (bool);

    /**
     *
     * @param _user The user whose Legacy User info should be retrieved
     * @return  The user's Legacy User info
     */
    function getLegacyUserInfo(address _user) external view returns (LegacyUser memory);

    /**
     *
     * @param _user The user whose category should be retrieved
     * @return  The user's assigned category
     */
    function getLegacyUserCategory(address _user) external view returns (uint8);

    /**
     *
     * @param _user The user whose allocation should be retrieved
     * @return  The user's assigned WLFI allocation
     */
    function getLegacyUserAllocation(address _user) external view returns (uint112);
}
