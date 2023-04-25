// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import 'test/base/BaseTest.t.sol';
import 'test/helpers/SignatureHelpers.sol';

contract MultiStateHubTest_Common is BaseTest {
    // Negatives
    function testCannotSetStateAsRegularUser() public {
        vm.expectRevert(Errors.NotGovernanceOrEmergencyAdmin.selector);
        hub.setState(Types.ProtocolState.Paused);

        vm.expectRevert(Errors.NotGovernanceOrEmergencyAdmin.selector);
        hub.setState(Types.ProtocolState.PublishingPaused);

        vm.expectRevert(Errors.NotGovernanceOrEmergencyAdmin.selector);
        hub.setState(Types.ProtocolState.Unpaused);
    }

    function testCannotSetEmergencyAdminAsRegularUser() public {
        vm.expectRevert(Errors.NotGovernance.selector);
        hub.setEmergencyAdmin(address(this));
    }

    function testCannotUnpauseAsEmergencyAdmin() public {
        vm.prank(governance);
        hub.setEmergencyAdmin(address(this));

        vm.expectRevert(Errors.EmergencyAdminCanOnlyPauseFurther.selector);
        hub.setState(Types.ProtocolState.Unpaused);
    }

    function testCannotSetLowerStateAsEmergencyAdmin() public {
        vm.prank(governance);
        hub.setEmergencyAdmin(address(this));

        hub.setState(Types.ProtocolState.Paused);

        vm.expectRevert(Errors.EmergencyAdminCanOnlyPauseFurther.selector);
        hub.setState(Types.ProtocolState.PublishingPaused);

        vm.expectRevert(Errors.EmergencyAdminCanOnlyPauseFurther.selector);
        hub.setState(Types.ProtocolState.Paused);
    }

    function testCannotSetEmergencyAdminAsEmergencyAdmin() public {
        vm.prank(governance);
        hub.setEmergencyAdmin(address(this));

        vm.expectRevert(Errors.NotGovernance.selector);
        hub.setEmergencyAdmin(address(0));
    }

    // Scenarios
    function testSetProtocolStateAsEmergencyAdmin() public {
        vm.prank(governance);
        hub.setEmergencyAdmin(address(this));

        Types.ProtocolState[2] memory states = [Types.ProtocolState.PublishingPaused, Types.ProtocolState.Paused];

        for (uint256 i = 0; i < states.length; i++) {
            Types.ProtocolState newState = states[i];
            Types.ProtocolState prevState = hub.getState();
            hub.setState(newState);
            Types.ProtocolState curState = hub.getState();
            assertTrue(newState == curState);
            assertTrue(curState != prevState);
        }
    }

    function testSetProtocolStateAsGovernance() public {
        vm.startPrank(governance);

        Types.ProtocolState[6] memory states = [
            Types.ProtocolState.PublishingPaused,
            Types.ProtocolState.Paused,
            Types.ProtocolState.Unpaused,
            Types.ProtocolState.Paused,
            Types.ProtocolState.PublishingPaused,
            Types.ProtocolState.Unpaused
        ];

        for (uint256 i = 0; i < states.length; i++) {
            Types.ProtocolState newState = states[i];
            Types.ProtocolState prevState = hub.getState();
            hub.setState(newState);
            Types.ProtocolState curState = hub.getState();
            assertTrue(newState == curState);
            assertTrue(curState != prevState);
        }
        vm.stopPrank();
    }

    function testGovernanceCanRevokeEmergencyAdmin() public {
        vm.prank(governance);
        hub.setEmergencyAdmin(address(this));

        hub.setState(Types.ProtocolState.PublishingPaused);

        vm.prank(governance);
        hub.setEmergencyAdmin(address(0));

        vm.expectRevert(Errors.NotGovernanceOrEmergencyAdmin.selector);
        hub.setState(Types.ProtocolState.Paused);
    }
}

contract MultiStateHubTest_PausedState_Direct is BaseTest {
    uint256 postId;
    uint256 followerProfileId;

    function setUp() public virtual override {
        super.setUp();

        followerProfileId = _createProfile(address(this));

        vm.prank(defaultAccount.owner);
        postId = hub.post(mockPostParams);

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Paused);
    }

    // TODO: Consider extracting these mock actions functions somewhere because they're used in several places
    function _mockSetFollowModule() internal virtual {
        vm.prank(defaultAccount.owner);
        hub.setFollowModule(defaultAccount.profileId, address(0), '');
    }

    function _mockChangeDelegatedExecutorsConfig() internal virtual {
        address delegatedExecutor = otherSigner.owner;
        bool approved = true;
        vm.prank(defaultAccount.owner);
        hub.changeDelegatedExecutorsConfig({
            delegatorProfileId: defaultAccount.profileId,
            delegatedExecutors: _toAddressArray(delegatedExecutor),
            approvals: _toBoolArray(approved)
        });
    }

    function _mockSetProfileImageURI() internal virtual {
        vm.prank(defaultAccount.owner);
        hub.setProfileImageURI(defaultAccount.profileId, MOCK_URI);
    }

    function _mockPost() internal virtual {
        vm.prank(defaultAccount.owner);
        hub.post(mockPostParams);
    }

    function _mockComment() internal virtual {
        mockCommentParams.pointedPubId = postId;
        vm.prank(defaultAccount.owner);
        hub.comment(mockCommentParams);
    }

    function _mockMirror() internal virtual {
        mockMirrorParams.pointedPubId = postId;
        vm.prank(defaultAccount.owner);
        hub.mirror(mockMirrorParams);
    }

    function _mockBurn() internal virtual {
        vm.prank(defaultAccount.owner);
        hub.burn(defaultAccount.profileId);
    }

    function _mockFollow() internal virtual {
        hub.follow(followerProfileId, _toUint256Array(defaultAccount.profileId), _toUint256Array(0), _toBytesArray(''));
    }

    function _mockAct() internal virtual {
        vm.prank(defaultAccount.owner);
        hub.act(mockActParams);
    }

    // Negatives
    function testCannotTransferProfileWhilePaused() public virtual {
        vm.expectRevert(Errors.Paused.selector);
        vm.prank(defaultAccount.owner);
        hub.transferFrom(defaultAccount.owner, address(111), defaultAccount.profileId);
    }

    function testCannotCreateProfileWhilePaused() public virtual {
        vm.expectRevert(Errors.Paused.selector);
        _createProfile(address(this));

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _createProfile(address(this));
    }

    function testCannotSetFollowModuleWhilePaused() public {
        vm.expectRevert(Errors.Paused.selector);
        _mockSetFollowModule();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockSetFollowModule();
    }

    function testCannotSetDelegatedExecutorWhilePaused() public {
        vm.expectRevert(Errors.Paused.selector);
        _mockChangeDelegatedExecutorsConfig();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockChangeDelegatedExecutorsConfig();
    }

    function testCannotSetProfileImageURIWhilePaused() public {
        vm.expectRevert(Errors.Paused.selector);
        _mockSetProfileImageURI();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockSetProfileImageURI();
    }

    function testCannotPostWhilePaused() public {
        vm.expectRevert(Errors.PublishingPaused.selector);
        _mockPost();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockPost();
    }

    function testCannotCommentWhilePaused() public {
        vm.expectRevert(Errors.PublishingPaused.selector);
        _mockComment();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockComment();
    }

    function testCannotMirrorWhilePaused() public {
        vm.expectRevert(Errors.PublishingPaused.selector);
        _mockMirror();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockMirror();
    }

    function testCannotBurnWhilePaused() public {
        vm.expectRevert(Errors.Paused.selector);
        _mockBurn();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockBurn();
    }

    function testCannotFollowWhilePaused() public {
        vm.expectRevert(Errors.Paused.selector);
        _mockFollow();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockFollow();
    }

    function testActCollectWhilePaused() public {
        vm.expectRevert(Errors.Paused.selector);
        _mockAct();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockAct();
    }
}

contract MultiStateHubTest_PausedState_WithSig is MultiStateHubTest_PausedState_Direct, SigSetup {
    function setUp() public override(MultiStateHubTest_PausedState_Direct, SigSetup) {
        MultiStateHubTest_PausedState_Direct.setUp();
        SigSetup.setUp();
        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);
        followerProfileId = _createProfile(otherSigner.owner);
        vm.prank(governance);
        hub.setState(Types.ProtocolState.Paused);
    }

    function _mockSetFollowModule() internal override {
        bytes32 digest = _getSetFollowModuleTypedDataHash(defaultAccount.profileId, address(0), '', nonce, deadline);

        hub.setFollowModuleWithSig({
            profileId: defaultAccount.profileId,
            followModule: address(0),
            followModuleInitData: '',
            signature: _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline)
        });
    }

    // Positives
    function _mockChangeDelegatedExecutorsConfig() internal override {
        address delegatedExecutor = otherSigner.owner;

        bytes32 digest = _getChangeDelegatedExecutorsConfigTypedDataHash({
            delegatorProfileId: defaultAccount.profileId,
            delegatedExecutors: _toAddressArray(delegatedExecutor),
            approvals: _toBoolArray(true),
            configNumber: 0,
            switchToGivenConfig: true,
            nonce: nonce,
            deadline: deadline
        });
        hub.changeDelegatedExecutorsConfigWithSig({
            delegatorProfileId: defaultAccount.profileId,
            delegatedExecutors: _toAddressArray(delegatedExecutor),
            approvals: _toBoolArray(true),
            configNumber: 0,
            switchToGivenConfig: true,
            signature: _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline)
        });
    }

    function _mockSetProfileImageURI() internal override {
        bytes32 digest = _getSetProfileImageURITypedDataHash(defaultAccount.profileId, MOCK_URI, nonce, deadline);

        hub.setProfileImageURIWithSig({
            profileId: defaultAccount.profileId,
            imageURI: MOCK_URI,
            signature: _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline)
        });
    }

    function _mockPost() internal override {
        bytes32 digest = _getPostTypedDataHash(mockPostParams, nonce, deadline);

        hub.postWithSig(mockPostParams, _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline));
    }

    function _mockComment() internal override {
        mockCommentParams.pointedPubId = postId;
        bytes32 digest = _getCommentTypedDataHash(mockCommentParams, nonce, deadline);

        hub.commentWithSig(
            mockCommentParams,
            _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline)
        );
    }

    function _mockMirror() internal override {
        mockMirrorParams.pointedPubId = postId;
        bytes32 digest = _getMirrorTypedDataHash(mockMirrorParams, nonce, deadline);

        hub.mirrorWithSig(
            mockMirrorParams,
            _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline)
        );
    }

    function _mockFollow() internal override {
        bytes32 digest = _getFollowTypedDataHash(
            followerProfileId,
            _toUint256Array(defaultAccount.profileId),
            _toUint256Array(0),
            _toBytesArray(''),
            nonce,
            deadline
        );

        hub.followWithSig({
            followerProfileId: followerProfileId,
            idsOfProfilesToFollow: _toUint256Array(defaultAccount.profileId),
            followTokenIds: _toUint256Array(0),
            datas: _toBytesArray(''),
            signature: _getSigStruct(otherSigner.ownerPk, digest, deadline)
        });
    }

    function _mockAct() internal override {
        bytes32 digest = _getActTypedDataHash(mockActParams, nonce, deadline);

        hub.actWithSig(mockActParams, _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline));
    }

    // Methods that cannot be called with signature
    function testCannotTransferProfileWhilePaused() public override {}

    function testCannotCreateProfileWhilePaused() public override {}
}

contract MultiStateHubTest_PublishingPausedState_Direct is BaseTest {
    uint256 postId;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(defaultAccount.owner);
        postId = hub.post(mockPostParams);

        vm.prank(governance);
        hub.setState(Types.ProtocolState.PublishingPaused);
    }

    // TODO: Consider extracting these mock actions functions somewhere because they're used in several places
    function _mockSetFollowModule() internal virtual {
        vm.prank(defaultAccount.owner);
        hub.setFollowModule(defaultAccount.profileId, address(0), '');
    }

    function _mockChangeDelegatedExecutorsConfig() internal virtual {
        address delegatedExecutor = otherSigner.owner;
        bool approved = true;
        vm.prank(defaultAccount.owner);
        hub.changeDelegatedExecutorsConfig({
            delegatorProfileId: defaultAccount.profileId,
            delegatedExecutors: _toAddressArray(delegatedExecutor),
            approvals: _toBoolArray(approved)
        });
    }

    function _mockSetProfileImageURI() internal virtual {
        vm.prank(defaultAccount.owner);
        hub.setProfileImageURI(defaultAccount.profileId, MOCK_URI);
    }

    function _mockPost() internal virtual {
        vm.prank(defaultAccount.owner);
        hub.post(mockPostParams);
    }

    function _mockComment() internal virtual {
        mockCommentParams.pointedPubId = postId;
        vm.prank(defaultAccount.owner);
        hub.comment(mockCommentParams);
    }

    function _mockMirror() internal virtual {
        mockMirrorParams.pointedPubId = postId;
        vm.prank(defaultAccount.owner);
        hub.mirror(mockMirrorParams);
    }

    function _mockBurn() internal virtual {
        vm.prank(defaultAccount.owner);
        hub.burn(defaultAccount.profileId);
    }

    function _mockFollow() internal virtual {
        hub.follow(
            _createProfile(address(this)),
            _toUint256Array(defaultAccount.profileId),
            _toUint256Array(0),
            _toBytesArray('')
        );
    }

    // TODO: The following two functions were copy-pasted from CollectingTest.t.sol
    // TODO: Consider extracting them somewhere else to be used by both of tests
    function _mockAct() internal virtual {
        vm.prank(defaultAccount.owner);
        hub.act(mockActParams);
    }

    // Negatives
    function testCanTransferProfileWhilePublishingPaused() public virtual {
        vm.prank(defaultAccount.owner);
        hub.transferFrom(defaultAccount.owner, address(111), defaultAccount.profileId);
    }

    function testCanCreateProfileWhilePublishingPaused() public virtual {
        _createProfile(address(this));
    }

    function testCanSetFollowModuleWhilePublishingPaused() public {
        _mockSetFollowModule();
    }

    function testCanSetDelegatedExecutorWhilePublishingPaused() public {
        _mockChangeDelegatedExecutorsConfig();
    }

    function testCanSetProfileImageURIWhilePublishingPaused() public {
        _mockSetProfileImageURI();
    }

    function testCanBurnWhilePublishingPaused() public {
        _mockBurn();
    }

    function testCanFollowWhilePublishingPaused() public {
        _mockFollow();
    }

    function testCanCollectWhilePublishingPaused() public {
        _mockAct();
    }

    function testCannotPostWhilePublishingPaused() public {
        vm.expectRevert(Errors.PublishingPaused.selector);
        _mockPost();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockPost();
    }

    function testCannotCommentWhilePublishingPaused() public {
        vm.expectRevert(Errors.PublishingPaused.selector);
        _mockComment();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockComment();
    }

    function testCannotMirrorWhilePublishingPaused() public {
        vm.expectRevert(Errors.PublishingPaused.selector);
        _mockMirror();

        vm.prank(governance);
        hub.setState(Types.ProtocolState.Unpaused);

        _mockMirror();
    }
}

contract MultiStateHubTest_PublishingPausedState_WithSig is MultiStateHubTest_PublishingPausedState_Direct, SigSetup {
    // TODO: Consider refactoring this contract somehow cause it's all just pure copy-paste of the PausedState_WithSig
    function setUp() public override(MultiStateHubTest_PublishingPausedState_Direct, SigSetup) {
        MultiStateHubTest_PublishingPausedState_Direct.setUp();
        SigSetup.setUp();
    }

    function _mockSetFollowModule() internal override {
        bytes32 digest = _getSetFollowModuleTypedDataHash(defaultAccount.profileId, address(0), '', nonce, deadline);

        hub.setFollowModuleWithSig({
            profileId: defaultAccount.profileId,
            followModule: address(0),
            followModuleInitData: '',
            signature: _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline)
        });
    }

    // Positives
    function _mockChangeDelegatedExecutorsConfig() internal override {
        address delegatedExecutor = otherSigner.owner;

        bytes32 digest = _getChangeDelegatedExecutorsConfigTypedDataHash({
            delegatorProfileId: defaultAccount.profileId,
            delegatedExecutors: _toAddressArray(delegatedExecutor),
            approvals: _toBoolArray(true),
            configNumber: 0,
            switchToGivenConfig: true,
            nonce: nonce,
            deadline: deadline
        });
        hub.changeDelegatedExecutorsConfigWithSig({
            delegatorProfileId: defaultAccount.profileId,
            delegatedExecutors: _toAddressArray(delegatedExecutor),
            approvals: _toBoolArray(true),
            configNumber: 0,
            switchToGivenConfig: true,
            signature: _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline)
        });
    }

    function _mockSetProfileImageURI() internal override {
        bytes32 digest = _getSetProfileImageURITypedDataHash(defaultAccount.profileId, MOCK_URI, nonce, deadline);

        hub.setProfileImageURIWithSig({
            profileId: defaultAccount.profileId,
            imageURI: MOCK_URI,
            signature: _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline)
        });
    }

    function _mockPost() internal override {
        bytes32 digest = _getPostTypedDataHash(mockPostParams, nonce, deadline);

        hub.postWithSig(mockPostParams, _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline));
    }

    function _mockComment() internal override {
        mockCommentParams.pointedPubId = postId;
        bytes32 digest = _getCommentTypedDataHash(mockCommentParams, nonce, deadline);

        hub.commentWithSig(
            mockCommentParams,
            _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline)
        );
    }

    function _mockMirror() internal override {
        mockMirrorParams.pointedPubId = postId;
        bytes32 digest = _getMirrorTypedDataHash(mockMirrorParams, nonce, deadline);

        hub.mirrorWithSig(
            mockMirrorParams,
            _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline)
        );
    }

    function _mockFollow() internal override {
        uint256 followerProfileId = _createProfile(otherSigner.owner);
        bytes32 digest = _getFollowTypedDataHash(
            followerProfileId,
            _toUint256Array(defaultAccount.profileId),
            _toUint256Array(0),
            _toBytesArray(''),
            nonce,
            deadline
        );

        hub.followWithSig({
            followerProfileId: followerProfileId,
            idsOfProfilesToFollow: _toUint256Array(defaultAccount.profileId),
            followTokenIds: _toUint256Array(0),
            datas: _toBytesArray(''),
            signature: _getSigStruct(otherSigner.ownerPk, digest, deadline)
        });
    }

    function _mockAct() internal override {
        bytes32 digest = _getActTypedDataHash(mockActParams, nonce, deadline);

        hub.actWithSig(mockActParams, _getSigStruct(defaultAccount.owner, defaultAccount.ownerPk, digest, deadline));
    }

    // Methods that cannot be called with signature
    function testCanTransferProfileWhilePublishingPaused() public override {}

    function testCanCreateProfileWhilePublishingPaused() public override {}
}
