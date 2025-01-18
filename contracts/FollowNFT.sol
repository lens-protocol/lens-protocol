// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import {Types} from 'contracts/libraries/constants/Types.sol';
import {ERC2981CollectionRoyalties} from 'contracts/base/ERC2981CollectionRoyalties.sol';
import {Errors} from 'contracts/libraries/constants/Errors.sol';
import {HubRestricted} from 'contracts/base/HubRestricted.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC721Timestamped} from 'contracts/interfaces/IERC721Timestamped.sol';
import {IFollowNFT} from 'contracts/interfaces/IFollowNFT.sol';
import {ILensHub} from 'contracts/interfaces/ILensHub.sol';
import {LensBaseERC721} from 'contracts/base/LensBaseERC721.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';
import {StorageLib} from 'contracts/libraries/StorageLib.sol';
import {Types} from 'contracts/libraries/constants/Types.sol';
import {IFollowTokenURI} from 'contracts/interfaces/IFollowTokenURI.sol';

/**
 * @custom:upgradeable Beacon proxy. The beacon, responsible for returning the implementation address, is the LensHub.
 */
contract FollowNFT is HubRestricted, LensBaseERC721, ERC2981CollectionRoyalties, IFollowNFT {
    using Strings for uint256;

    string constant FOLLOW_NFT_NAME_SUFFIX = '-Follower';
    string constant FOLLOW_NFT_SYMBOL_SUFFIX = '-Fl';

    uint256[5] __DEPRECATED_SLOTS; // Deprecated slots, previously used for delegations.
    uint256 internal _followedProfileId;

    // Old uint256 `_lastFollowTokenId` slot splitted into two uint128s to include `_followerCount`.
    uint128 internal _lastFollowTokenId;
    // `_followerCount` will not be decreased when a follower profile is burned, making the counter not fully accurate.
    // New variable added in V2 in the same slot, lower-ordered to not conflict with previous storage layout.
    uint128 internal _followerCount;

    bool private _initialized;

    // Introduced in v2
    mapping(uint256 => Types.FollowData) internal _followDataByFollowTokenId;
    mapping(uint256 => uint256) internal _followTokenIdByFollowerProfileId;
    mapping(uint256 => uint256) internal _followApprovalByFollowTokenId;
    uint256 internal _royaltiesInBasisPoints;

    event FollowApproval(uint256 indexed followerProfileId, uint256 indexed followTokenId);

    modifier whenNotPaused() {
        if (ILensHub(HUB).getState() == Types.ProtocolState.Paused) {
            revert Errors.Paused();
        }
        _;
    }

    constructor(address hub) HubRestricted(hub) {
        _initialized = true;
    }

    /// @inheritdoc IFollowNFT
    function initialize(uint256 profileId) external override {
        // This is called right after deployment by the LensHub, so we can skip the onlyHub check.
        if (_initialized) {
            revert Errors.Initialized();
        }
        _initialized = true;
        _followedProfileId = profileId;
        _setRoyalty(1000); // 10% of royalties
    }

    /// @inheritdoc IFollowNFT
    function follow(
        uint256 followerProfileId,
        address transactionExecutor,
        uint256 followTokenId
    ) external override onlyHub returns (uint256) {
        if (_followTokenIdByFollowerProfileId[followerProfileId] != 0) {
            revert AlreadyFollowing();
        }

        if (followTokenId == 0) {
            // Fresh follow.
            return _followMintingNewToken(followerProfileId);
        }

        address followTokenOwner = _unsafeOwnerOf(followTokenId);
        if (followTokenOwner != address(0)) {
            // Provided follow token is wrapped.
            return
                _followWithWrappedToken({
                    followerProfileId: followerProfileId,
                    transactionExecutor: transactionExecutor,
                    followTokenId: followTokenId
                });
        }

        uint256 currentFollowerProfileId = _followDataByFollowTokenId[followTokenId].followerProfileId;
        if (currentFollowerProfileId != 0) {
            // Provided follow token is unwrapped.
            // It has a follower profile set already, it can only be used to follow if that profile was burnt.
            return
                _followWithUnwrappedTokenFromBurnedProfile({
                    followerProfileId: followerProfileId,
                    followTokenId: followTokenId,
                    currentFollowerProfileId: currentFollowerProfileId,
                    transactionExecutor: transactionExecutor
                });
        }

        // Provided follow token does not exist anymore, it can only be used if the profile attempting to follow is
        // allowed to recover it.
        return _followByRecoveringToken({followerProfileId: followerProfileId, followTokenId: followTokenId});
    }

    /// @inheritdoc IFollowNFT
    function unfollow(uint256 unfollowerProfileId) external override onlyHub {
        uint256 followTokenId = _followTokenIdByFollowerProfileId[unfollowerProfileId];
        if (followTokenId == 0) {
            revert NotFollowing();
        }
        address followTokenOwner = _unsafeOwnerOf(followTokenId);
        // LensHub already validated that this action can only be performed by the unfollower profile's owner or one of
        // his approved delegated executors.
        _unfollow({unfollower: unfollowerProfileId, followTokenId: followTokenId});
        if (followTokenOwner == address(0)) {
            // Follow token was unwrapped, allowing recovery.
            _followDataByFollowTokenId[followTokenId].profileIdAllowedToRecover = unfollowerProfileId;
        }
    }

    /// @inheritdoc IFollowNFT
    function removeFollower(uint256 followTokenId) external override whenNotPaused {
        if (_isApprovedOrOwner(msg.sender, followTokenId)) {
            _unfollowIfHasFollower(followTokenId, msg.sender);
        } else {
            revert DoesNotHavePermissions();
        }
    }

    /// @inheritdoc IFollowNFT
    function approveFollow(uint256 followerProfileId, uint256 followTokenId) external override {
        if (!IERC721Timestamped(HUB).exists(followerProfileId)) {
            revert Errors.TokenDoesNotExist();
        }
        // `followTokenId` allowed to be zero as a way to clear the approval.
        if (followTokenId != 0 && _unsafeOwnerOf(followTokenId) == address(0)) {
            revert OnlyWrappedFollowTokens();
        }
        if (_isApprovedOrOwner(msg.sender, followTokenId)) {
            _approveFollow(followerProfileId, followTokenId);
        } else {
            revert DoesNotHavePermissions();
        }
    }

    /// @inheritdoc IFollowNFT
    function wrap(uint256 followTokenId, address wrappedTokenReceiver) external override whenNotPaused {
        if (wrappedTokenReceiver == address(0)) {
            revert Errors.InvalidParameter();
        }
        _wrap(followTokenId, wrappedTokenReceiver);
    }

    /// @inheritdoc IFollowNFT
    function wrap(uint256 followTokenId) external override whenNotPaused {
        _wrap(followTokenId, address(0));
    }

    function _wrap(uint256 followTokenId, address wrappedTokenReceiver) internal {
        if (_isFollowTokenWrapped(followTokenId)) {
            revert AlreadyWrapped();
        }
        uint256 followerProfileId = _followDataByFollowTokenId[followTokenId].followerProfileId;
        if (followerProfileId == 0) {
            followerProfileId = _followDataByFollowTokenId[followTokenId].profileIdAllowedToRecover;
            if (followerProfileId == 0) {
                revert FollowTokenDoesNotExist();
            }
            delete _followDataByFollowTokenId[followTokenId].profileIdAllowedToRecover;
        }
        address followerProfileOwner = IERC721(HUB).ownerOf(followerProfileId);
        if (msg.sender != followerProfileOwner) {
            revert DoesNotHavePermissions();
        }
        _mint(wrappedTokenReceiver == address(0) ? followerProfileOwner : wrappedTokenReceiver, followTokenId);
    }

    /// @inheritdoc IFollowNFT
    function unwrap(uint256 followTokenId) external override whenNotPaused {
        if (_followDataByFollowTokenId[followTokenId].followerProfileId == 0) {
            revert NotFollowing();
        }
        super.burn(followTokenId);
    }

    /// @inheritdoc IFollowNFT
    function processBlock(uint256 followerProfileId) external override onlyHub returns (bool) {
        bool hasUnfollowed;
        uint256 followTokenId = _followTokenIdByFollowerProfileId[followerProfileId];
        if (followTokenId != 0) {
            if (!_isFollowTokenWrapped(followTokenId)) {
                // Wrap it first, so the user stops following but does not lose the token when being blocked.
                _mint(IERC721(HUB).ownerOf(followerProfileId), followTokenId);
            }
            _unfollow(followerProfileId, followTokenId);
            hasUnfollowed = true;
        }
        return hasUnfollowed;
    }

    /// @inheritdoc IFollowNFT
    function getFollowerProfileId(uint256 followTokenId) external view override returns (uint256) {
        return _followDataByFollowTokenId[followTokenId].followerProfileId;
    }

    /// @inheritdoc IFollowNFT
    function isFollowing(uint256 followerProfileId) external view override returns (bool) {
        return _followTokenIdByFollowerProfileId[followerProfileId] != 0;
    }

    /// @inheritdoc IFollowNFT
    function getFollowTokenId(uint256 followerProfileId) external view override returns (uint256) {
        return _followTokenIdByFollowerProfileId[followerProfileId];
    }

    /// @inheritdoc IFollowNFT
    function getOriginalFollowTimestamp(uint256 followTokenId) external view override returns (uint256) {
        return _followDataByFollowTokenId[followTokenId].originalFollowTimestamp;
    }

    /// @inheritdoc IFollowNFT
    function getFollowTimestamp(uint256 followTokenId) external view override returns (uint256) {
        return _followDataByFollowTokenId[followTokenId].followTimestamp;
    }

    /// @inheritdoc IFollowNFT
    function getProfileIdAllowedToRecover(uint256 followTokenId) external view override returns (uint256) {
        return _followDataByFollowTokenId[followTokenId].profileIdAllowedToRecover;
    }

    /// @inheritdoc IFollowNFT
    function getFollowData(uint256 followTokenId) external view override returns (Types.FollowData memory) {
        return _followDataByFollowTokenId[followTokenId];
    }

    /// @inheritdoc IFollowNFT
    function getFollowApproved(uint256 followTokenId) external view override returns (uint256) {
        return _followApprovalByFollowTokenId[followTokenId];
    }

    /// @inheritdoc IFollowNFT
    function getFollowerCount() external view override returns (uint256) {
        return _followerCount;
    }

    function burn(uint256 followTokenId) public override whenNotPaused {
        _unfollowIfHasFollower(followTokenId, msg.sender);
        super.burn(followTokenId);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(LensBaseERC721, ERC2981CollectionRoyalties) returns (bool) {
        return
            LensBaseERC721.supportsInterface(interfaceId) || ERC2981CollectionRoyalties.supportsInterface(interfaceId);
    }

    function name() public view override returns (string memory) {
        return string(abi.encodePacked(_followedProfileId.toString(), FOLLOW_NFT_NAME_SUFFIX));
    }

    function symbol() public view override returns (string memory) {
        return string(abi.encodePacked(_followedProfileId.toString(), FOLLOW_NFT_SYMBOL_SUFFIX));
    }

    /**
     * @dev This returns the follow NFT URI fetched from the hub.
     */
    function tokenURI(uint256 followTokenId) public view override returns (string memory) {
        if (!_exists(followTokenId)) {
            revert Errors.TokenDoesNotExist();
        }
        return
            IFollowTokenURI(ILensHub(HUB).getFollowTokenURIContract()).getTokenURI(
                followTokenId,
                _followedProfileId,
                _followDataByFollowTokenId[followTokenId].originalFollowTimestamp
            );
    }

    function _followMintingNewToken(uint256 followerProfileId) internal returns (uint256) {
        uint256 followTokenIdAssigned;
        unchecked {
            followTokenIdAssigned = ++_lastFollowTokenId;
            _followerCount++;
        }
        _baseFollow({
            followerProfileId: followerProfileId,
            followTokenId: followTokenIdAssigned,
            isOriginalFollow: true
        });
        return followTokenIdAssigned;
    }

    function _followWithWrappedToken(
        uint256 followerProfileId,
        address transactionExecutor,
        uint256 followTokenId
    ) internal returns (uint256) {
        bool isFollowApproved = _followApprovalByFollowTokenId[followTokenId] == followerProfileId;
        address followerProfileOwner = IERC721(HUB).ownerOf(followerProfileId);
        if (
            !isFollowApproved &&
            !_isApprovedOrOwner(followerProfileOwner, followTokenId) &&
            !_isApprovedOrOwner(transactionExecutor, followTokenId)
        ) {
            revert DoesNotHavePermissions();
        }
        // The transactionExecutor is allowed to write the follower in that wrapped token.
        if (isFollowApproved) {
            // The `_followApprovalByFollowTokenId` was used, and now it needs to be cleared.
            _approveFollow(0, followTokenId);
        }
        _replaceFollower({
            currentFollowerProfileId: _followDataByFollowTokenId[followTokenId].followerProfileId,
            newFollowerProfileId: followerProfileId,
            followTokenId: followTokenId,
            transactionExecutor: transactionExecutor
        });
        return followTokenId;
    }

    function _followWithUnwrappedTokenFromBurnedProfile(
        uint256 followerProfileId,
        uint256 followTokenId,
        uint256 currentFollowerProfileId,
        address transactionExecutor
    ) internal returns (uint256) {
        if (IERC721Timestamped(HUB).exists(currentFollowerProfileId)) {
            revert DoesNotHavePermissions();
        }
        _replaceFollower({
            currentFollowerProfileId: currentFollowerProfileId,
            newFollowerProfileId: followerProfileId,
            followTokenId: followTokenId,
            transactionExecutor: transactionExecutor
        });
        return followTokenId;
    }

    function _followByRecoveringToken(uint256 followerProfileId, uint256 followTokenId) internal returns (uint256) {
        if (_followDataByFollowTokenId[followTokenId].profileIdAllowedToRecover != followerProfileId) {
            revert FollowTokenDoesNotExist();
        }
        unchecked {
            _followerCount++;
        }
        _baseFollow({followerProfileId: followerProfileId, followTokenId: followTokenId, isOriginalFollow: false});
        return followTokenId;
    }

    function _replaceFollower(
        uint256 currentFollowerProfileId,
        uint256 newFollowerProfileId,
        uint256 followTokenId,
        address transactionExecutor
    ) internal {
        if (currentFollowerProfileId != 0) {
            // As it has a follower, unfollow first, removing the current follower.
            delete _followTokenIdByFollowerProfileId[currentFollowerProfileId];
            ILensHub(HUB).emitUnfollowedEvent(currentFollowerProfileId, _followedProfileId, transactionExecutor);
        } else {
            unchecked {
                _followerCount++;
            }
        }
        // Perform the follow, setting a new follower.
        _baseFollow({followerProfileId: newFollowerProfileId, followTokenId: followTokenId, isOriginalFollow: false});
    }

    function _baseFollow(uint256 followerProfileId, uint256 followTokenId, bool isOriginalFollow) internal {
        _followTokenIdByFollowerProfileId[followerProfileId] = followTokenId;
        _followDataByFollowTokenId[followTokenId].followerProfileId = uint160(followerProfileId);
        _followDataByFollowTokenId[followTokenId].followTimestamp = uint48(block.timestamp);
        delete _followDataByFollowTokenId[followTokenId].profileIdAllowedToRecover;
        if (isOriginalFollow) {
            _followDataByFollowTokenId[followTokenId].originalFollowTimestamp = uint48(block.timestamp);
        } else {
            // Migration code.
            // If the follow token was minted before the originalFollowTimestamp was introduced, it will be 0.
            // In that case, we need to fetch the mint timestamp from the token data.
            if (_followDataByFollowTokenId[followTokenId].originalFollowTimestamp == 0) {
                uint48 mintTimestamp = uint48(StorageLib.getTokenData(followTokenId).mintTimestamp);
                _followDataByFollowTokenId[followTokenId].originalFollowTimestamp = mintTimestamp;
            }
        }
    }

    function _unfollowIfHasFollower(uint256 followTokenId, address transactionExecutor) internal {
        uint256 followerProfileId = _followDataByFollowTokenId[followTokenId].followerProfileId;
        if (followerProfileId != 0) {
            _unfollow(followerProfileId, followTokenId);
            ILensHub(HUB).emitUnfollowedEvent(followerProfileId, _followedProfileId, transactionExecutor);
        }
    }

    function _unfollow(uint256 unfollower, uint256 followTokenId) internal {
        unchecked {
            // This is safe, as this line can only be reached if the unfollowed profile is being followed by the
            // unfollower profile, so _followerCount is guaranteed to be greater than zero.
            _followerCount--;
        }
        delete _followTokenIdByFollowerProfileId[unfollower];
        delete _followDataByFollowTokenId[followTokenId].followerProfileId;
        delete _followDataByFollowTokenId[followTokenId].followTimestamp;
        delete _followDataByFollowTokenId[followTokenId].profileIdAllowedToRecover;
    }

    function _approveFollow(uint256 approvedProfileId, uint256 followTokenId) internal {
        _followApprovalByFollowTokenId[followTokenId] = approvedProfileId;
        emit FollowApproval(approvedProfileId, followTokenId);
    }

    /**
     * @dev Upon transfers, we clear follow approvals and emit the transfer event in the hub.
     */
    function _beforeTokenTransfer(address from, address to, uint256 followTokenId) internal override whenNotPaused {
        if (from != address(0)) {
            // It is cleared on unwrappings and transfers, and it can not be set on unwrapped tokens.
            // As a consequence, there is no need to clear it on wrappings.
            _approveFollow(0, followTokenId);
        }
        super._beforeTokenTransfer(from, to, followTokenId);
    }

    function _getReceiver(uint256 /* followTokenId */) internal view override returns (address) {
        if (!ILensHub(HUB).exists(_followedProfileId)) {
            return address(0);
        }
        return IERC721(HUB).ownerOf(_followedProfileId);
    }

    function _beforeRoyaltiesSet(uint256 /* royaltiesInBasisPoints */) internal view override {
        if (IERC721(HUB).ownerOf(_followedProfileId) != msg.sender) {
            revert Errors.NotProfileOwner();
        }
    }

    function _isFollowTokenWrapped(uint256 followTokenId) internal view returns (bool) {
        return _exists(followTokenId);
    }

    function _getRoyaltiesInBasisPointsSlot() internal pure override returns (uint256) {
        uint256 slot;
        assembly {
            slot := _royaltiesInBasisPoints.slot
        }
        return slot;
    }

    //////////////////
    /// Migrations ///
    //////////////////

    // This function shouldn't fail under no circumstances, except if wrong parameters are passed.
    function tryMigrate(
        uint256 followerProfileId,
        address followerProfileOwner,
        uint256 followTokenId
    ) external onlyHub returns (uint48) {
        // Migrated FollowNFTs should have `originalFollowTimestamp` set
        if (_followDataByFollowTokenId[followTokenId].originalFollowTimestamp != 0) {
            return 0; // Already migrated
        }

        if (_followTokenIdByFollowerProfileId[followerProfileId] != 0) {
            return 0; // Already following
        }

        Types.TokenData memory tokenData = StorageLib.getTokenData(followTokenId);

        address followTokenOwner = tokenData.owner;

        if (followTokenOwner == address(0)) {
            return 0; // Doesn't exist
        }

        // ProfileNFT and FollowNFT should be in the same account
        if (followerProfileOwner != followTokenOwner) {
            return 0; // Not holding both Profile & Follow NFTs together
        }

        unchecked {
            ++_followerCount;
        }

        _followTokenIdByFollowerProfileId[followerProfileId] = followTokenId;

        _followDataByFollowTokenId[followTokenId].followerProfileId = uint160(followerProfileId);
        _followDataByFollowTokenId[followTokenId].originalFollowTimestamp = uint48(tokenData.mintTimestamp);
        _followDataByFollowTokenId[followTokenId].followTimestamp = uint48(tokenData.mintTimestamp);

        super._burn(followTokenId);
        return uint48(tokenData.mintTimestamp);
    }
}
