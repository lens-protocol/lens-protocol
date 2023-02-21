// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IEIP1271Implementer} from 'contracts/interfaces/IEIP1271Implementer.sol';
import {Types} from 'contracts/libraries/constants/Types.sol';
import {Errors} from 'contracts/libraries/constants/Errors.sol';
import {GeneralHelpers} from 'contracts/libraries/GeneralHelpers.sol';
import {Typehash} from 'contracts/libraries/constants/Typehash.sol';
import 'contracts/libraries/Constants.sol';

/**
 * @title MetaTxLib
 * @author Lens Protocol
 *
 * @notice This is the library used by the GeneralLib that contains the logic for signature
 * validation.
 *
 * NOTE: the baseFunctions in this contract operate under the assumption that the passed signer is already validated
 * to either be the originator or one of their delegated executors.
 *
 * @dev The functions are internal, so they are inlined into the GeneralLib. User nonces
 * are incremented from this library as well.
 */
library MetaTxLib {
    bytes32 constant EIP712_REVISION_HASH = keccak256('2');

    /**
     * @dev We store the domain separator and LensHub Proxy address as constants to save gas.
     *
     * keccak256(
     *     abi.encode(
     *         keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
     *         keccak256('Lens Protocol Profiles'), // Contract Name
     *         keccak256('2'), // Revision Hash
     *         137, // Polygon Chain ID
     *         address(0xDb46d1Dc155634FbC732f92E853b10B288AD5a1d) // Verifying Contract Address - LensHub Address
     *     )
     * );
     */
    bytes32 constant LENS_HUB_CACHED_POLYGON_DOMAIN_SEPARATOR =
        0xbf9544cf7d7a0338fc4f071be35409a61e51e9caef559305410ad74e16a05f2d; // TODO: Test this on a fork

    address constant LENS_HUB_ADDRESS = 0xDb46d1Dc155634FbC732f92E853b10B288AD5a1d;

    function validateSetProfileMetadataURISignature(
        Types.EIP712Signature calldata signature,
        uint256 profileId,
        string calldata metadataURI
    ) internal {
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.SET_PROFILE_METADATA_URI,
                        profileId,
                        keccak256(bytes(metadataURI)),
                        _sigNonces(signature.signer),
                        signature.deadline
                    )
                )
            ),
            signature
        );
    }

    function validateSetFollowModuleSignature(
        Types.EIP712Signature calldata signature,
        uint256 profileId,
        address followModule,
        bytes calldata followModuleInitData
    ) internal {
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.SET_FOLLOW_MODULE,
                        profileId,
                        followModule,
                        keccak256(followModuleInitData),
                        _sigNonces(signature.signer),
                        signature.deadline
                    )
                )
            ),
            signature
        );
    }

    function validateChangeDelegatedExecutorsConfigSignature(
        Types.EIP712Signature calldata signature,
        uint256 delegatorProfileId,
        address[] calldata executors,
        bool[] calldata approvals,
        uint64 configNumber,
        bool switchToGivenConfig
    ) internal {
        uint256 nonce = _sigNonces(signature.signer);
        uint256 deadline = signature.deadline;
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.CHANGE_DELEGATED_EXECUTORS_CONFIG,
                        delegatorProfileId,
                        abi.encodePacked(executors),
                        abi.encodePacked(approvals),
                        configNumber,
                        switchToGivenConfig,
                        nonce,
                        deadline
                    )
                )
            ),
            signature
        );
    }

    function validateSetProfileImageURISignature(
        Types.EIP712Signature calldata signature,
        uint256 profileId,
        string calldata imageURI
    ) internal {
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.SET_PROFILE_IMAGE_URI,
                        profileId,
                        keccak256(bytes(imageURI)),
                        _sigNonces(signature.signer),
                        signature.deadline
                    )
                )
            ),
            signature
        );
    }

    function validateSetFollowNFTURISignature(
        Types.EIP712Signature calldata signature,
        uint256 profileId,
        string calldata followNFTURI
    ) internal {
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.SET_FOLLOW_NFT_URI,
                        profileId,
                        keccak256(bytes(followNFTURI)),
                        _sigNonces(signature.signer),
                        signature.deadline
                    )
                )
            ),
            signature
        );
    }

    function validatePostSignature(Types.EIP712Signature calldata signature, Types.PostParams calldata postParams)
        internal
    {
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.POST,
                        postParams.profileId,
                        keccak256(bytes(postParams.contentURI)),
                        postParams.collectModule,
                        keccak256(postParams.collectModuleInitData),
                        postParams.referenceModule,
                        keccak256(postParams.referenceModuleInitData),
                        _sigNonces(signature.signer),
                        signature.deadline
                    )
                )
            ),
            signature
        );
    }

    function validateCommentSignature(
        Types.EIP712Signature calldata signature,
        Types.CommentParams calldata commentParams
    ) internal {
        uint256 nonce = _sigNonces(signature.signer);
        uint256 deadline = signature.deadline;
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.COMMENT,
                        commentParams.profileId,
                        keccak256(bytes(commentParams.contentURI)),
                        commentParams.pointedProfileId,
                        commentParams.pointedPubId,
                        commentParams.referrerProfileId,
                        commentParams.referrerPubId,
                        keccak256(commentParams.referenceModuleData),
                        commentParams.collectModule,
                        keccak256(commentParams.collectModuleInitData),
                        commentParams.referenceModule,
                        keccak256(commentParams.referenceModuleInitData),
                        nonce,
                        deadline
                    )
                )
            ),
            signature
        );
    }

    function validateQuoteSignature(Types.EIP712Signature calldata signature, Types.QuoteParams calldata quoteParams)
        internal
    {
        uint256 nonce = _sigNonces(signature.signer);
        uint256 deadline = signature.deadline;
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.COMMENT,
                        quoteParams.profileId,
                        keccak256(bytes(quoteParams.contentURI)),
                        quoteParams.pointedProfileId,
                        quoteParams.pointedPubId,
                        keccak256(quoteParams.referenceModuleData),
                        quoteParams.referrerProfileId,
                        quoteParams.referrerPubId,
                        quoteParams.collectModule,
                        keccak256(quoteParams.collectModuleInitData),
                        quoteParams.referenceModule,
                        keccak256(quoteParams.referenceModuleInitData),
                        nonce,
                        deadline
                    )
                )
            ),
            signature
        );
    }

    function validateMirrorSignature(Types.EIP712Signature calldata signature, Types.MirrorParams calldata mirrorParams)
        internal
    {
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.MIRROR,
                        mirrorParams.profileId,
                        mirrorParams.pointedProfileId,
                        mirrorParams.pointedPubId,
                        mirrorParams.referrerProfileId,
                        mirrorParams.referrerPubId,
                        keccak256(mirrorParams.referenceModuleData),
                        _sigNonces(signature.signer),
                        signature.deadline
                    )
                )
            ),
            signature
        );
    }

    function validateBurnSignature(Types.EIP712Signature calldata signature, uint256 tokenId) internal {
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(abi.encode(Typehash.BURN, tokenId, _sigNonces(signature.signer), signature.deadline))
            ),
            signature
        );
    }

    function validateFollowSignature(
        Types.EIP712Signature calldata signature,
        uint256 followerProfileId,
        uint256[] calldata idsOfProfilesToFollow,
        uint256[] calldata followTokenIds,
        bytes[] calldata datas
    ) internal {
        uint256 dataLength = datas.length;
        bytes32[] memory dataHashes = new bytes32[](dataLength);
        for (uint256 i = 0; i < dataLength; ) {
            dataHashes[i] = keccak256(datas[i]);
            unchecked {
                ++i;
            }
        }
        uint256 nonce = _sigNonces(signature.signer);
        uint256 deadline = signature.deadline;

        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.FOLLOW,
                        followerProfileId,
                        keccak256(abi.encodePacked(idsOfProfilesToFollow)),
                        keccak256(abi.encodePacked(followTokenIds)),
                        keccak256(abi.encodePacked(dataHashes)),
                        nonce,
                        deadline
                    )
                )
            ),
            signature
        );
    }

    function validateUnfollowSignature(
        Types.EIP712Signature calldata signature,
        uint256 unfollowerProfileId,
        uint256[] calldata idsOfProfilesToUnfollow
    ) internal {
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.UNFOLLOW,
                        unfollowerProfileId,
                        keccak256(abi.encodePacked(idsOfProfilesToUnfollow)),
                        _sigNonces(signature.signer),
                        signature.deadline
                    )
                )
            ),
            signature
        );
    }

    function validateSetBlockStatusSignature(
        Types.EIP712Signature calldata signature,
        uint256 byProfileId,
        uint256[] calldata idsOfProfilesToSetBlockStatus,
        bool[] calldata blockStatus
    ) internal {
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.SET_BLOCK_STATUS,
                        byProfileId,
                        keccak256(abi.encodePacked(idsOfProfilesToSetBlockStatus)),
                        keccak256(abi.encodePacked(blockStatus)),
                        _sigNonces(signature.signer),
                        signature.deadline
                    )
                )
            ),
            signature
        );
    }

    function validateCollectSignature(
        Types.EIP712Signature calldata signature,
        Types.CollectParams calldata collectParams
    ) internal {
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(
                        Typehash.COLLECT,
                        collectParams.publicationCollectedProfileId,
                        collectParams.publicationCollectedId,
                        collectParams.collectorProfileId,
                        collectParams.referrerProfileId,
                        collectParams.referrerPubId,
                        keccak256(collectParams.collectModuleData),
                        _sigNonces(signature.signer),
                        signature.deadline
                    )
                )
            ),
            signature
        );
    }

    function validatePermitSignature(
        Types.EIP712Signature calldata signature,
        address spender,
        uint256 tokenId
    ) internal {
        _validateRecoveredAddress(
            _calculateDigest(
                keccak256(
                    abi.encode(Typehash.PERMIT, spender, tokenId, _sigNonces(signature.signer), signature.deadline)
                )
            ),
            signature
        );
    }

    function getDomainSeparator() internal view returns (bytes32) {
        return _calculateDomainSeparator();
    }

    /**
     * @dev Wrapper for ecrecover to reduce code size, used in meta-tx specific functions.
     */
    function _validateRecoveredAddress(bytes32 digest, Types.EIP712Signature calldata signature) internal view {
        if (signature.deadline < block.timestamp) revert Errors.SignatureExpired();
        // If the expected address is a contract, check the signature there.
        if (signature.signer.code.length != 0) {
            bytes memory concatenatedSig = abi.encodePacked(signature.r, signature.s, signature.v);
            if (
                IEIP1271Implementer(signature.signer).isValidSignature(digest, concatenatedSig) != EIP1271_MAGIC_VALUE
            ) {
                revert Errors.SignatureInvalid();
            }
        } else {
            address recoveredAddress = ecrecover(digest, signature.v, signature.r, signature.s);
            if (recoveredAddress == address(0) || recoveredAddress != signature.signer) {
                revert Errors.SignatureInvalid();
            }
        }
    }

    /**
     * @dev Calculates EIP712 DOMAIN_SEPARATOR based on the current contract and chain ID.
     */
    function _calculateDomainSeparator() private view returns (bytes32) {
        if (address(this) == LENS_HUB_ADDRESS) {
            return LENS_HUB_CACHED_POLYGON_DOMAIN_SEPARATOR;
        }
        return
            keccak256(
                abi.encode(
                    Typehash.EIP712_DOMAIN,
                    keccak256(_nameBytes()),
                    EIP712_REVISION_HASH,
                    block.chainid,
                    address(this)
                )
            );
    }

    /**
     * @dev Calculates EIP712 digest based on the current DOMAIN_SEPARATOR.
     *
     * @param hashedMessage The message hash from which the digest should be calculated.
     *
     * @return bytes32 A 32-byte output representing the EIP712 digest.
     */
    function _calculateDigest(bytes32 hashedMessage) private view returns (bytes32) {
        bytes32 digest;
        unchecked {
            digest = keccak256(abi.encodePacked('\x19\x01', _calculateDomainSeparator(), hashedMessage));
        }
        return digest;
    }

    /**
     * @dev This fetches a user's signing nonce and increments it, akin to `sigNonces++`.
     *
     * @param user The user address to fetch and post-increment the signing nonce for.
     *
     * @return uint256 The signing nonce for the given user prior to being incremented.
     */
    function _sigNonces(address user) private returns (uint256) {
        uint256 previousValue;
        assembly {
            mstore(0, user)
            mstore(32, SIG_NONCES_MAPPING_SLOT)
            let slot := keccak256(0, 64)
            previousValue := sload(slot)
            sstore(slot, add(previousValue, 1))
        }
        return previousValue;
    }

    /**
     * @dev Reads the name storage slot and returns the value as a bytes variable.
     *
     * @return bytes The contract's name.
     */
    function _nameBytes() private view returns (bytes memory) {
        bytes memory ptr;
        assembly {
            // Load the free memory pointer, where we'll return the value
            ptr := mload(64)

            // Load the slot, which either contains the name + 2*length if length < 32 or
            // 2*length+1 if length >= 32, and the actual string starts at slot keccak256(NAME_SLOT)
            let slotLoad := sload(NAME_SLOT)

            let size
            // Determine if the length > 32 by checking the lowest order bit, meaning the string
            // itself is stored at keccak256(NAME_SLOT)
            switch and(slotLoad, 1)
            case 0 {
                // The name is in the same slot
                // Determine the size by dividing the last byte's value by 2
                size := shr(1, and(slotLoad, 255))

                // Store the size in the first slot
                mstore(ptr, size)

                // Store the actual string in the second slot (without the size)
                mstore(add(ptr, 32), and(slotLoad, not(255)))
            }
            case 1 {
                // The name is not in the same slot
                // Determine the size by dividing the value in the whole slot minus 1 by 2
                size := shr(1, sub(slotLoad, 1))

                // Store the size in the first slot
                mstore(ptr, size)

                // Compute the total memory slots we need, this is (size + 31) / 32
                let totalMemorySlots := shr(5, add(size, 31))

                // Iterate through the words in memory and store the string word by word
                // prettier-ignore
                for { let i := 0 } lt(i, totalMemorySlots) { i := add(i, 1) } {
                    mstore(add(add(ptr, 32), mul(32, i)), sload(add(NAME_SLOT_GT_31, i)))
                }
            }
            // Store the new memory pointer in the free memory pointer slot
            mstore(64, add(add(ptr, 32), size))
        }
        return ptr;
    }
}
