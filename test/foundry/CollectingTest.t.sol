// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import './base/BaseTest.t.sol';
import './helpers/SignatureHelpers.sol';
import './helpers/CollectingHelpers.sol';
import './MetaTxNegatives.t.sol';

// TODO add check for _initialize() called for fork tests - check name and symbol set

contract CollectingTest is BaseTest, CollectingHelpers, SigSetup {
    uint256 constant collectorProfileOwnerPk = 0xC011EEC7012;
    address collectorProfileOwner;
    uint256 collectorProfileId;

    uint256 constant userWithoutProfilePk = 0x105312;
    address userWithoutProfile;

    function setUp() public virtual override(SigSetup, TestSetup) {
        TestSetup.setUp();
        SigSetup.setUp();

        vm.prank(profileOwner);
        hub.post(mockPostParams);

        collectorProfileOwner = vm.addr(collectorProfileOwnerPk);
        collectorProfileId = _createProfile(collectorProfileOwner);

        userWithoutProfile = vm.addr(userWithoutProfilePk);

        mockCollectParams.collectorProfileId = collectorProfileId;
    }

    function _collect(
        uint256, /* metaTxSignerPk */
        address transactionExecutor,
        Types.CollectParams memory collectParams
    ) internal virtual returns (uint256) {
        vm.prank(transactionExecutor);
        return hub.collect(collectParams);
    }

    // NEGATIVES

    // Also acts like a test for cannot collect specifying another (non-owned) profile as a parameter
    function testCannotCollectIfNotExecutor() public {
        vm.expectRevert(Errors.ExecutorInvalid.selector);
        _collect(collectorProfileOwnerPk, otherSigner, mockCollectParams);
    }

    function testCannotCollectIfNonexistantPub() public {
        mockCollectParams.publicationCollectedId = 2;
        // Check that the publication doesn't exist.
        assertEq(
            _getPub(mockCollectParams.publicationCollectedProfileId, mockCollectParams.publicationCollectedId)
                .pointedProfileId,
            0
        );

        vm.expectRevert(Errors.CollectNotAllowed.selector);
        _collect(collectorProfileOwnerPk, collectorProfileOwner, mockCollectParams);
        vm.stopPrank();
    }

    function testCannotCollectIfZeroPub() public {
        mockCollectParams.publicationCollectedId = 0;
        // Check that the publication doesn't exist.
        assertEq(
            _getPub(mockCollectParams.publicationCollectedProfileId, mockCollectParams.publicationCollectedId)
                .pointedProfileId,
            0
        );

        vm.expectRevert(Errors.CollectNotAllowed.selector);
        _collect(collectorProfileOwnerPk, collectorProfileOwner, mockCollectParams);
        vm.stopPrank();
    }

    function testCannotCollect_WithoutProfile() public {
        mockCollectParams.collectorProfileId = _getNextProfileId(); // Non-existent profile
        vm.expectRevert(Errors.TokenDoesNotExist.selector);
        _collect(userWithoutProfilePk, userWithoutProfile, mockCollectParams);
        vm.stopPrank();
    }

    function testCannotCollectIfBlocked() public {
        vm.prank(profileOwner);
        hub.setBlockStatus(newProfileId, _toUint256Array(collectorProfileId), _toBoolArray(true));
        vm.expectRevert(Errors.Blocked.selector);
        _collect(collectorProfileOwnerPk, collectorProfileOwner, mockCollectParams);
    }

    function testCannotCollectMirror() public {
        _checkCollectNFTBefore();

        // Mirror once
        vm.prank(profileOwner);
        uint256 mirrorPubId = hub.mirror(mockMirrorParams);

        // Collecting the mirror
        mockCollectParams.publicationCollectedId = mirrorPubId;

        vm.expectRevert(Errors.CollectNotAllowed.selector);
        _collect(collectorProfileOwnerPk, collectorProfileOwner, mockCollectParams);
    }

    // SCENARIOS

    function testCollect() public {
        uint256 startNftId = _checkCollectNFTBefore();

        uint256 nftId = _collect(collectorProfileOwnerPk, collectorProfileOwner, mockCollectParams);

        _checkCollectNFTAfter(nftId, startNftId + 1);
    }

    function testCollectMirror() public {
        uint256 startNftId = _checkCollectNFTBefore();

        vm.prank(profileOwner);
        hub.mirror(mockMirrorParams);

        uint256 nftId = _collect(collectorProfileOwnerPk, collectorProfileOwner, mockCollectParams);

        _checkCollectNFTAfter(nftId, startNftId + 1);
    }

    function testExecutorCollect() public {
        uint256 startNftId = _checkCollectNFTBefore();

        // delegate power to executor
        _changeDelegatedExecutorsConfig(collectorProfileOwner, collectorProfileId, otherSigner, true);

        // collect from executor
        uint256 nftId = _collect(otherSignerKey, otherSigner, mockCollectParams);

        _checkCollectNFTAfter(nftId, startNftId + 1);
    }

    function testExecutorCollectMirror() public {
        uint256 startNftId = _checkCollectNFTBefore();

        // mirror, then delegate power to executor
        vm.prank(profileOwner);
        hub.mirror(mockMirrorParams);
        _changeDelegatedExecutorsConfig(collectorProfileOwner, collectorProfileId, otherSigner, true);

        // collect from executor
        uint256 nftId = _collect(otherSignerKey, otherSigner, mockCollectParams);

        _checkCollectNFTAfter(nftId, startNftId + 1);
    }
}

contract CollectingTestMetaTx is CollectingTest, MetaTxNegatives {
    mapping(address => uint256) cachedNonceByAddress;

    function setUp() public override(CollectingTest, MetaTxNegatives) {
        CollectingTest.setUp();
        MetaTxNegatives.setUp();

        cachedNonceByAddress[collectorProfileOwner] = _getSigNonce(collectorProfileOwner);
    }

    function _collect(
        uint256 metaTxSignerPk,
        address transactionExecutor,
        Types.CollectParams memory collectParams
    ) internal override returns (uint256) {
        address signer = vm.addr(metaTxSignerPk);
        uint256 deadline = type(uint256).max;
        bytes32 digest = _getCollectTypedDataHash(collectParams, cachedNonceByAddress[signer], deadline);
        return hub.collectWithSig(collectParams, _getSigStruct(transactionExecutor, metaTxSignerPk, digest, deadline));
    }

    function _executeMetaTx(
        uint256 signerPk,
        uint256 nonce,
        uint256 deadline
    ) internal override {
        _collectWithSig(
            mockCollectParams,
            _getSigStruct(
                vm.addr(_getDefaultMetaTxSignerPk()),
                signerPk,
                _getCollectTypedDataHash(mockCollectParams, nonce, deadline),
                deadline
            )
        );
    }

    function _getDefaultMetaTxSignerPk() internal pure override returns (uint256) {
        return collectorProfileOwnerPk;
    }
}
