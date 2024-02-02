// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import {ILensHub} from 'contracts/interfaces/ILensHub.sol';
import {Types} from 'contracts/libraries/constants/Types.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

import {ILensHandles} from 'contracts/interfaces/ILensHandles.sol';
import {ITokenHandleRegistry} from 'contracts/interfaces/ITokenHandleRegistry.sol';

/**
 * @title PermissonlessCreator
 * @author Lens Protocol
 * @notice This is an ownable public proxy contract which is open for all.
 */
contract PermissonlessCreator is Ownable {
    ILensHandles public immutable LENS_HANDLES;
    ITokenHandleRegistry public immutable TOKEN_HANDLE_REGISTRY;
    address immutable LENS_HUB;

    uint128 private _profileCreationCost = 5 ether; // TODO: Make it constant, remove setter and set through upgrade?
    uint128 private _handleCreationCost = 5 ether; // TODO: Make it constant, remove setter and set through upgrade?

    mapping(address => uint256) internal _credits;
    mapping(address => bool) internal _isCreditProvider;
    mapping(address => bool) internal _isUntrusted;
    mapping(uint256 => address) internal _profileCreatorUsingCredits;

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
    error NotAllowedToLinkHandleToProfile();
    error HandleLengthNotAllowed();
    error NotAllowed();

    event HandleCreationPriceChanged(uint256 newPrice);
    event ProfileCreationPriceChanged(uint256 newPrice);
    event CreditSpent(address indexed from, uint256 remainingCredits);
    event CreditBalanceChanged(address indexed creditAddress, uint256 remainingCredits);
    event UntrustnessToggled(address indexed targetAddress);

    constructor(address owner, address hub, address lensHandles, address tokenHandleRegistry) {
        _transferOwnership(owner);
        LENS_HUB = hub;
        LENS_HANDLES = ILensHandles(lensHandles);
        TOKEN_HANDLE_REGISTRY = ITokenHandleRegistry(tokenHandleRegistry);
    }

    // Function onlyOwner to transfer all funds from paid creations - otherwise funds are locked here.
    function withdrawFunds() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /////////////////////////// Permissionless payable creation functions //////////////////////////////////////////////

    function createProfile(
        Types.CreateProfileParams calldata createProfileParams
    ) external payable returns (uint256 profileId) {
        _validatePayment(_profileCreationCost);
        address[] memory delegatedExecutors; // Empty array, only trusted credit-based creators can keep delegates
        return _createProfile(createProfileParams, delegatedExecutors);
    }

    function createHandle(address to, string calldata handle) external payable returns (uint256) {
        _validatePayment(_handleCreationCost);
        if (bytes(handle).length < 5) {
            revert HandleLengthNotAllowed();
        }
        return LENS_HANDLES.mintHandle(to, handle);
    }

    function createProfileWithHandle(
        Types.CreateProfileParams calldata createProfileParams,
        string calldata handle
    ) external payable returns (uint256 profileId, uint256 handleId) {
        _validatePayment(_profileCreationCost + _handleCreationCost);
        address[] memory delegatedExecutors; // Empty array, only trusted credit-based creators can keep delegates
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
        return profileId;
    }

    function createProfileWithHandleUsingCredits(
        Types.CreateProfileParams calldata createProfileParams,
        string calldata handle,
        address[] calldata delegatedExecutors
    ) external returns (uint256, uint256) {
        _spendCredit(msg.sender);
        (uint256 profileId, uint256 handleId) = _createProfileWithHandle(
            createProfileParams,
            handle,
            delegatedExecutors
        );
        _profileCreatorUsingCredits[profileId] = msg.sender;
        return (profileId, handleId);
    }

    function createHandleUsingCredits(address to, string calldata handle) external returns (uint256) {
        _spendCredit(msg.sender);
        return LENS_HANDLES.mintHandle(to, handle);
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
    ) private returns (uint256 profileId, uint256 handleId) {
        // Copy the struct from calldata to memory to make it mutable
        Types.CreateProfileParams memory createProfileParamsMemory = createProfileParams;

        // We mint the handle & profile to this contract first, then link it to the profile and delegates if defined
        // This will not allow to initialize follow modules that require funds from the msg.sender,
        // but we assume only simple follow modules should be set during profile creation.
        // Complex ones can be set after the profile is created.
        address destination = createProfileParamsMemory.to;

        createProfileParamsMemory.to = address(this);

        uint256 _profileId = ILensHub(LENS_HUB).createProfile(createProfileParamsMemory);
        uint256 _handleId = LENS_HANDLES.mintHandle(address(this), handle);

        TOKEN_HANDLE_REGISTRY.link({handleId: _handleId, profileId: _profileId});

        _addDelegatesToProfile(_profileId, delegatedExecutors);

        // Transfer the handle & profile to the destination
        LENS_HANDLES.transferFrom(address(this), destination, _handleId);
        // keep the config if its been set
        ILensHub(LENS_HUB).transferFromKeepingDelegates(address(this), destination, profileId);

        return (_profileId, _handleId);
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

    /// @dev Requires the sender, a trusted credit-based creator, to approve the profile with this contract as spender.
    function transferFromKeepingDelegates(address from, address to, uint256 tokenId) external {
        if (_isUntrusted[msg.sender] || _profileCreatorUsingCredits[tokenId] != msg.sender) {
            // If is untrusted or not the original creator of the profile through credits, then fail.
            revert NotAllowed();
        }
        ILensHub(LENS_HUB).transferFromKeepingDelegates(from, to, tokenId);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function _validatePayment(uint256 amount) private view {
        if (msg.value < amount) {
            revert InvalidFunds();
        }
    }

    function _spendCredit(address from) private {
        _credits[from] -= 1;
        emit CreditSpent(from, _credits[from]);
    }

    function increaseCredits(address to, uint256 amount) external onlyCreditProviders {
        _credits[to] += amount;
        emit CreditBalanceChanged(to, _credits[to]);
    }

    function decreaseCredits(address to, uint256 amount) external onlyCreditProviders {
        _credits[to] -= amount;
        emit CreditBalanceChanged(to, _credits[to]);
    }

    function addCreditor(address creditor) external onlyOwner {
        _isCreditProvider[creditor] = true;
    }

    function removeCreditor(address creditor) external onlyOwner {
        _isCreditProvider[creditor] = false;
    }

    function changeHandleCreationPrice(uint128 newPrice) external onlyOwner {
        _handleCreationCost = newPrice;
        emit HandleCreationPriceChanged(newPrice);
    }

    function changeProfileCreationPrice(uint128 newPrice) external onlyOwner {
        _profileCreationCost = newPrice;
        emit ProfileCreationPriceChanged(newPrice);
    }

    function getPriceForProfileWithHandleCreation() external view returns (uint256) {
        return _profileCreationCost + _handleCreationCost;
    }

    function getPriceForProfileCreation() external view returns (uint256) {
        return _profileCreationCost;
    }

    function getPriceForHandleCreation() external view returns (uint256) {
        return _handleCreationCost;
    }

    function toggleTrustness(address targetAddress) external onlyOwner {
        bool isUntrusted = _isUntrusted[targetAddress];
        if (!isUntrusted) {
            // If it is becoming untrusted, current credits should be revoked.
            uint256 targetAddressCredits = _credits[targetAddress];
            if (targetAddressCredits > 0) {
                _credits[targetAddress] = 0;
                emit CreditBalanceChanged(targetAddress, targetAddressCredits);
            }
        }
        _isUntrusted[targetAddress] = !isUntrusted;
        emit UntrustnessToggled(targetAddress);
    }

    function isTrusted(address targetAddress) external view returns (bool) {
        return !_isUntrusted[targetAddress];
    }

    function isCreditProvider(address targetAddress) external view returns (bool) {
        return _isCreditProvider[targetAddress];
    }

    function getCreditBalance(address targetAddress) external view returns (uint256) {
        return _credits[targetAddress];
    }
}
