// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import {ILensHub} from 'contracts/interfaces/ILensHub.sol';
import {Types} from 'contracts/libraries/constants/Types.sol';

import {ILensHandles} from 'contracts/interfaces/ILensHandles.sol';
import {ITokenHandleRegistry} from 'contracts/interfaces/ITokenHandleRegistry.sol';
import {ImmutableOwnable} from 'contracts/misc/ImmutableOwnable.sol';

/**
 * @title PermissionlessCreator
 * @author Lens Protocol
 * @notice This is an ownable public proxy contract which is open for all.
 */
contract PermissionlessCreator is ImmutableOwnable {
    ILensHandles public immutable LENS_HANDLES;
    ITokenHandleRegistry public immutable TOKEN_HANDLE_REGISTRY;

    // These should be configured through setters before being whitelisted in the LensHub.
    uint128 private _profileCreationCost;
    uint128 private _handleCreationCost;
    uint8 private _handleLengthMin;

    mapping(address => uint256) internal _credits;
    mapping(address => bool) internal _isCreditProvider; // Credit providers can increase/decrease credits of users
    mapping(address => bool) internal _isUntrusted;
    mapping(uint256 => address) internal _profileCreatorUsingCredits; // The address that created the profile spending credits

    modifier onlyCreditProviders() {
        if (!_isCreditProvider[msg.sender]) {
            revert OnlyCreditProviders();
        }
        _;
    }

    error OnlyCreditProviders();
    error HandleAlreadyExists();
    error InvalidFunds();
    error InsufficientCredits();
    error ProfileAlreadyLinked();
    error HandleLengthNotAllowed();
    error NotAllowed();

    event HandleCreationPriceChanged(uint256 newPrice, uint256 timestamp);
    event ProfileCreationPriceChanged(uint256 newPrice, uint256 timestamp);
    event HandleLengthMinChanged(uint8 newMinLength, uint256 timestamp);
    event CreditBalanceChanged(address indexed creditAddress, uint256 remainingCredits, uint256 timestamp);
    event TrustStatusChanged(address indexed targetAddress, bool isUntrusted, uint256 timestamp);
    event CreditProviderStatusChanged(address indexed creditProvider, bool isCreditProvider, uint256 timestamp);

    event ProfileCreatedUsingCredits(uint256 indexed profileId, address indexed creator, uint256 timestamp);
    event HandleCreatedUsingCredits(
        uint256 indexed handleId,
        string handle,
        address indexed creator,
        uint256 timestamp
    );

    constructor(
        address owner,
        address lensHub,
        address lensHandles,
        address tokenHandleRegistry
    ) ImmutableOwnable(owner, lensHub) {
        LENS_HANDLES = ILensHandles(lensHandles);
        TOKEN_HANDLE_REGISTRY = ITokenHandleRegistry(tokenHandleRegistry);
    }

    /////////////////////////// Permissionless payable creation functions //////////////////////////////////////////////

    function createProfile(
        Types.CreateProfileParams calldata createProfileParams,
        address[] calldata delegatedExecutors
    ) external payable returns (uint256) {
        _validatePayment(_profileCreationCost);
        // delegatedExecutors are only allowed if to == msg.sender
        if (delegatedExecutors.length > 0 && createProfileParams.to != msg.sender) {
            revert NotAllowed();
        }
        return _createProfile(createProfileParams, delegatedExecutors);
    }

    function createHandle(address to, string calldata handle) external payable returns (uint256) {
        _validatePayment(_handleCreationCost);
        _validateHandleLength(handle);
        return LENS_HANDLES.mintHandle(to, handle);
    }

    function createProfileWithHandle(
        Types.CreateProfileParams calldata createProfileParams,
        string calldata handle,
        address[] calldata delegatedExecutors
    ) external payable returns (uint256, uint256) {
        _validatePayment(_profileCreationCost + _handleCreationCost);
        _validateHandleLength(handle);
        // delegatedExecutors are only allowed if to == msg.sender
        if (delegatedExecutors.length > 0 && createProfileParams.to != msg.sender) {
            revert NotAllowed();
        }
        return _createProfileWithHandle(createProfileParams, handle, delegatedExecutors);
    }

    ////////////////////////////// Credit based creation functions /////////////////////////////////////////////////////

    function createProfileUsingCredits(
        Types.CreateProfileParams calldata createProfileParams,
        address[] calldata delegatedExecutors
    ) external returns (uint256) {
        _spendCredit(msg.sender);
        uint256 profileId = _createProfile(createProfileParams, delegatedExecutors);
        _profileCreatorUsingCredits[profileId] = msg.sender;
        emit ProfileCreatedUsingCredits(profileId, msg.sender, block.timestamp);
        return profileId;
    }

    function createProfileWithHandleUsingCredits(
        Types.CreateProfileParams calldata createProfileParams,
        string calldata handle,
        address[] calldata delegatedExecutors
    ) external returns (uint256, uint256) {
        _spendCredit(msg.sender);
        _validateHandleLength(handle);
        (uint256 profileId, uint256 handleId) = _createProfileWithHandle(
            createProfileParams,
            handle,
            delegatedExecutors
        );
        _profileCreatorUsingCredits[profileId] = msg.sender;
        emit ProfileCreatedUsingCredits(profileId, msg.sender, block.timestamp);
        emit HandleCreatedUsingCredits(handleId, handle, msg.sender, block.timestamp);
        return (profileId, handleId);
    }

    function createHandleUsingCredits(address to, string calldata handle) external returns (uint256) {
        _spendCredit(msg.sender);
        _validateHandleLength(handle);
        uint256 handleId = LENS_HANDLES.mintHandle(to, handle);
        emit HandleCreatedUsingCredits(handleId, handle, msg.sender, block.timestamp);
        return handleId;
    }

    ////////////////////////////////////////// Base functions //////////////////////////////////////////////////////////

    function _createProfile(
        Types.CreateProfileParams calldata createProfileParams,
        address[] memory delegatedExecutors
    ) internal returns (uint256) {
        uint256 profileId;
        if (delegatedExecutors.length == 0) {
            profileId = ILensHub(LENS_HUB).createProfile(createProfileParams);
        } else {
            // We mint the profile to this contract first, then apply delegates if defined
            // This will not allow to initialize follow modules that require funds from the msg.sender,
            // but we assume only simple follow modules should be set during profile creation.
            // Complex ones can be set after the profile is created.
            address destination = createProfileParams.to;

            // Copy the struct from calldata to memory to make it mutable
            Types.CreateProfileParams memory createProfileParamsMemory = createProfileParams;
            createProfileParamsMemory.to = address(this);

            profileId = ILensHub(LENS_HUB).createProfile(createProfileParamsMemory);

            _addDelegatesToProfile(profileId, delegatedExecutors);

            // keep the config if its been set
            ILensHub(LENS_HUB).transferFromKeepingDelegates(address(this), destination, profileId);
        }
        return profileId;
    }

    function _createProfileWithHandle(
        Types.CreateProfileParams calldata createProfileParams,
        string calldata handle,
        address[] memory delegatedExecutors
    ) private returns (uint256, uint256) {
        // Copy the struct from calldata to memory to make it mutable
        Types.CreateProfileParams memory createProfileParamsMemory = createProfileParams;

        // We mint the handle & profile to this contract first, then link it to the profile and delegates if defined
        // This will not allow to initialize follow modules that require funds from the msg.sender,
        // but we assume only simple follow modules should be set during profile creation.
        // Complex ones can be set after the profile is created.
        address destination = createProfileParamsMemory.to;

        createProfileParamsMemory.to = address(this);

        uint256 profileId = ILensHub(LENS_HUB).createProfile(createProfileParamsMemory);
        uint256 handleId = LENS_HANDLES.mintHandle(address(this), handle);

        TOKEN_HANDLE_REGISTRY.link(handleId, profileId);

        _addDelegatesToProfile(profileId, delegatedExecutors);

        // Transfer the handle & profile to the destination
        LENS_HANDLES.transferFrom(address(this), destination, handleId);
        // keep the config if its been set
        ILensHub(LENS_HUB).transferFromKeepingDelegates(address(this), destination, profileId);

        return (profileId, handleId);
    }

    function _addDelegatesToProfile(uint256 profileId, address[] memory delegatedExecutors) private {
        // set delegates if any
        if (delegatedExecutors.length > 0) {
            // Initialize an array of bools with the same length as delegatedExecutors
            bool[] memory executorEnabled = new bool[](delegatedExecutors.length);

            // Fill the array with `true`
            for (uint256 i = 0; i < delegatedExecutors.length; i++) {
                executorEnabled[i] = true;
            }

            ILensHub(LENS_HUB).changeDelegatedExecutorsConfig(profileId, delegatedExecutors, executorEnabled);
        }
    }

    function _validateHandleLength(string calldata handle) private view {
        if (!_isCreditProvider[msg.sender] && bytes(handle).length < _handleLengthMin) {
            revert HandleLengthNotAllowed();
        }
    }

    function _validatePayment(uint256 amount) private view {
        if (msg.value < amount) {
            revert InvalidFunds();
        }
    }

    function _spendCredit(address account) private {
        if (_isCreditProvider[msg.sender]) {
            // Credit providers do not need credits.
            return;
        }
        _credits[account] -= 1;
        emit CreditBalanceChanged(account, _credits[account], block.timestamp);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Special function allowing to transfer a profile from one address to another, keeping the delegates.
    /// @dev Requires the sender, a trusted credit-based creator, to approve the profile with this contract as spender.
    function transferFromKeepingDelegates(address from, address to, uint256 tokenId) external {
        if (_isUntrusted[msg.sender] || _profileCreatorUsingCredits[tokenId] != msg.sender) {
            // If msg.sender trust was revoked or is not the original creator of the profile through credits, then fail.
            revert NotAllowed();
        }

        ILensHub(LENS_HUB).transferFromKeepingDelegates(from, to, tokenId);
    }

    // Credit Provider functions

    function increaseCredits(address account, uint256 amount) external onlyCreditProviders {
        if (_isUntrusted[account]) {
            // Cannot increase credits for an account with revoked trust.
            revert NotAllowed();
        }
        _credits[account] += amount;
        emit CreditBalanceChanged(account, _credits[account], block.timestamp);
    }

    function decreaseCredits(address account, uint256 amount) external onlyCreditProviders {
        _credits[account] -= amount;
        emit CreditBalanceChanged(account, _credits[account], block.timestamp);
    }

    // Owner functions

    function withdrawFunds() external onlyOwner {
        // Use call instead of transfer to provide more gas (otherwise it doesn't work with SAFE):
        // https://diligence.consensys.net/blog/2019/09/stop-using-soliditys-transfer-now/
        (bool success, ) = OWNER.call{value: address(this).balance}('');
        if (!success) {
            revert();
        }
    }

    function addCreditProvider(address creditProvider) external onlyOwner {
        _isCreditProvider[creditProvider] = true;
        emit CreditProviderStatusChanged(creditProvider, true, block.timestamp);
    }

    function removeCreditProvider(address creditProvider) external onlyOwner {
        _isCreditProvider[creditProvider] = false;
        emit CreditProviderStatusChanged(creditProvider, false, block.timestamp);
    }

    function setProfileCreationPrice(uint128 newPrice) external onlyOwner {
        _profileCreationCost = newPrice;
        emit ProfileCreationPriceChanged(newPrice, block.timestamp);
    }

    function setHandleCreationPrice(uint128 newPrice) external onlyOwner {
        _handleCreationCost = newPrice;
        emit HandleCreationPriceChanged(newPrice, block.timestamp);
    }

    function setHandleLengthMin(uint8 newMinLength) external onlyOwner {
        _handleLengthMin = newMinLength;
        emit HandleLengthMinChanged(newMinLength, block.timestamp);
    }

    function setTrustStatus(address targetAddress, bool setAsUntrusted) external onlyOwner {
        if (setAsUntrusted == _isUntrusted[targetAddress]) {
            // No change in trust status.
            return;
        }
        if (setAsUntrusted && _credits[targetAddress] > 0) {
            // If it is becoming unstrusted, current credits should be removed.
            _credits[targetAddress] = 0;
            emit CreditBalanceChanged(targetAddress, 0, block.timestamp);
        }
        _isUntrusted[targetAddress] = setAsUntrusted;
        emit TrustStatusChanged(targetAddress, setAsUntrusted, block.timestamp);
    }

    // View functions

    function getProfileWithHandleCreationPrice() external view returns (uint256) {
        return _profileCreationCost + _handleCreationCost;
    }

    function getProfileCreationPrice() external view returns (uint256) {
        return _profileCreationCost;
    }

    function getHandleCreationPrice() external view returns (uint256) {
        return _handleCreationCost;
    }

    function getHandleLengthMin() external view returns (uint8) {
        return _handleLengthMin;
    }

    function isUntrusted(address targetAddress) external view returns (bool) {
        return _isUntrusted[targetAddress];
    }

    function isCreditProvider(address targetAddress) external view returns (bool) {
        return _isCreditProvider[targetAddress];
    }

    function getCreditBalance(address targetAddress) external view returns (uint256) {
        return _credits[targetAddress];
    }

    function getProfileCreatorUsingCredits(uint256 profileId) external view returns (address) {
        return _profileCreatorUsingCredits[profileId];
    }
}
