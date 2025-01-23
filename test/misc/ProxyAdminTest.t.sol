// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import 'test/base/BaseTest.t.sol';
import {ProxyAdmin} from 'contracts/misc/access/ProxyAdmin.sol';

contract MockContract {
    function testMockContract() public {
        // Prevents being counted in Foundry Coverage
    }

    function initialize(address initializationAddress) public pure {}
}

contract ProxyAdminTest is BaseTest {
    using stdJson for string;

    error Unauthorized();

    address controllerContract = makeAddr('CONTROLLER_CONTRACT');
    address proxyAdminContractOwner;

    function setUp() public override {
        super.setUp();

        loadOrDeploy_ProxyAdminContract();

        vm.prank(proxyAdmin);
        hubAsProxy.changeAdmin(address(proxyAdminContract));

        proxyAdminContractOwner = proxyAdminContract.owner();

        vm.prank(proxyAdminContractOwner);
        proxyAdminContract.setControllerContract(controllerContract);
    }

    // Negatives

    function testCannot_rollbackLastUpgrade_ifNotOwner(address otherAddress) public {
        vm.assume(otherAddress != proxyAdminContractOwner);
        vm.expectRevert('Ownable: caller is not the owner');
        vm.prank(otherAddress);
        proxyAdminContract.rollbackLastUpgrade();
    }

    function testCannot_changeLensHubProxyAdmin_ifNotOwner(address newAdmin, address otherAddress) public {
        vm.assume(otherAddress != proxyAdminContractOwner);
        vm.assume(newAdmin != address(0));
        vm.expectRevert('Ownable: caller is not the owner');
        vm.prank(otherAddress);
        proxyAdminContract.proxy_changeAdmin(newAdmin);
    }

    function testCannot_upgrade_ifNotOwnerOrControllerContract(address otherAddress) public {
        address hubImplV2 = address(new MockContract());

        vm.assume(otherAddress != proxyAdminContractOwner);
        vm.assume(otherAddress != controllerContract);

        vm.expectRevert(Unauthorized.selector);
        vm.prank(otherAddress);
        proxyAdminContract.proxy_upgrade(hubImplV2);
    }

    function testCannot_upgradeAndCall_ifNotOwnerOrControllerContract(address otherAddress) public {
        address hubImplV2 = address(new MockContract());

        vm.assume(otherAddress != proxyAdminContractOwner);
        vm.assume(otherAddress != controllerContract);

        vm.expectRevert(Unauthorized.selector);
        vm.prank(otherAddress);
        proxyAdminContract.proxy_upgradeAndCall(
            hubImplV2,
            abi.encodeWithSelector(MockContract.initialize.selector, address(0xdeadbeef))
        );
    }

    // Scenarios

    function testConstructor() public notFork {
        assertEq(address(proxyAdminContract.LENS_HUB_PROXY()), address(hub), 'Hub address is not set correctly');
        assertEq(
            proxyAdminContract.previousImplementation(),
            address(hubImpl),
            'Hub implementation is not set correctly'
        );
        assertEq(proxyAdminContract.owner(), proxyAdminContractOwner, 'Owner is not set correctly');
        assertEq(proxyAdminContract.controllerContract(), controllerContract, 'Controller is not set correctly');
    }

    function testCurrentImplementation() public {
        assertEq(proxyAdminContract.currentImplementation(), address(hubImpl));
    }

    function testRollbackLastUpgrade() public {
        address hubImplV2 = address(new MockContract());

        address prevImpl;

        if (forkVersion == 1) {
            prevImpl = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
            assertEq(prevImpl, proxyAdminContract.previousImplementation());

            vm.prank(proxyAdminContractOwner);
            proxyAdminContract.proxy_upgrade(hubImplV2);

            address newImpl = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
            assertEq(newImpl, hubImplV2);
        } else {
            prevImpl = proxyAdminContract.previousImplementation();
        }

        vm.expectCall(address(hubAsProxy), abi.encodeCall(hubAsProxy.upgradeTo, (prevImpl)));

        vm.prank(proxyAdminContractOwner);
        proxyAdminContract.rollbackLastUpgrade();

        address rolledBackImpl = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
        assertEq(rolledBackImpl, prevImpl);
    }

    function testChangeLensHubProxyAdmin(address newAdmin) public {
        vm.assume(newAdmin != address(0));
        address currentProxyAdmin = address(uint160(uint256(vm.load(hubProxyAddr, ADMIN_SLOT))));
        vm.assume(newAdmin != currentProxyAdmin);

        vm.expectCall(address(hubAsProxy), abi.encodeCall(hubAsProxy.changeAdmin, (newAdmin)));
        vm.prank(proxyAdminContractOwner);
        proxyAdminContract.proxy_changeAdmin(newAdmin);

        address changedProxyAdmin = address(uint160(uint256(vm.load(hubProxyAddr, ADMIN_SLOT))));
        assertEq(changedProxyAdmin, newAdmin);
    }

    function testUpgrade_ifCalledByOwner() public {
        address hubImplV2 = address(new MockContract());

        address prevImpl = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
        assertTrue(prevImpl != hubImplV2);

        vm.expectCall(address(hubAsProxy), abi.encodeCall(hubAsProxy.upgradeTo, (hubImplV2)));
        vm.prank(proxyAdminContractOwner);
        proxyAdminContract.proxy_upgrade(hubImplV2);

        address upgradedImpl = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
        assertEq(upgradedImpl, hubImplV2);

        assertEq(proxyAdminContract.previousImplementation(), prevImpl);
        assertEq(proxyAdminContract.controllerContract(), address(0)); // Controller is cleared after upgrade
    }

    function testUpgrade_ifCalledByControllerContract() public {
        address hubImplV2 = address(new MockContract());

        address prevImpl = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
        assertTrue(prevImpl != hubImplV2);

        vm.expectCall(address(hubAsProxy), abi.encodeCall(hubAsProxy.upgradeTo, (hubImplV2)));
        vm.prank(controllerContract);
        proxyAdminContract.proxy_upgrade(hubImplV2);

        address upgradedImpl = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
        assertEq(upgradedImpl, hubImplV2);

        assertEq(proxyAdminContract.previousImplementation(), prevImpl);
        assertEq(proxyAdminContract.controllerContract(), address(0)); // Controller is cleared after upgrade
    }

    function testUpgradeAndCall_ifCalledByOwner() public {
        address hubImplV2 = address(new MockContract());

        address prevImpl = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
        assertTrue(prevImpl != hubImplV2);

        bytes memory data = abi.encodeCall(MockContract.initialize, (address(0xdeadbeef)));

        vm.expectCall(address(hubAsProxy), abi.encodeCall(hubAsProxy.upgradeToAndCall, (hubImplV2, data)));
        vm.expectCall(address(hubImplV2), data);
        vm.prank(proxyAdminContractOwner);
        proxyAdminContract.proxy_upgradeAndCall(hubImplV2, data);

        address upgradedImpl = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
        assertEq(upgradedImpl, hubImplV2);

        assertEq(proxyAdminContract.previousImplementation(), prevImpl);
        assertEq(proxyAdminContract.controllerContract(), address(0)); // Controller is cleared after upgrade
    }

    function testUpgradeAndCall_ifCalledByControllerContract() public {
        address hubImplV2 = address(new MockContract());

        address prevImpl = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
        assertTrue(prevImpl != hubImplV2);

        bytes memory data = abi.encodeCall(MockContract.initialize, (address(0xdeadbeef)));

        vm.expectCall(address(hubAsProxy), abi.encodeCall(hubAsProxy.upgradeToAndCall, (hubImplV2, data)));
        vm.expectCall(address(hubImplV2), data);
        vm.prank(controllerContract);
        proxyAdminContract.proxy_upgradeAndCall(hubImplV2, data);

        address upgradedImpl = address(uint160(uint256(vm.load(hubProxyAddr, PROXY_IMPLEMENTATION_STORAGE_SLOT))));
        assertEq(upgradedImpl, hubImplV2);

        assertEq(proxyAdminContract.previousImplementation(), prevImpl);
        assertEq(proxyAdminContract.controllerContract(), address(0)); // Controller is cleared after upgrade
    }
}
