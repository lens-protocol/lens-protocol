// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import 'test/base/BaseTest.t.sol';
import {ProfileLib} from 'contracts/libraries/ProfileLib.sol';
import {MockFollowModuleWithRevertFlag} from 'test/mocks/MockFollowModuleWithRevertFlag.sol';
import {IFollowModule} from 'contracts/interfaces/IFollowModule.sol';
import {ValidationLib} from 'contracts/libraries/ValidationLib.sol';

contract LensHubTest is BaseTest {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setUp() public override {
        super.setUp();
    }

    function testCannot_CreateProfile_IfPaused() public {
        vm.prank(governance);
        hub.setState(Types.ProtocolState.Paused);

        vm.expectRevert(Errors.Paused.selector);
        hub.createProfile(_getDefaultCreateProfileParams());
    }

    function testCannot_CreateProfile_IfNotWhitelistedProfileCreator(address profileCreator) public {
        vm.assume(profileCreator != address(0));
        vm.assume(hub.isProfileCreatorWhitelisted(profileCreator) == false);
        address proxyAdmin = address(uint160(uint256(vm.load(address(lensHandles), ADMIN_SLOT))));
        vm.assume(profileCreator != proxyAdmin);

        Types.CreateProfileParams memory createProfileParams = _getDefaultCreateProfileParams();

        vm.expectRevert(Errors.NotWhitelisted.selector);

        vm.prank(profileCreator);
        hub.createProfile(createProfileParams);
    }

    function testCannot_CreateProfile_IfRecipientIsZero() public {
        Types.CreateProfileParams memory createProfileParams = _getDefaultCreateProfileParams();

        createProfileParams.to = address(0);

        vm.expectRevert(Errors.InvalidParameter.selector);
        hub.createProfile(createProfileParams);
    }

    function testCreateProfile_WithNoFollowModule(address to) public {
        vm.assume(to != address(0));

        address followModule = address(0);
        bytes memory followModuleInitData = '';

        Types.CreateProfileParams memory createProfileParams = Types.CreateProfileParams({
            to: to,
            followModule: followModule,
            followModuleInitData: followModuleInitData
        });

        uint256 expectedProfileId = uint256(vm.load(address(hub), bytes32(uint256(22)))) + 1;

        vm.expectEmit(true, true, true, true, address(hub));
        emit Transfer(address(0), to, expectedProfileId);

        vm.expectEmit(true, true, true, true, address(hub));
        emit Events.ProfileCreated(expectedProfileId, address(this), to, block.timestamp);

        vm.expectEmit(true, true, true, true, address(hub));
        emit Events.FollowModuleSet(
            expectedProfileId,
            followModule,
            followModuleInitData,
            '',
            address(this),
            block.timestamp
        );

        uint256 profileId = hub.createProfile(createProfileParams);

        assertEq(profileId, expectedProfileId);
        assertEq(hub.ownerOf(profileId), to);

        Types.Profile memory profile = hub.getProfile(profileId);

        assertEq(profile.followModule, followModule);
        assertEq(profile.pubCount, 0);
    }

    function testCreateProfile_WithFollowModule(address to) public {
        vm.assume(to != address(0));

        address followModule = address(new MockFollowModuleWithRevertFlag(address(this)));

        bytes memory followModuleInitData = abi.encode(false);

        Types.CreateProfileParams memory createProfileParams = Types.CreateProfileParams({
            to: to,
            followModule: followModule,
            followModuleInitData: followModuleInitData
        });

        uint256 expectedProfileId = uint256(vm.load(address(hub), bytes32(uint256(22)))) + 1;

        vm.expectEmit(true, true, true, true, address(hub));
        emit Transfer(address(0), to, expectedProfileId);

        vm.expectEmit(true, true, true, true, address(hub));
        emit Events.ProfileCreated(expectedProfileId, address(this), to, block.timestamp);

        vm.expectEmit(true, true, true, true, address(hub));
        emit Events.FollowModuleSet(
            expectedProfileId,
            followModule,
            followModuleInitData,
            '',
            address(this),
            block.timestamp
        );

        vm.expectCall(
            address(followModule),
            abi.encodeCall(
                IFollowModule.initializeFollowModule,
                (expectedProfileId, address(this), followModuleInitData)
            )
        );

        uint256 profileId = hub.createProfile(createProfileParams);

        assertEq(profileId, expectedProfileId);
        assertEq(hub.ownerOf(profileId), to);

        Types.Profile memory profile = hub.getProfile(profileId);

        assertEq(profile.followModule, followModule);
        assertEq(profile.pubCount, 0);

        Types.TokenData memory tokenData = hub.tokenDataOf(profileId);
        assertEq(tokenData.owner, to);
        assertEq(tokenData.mintTimestamp, block.timestamp);
    }

    function testGetContentURI() public {
        string memory contentURI = 'ipfs://randomContentUri1234567890';
        Types.PostParams memory postParams = _getDefaultPostParams();
        postParams.contentURI = contentURI;

        vm.prank(defaultAccount.owner);
        uint256 pubId = hub.post(postParams);

        assertEq(hub.getContentURI(defaultAccount.profileId, pubId), contentURI);
    }
}
