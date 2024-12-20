// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ForkManagement} from 'script/helpers/ForkManagement.sol';
import 'forge-std/Script.sol';
import {LensV2UpgradeContract} from 'contracts/misc/LensV2UpgradeContract.sol';
import {FollowNFT} from 'contracts/FollowNFT.sol';
import {LensHandles} from 'contracts/namespaces/LensHandles.sol';
import {TokenHandleRegistry} from 'contracts/namespaces/TokenHandleRegistry.sol';
import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {Governance} from 'contracts/misc/access/Governance.sol';
import {LensV2UpgradeContract} from 'contracts/misc/LensV2UpgradeContract.sol';
import {LensHubInitializable} from 'contracts/misc/LensHubInitializable.sol';
import {ILensHub} from 'contracts/interfaces/ILensHub.sol';
import {ILensHandles} from 'contracts/interfaces/ILensHandles.sol';
import {ITokenHandleRegistry} from 'contracts/interfaces/ITokenHandleRegistry.sol';
import {ProfileCreationProxy} from 'contracts/misc/ProfileCreationProxy.sol';
import {CollectNFT} from 'contracts/modules/act/collect/CollectNFT.sol';
import {CollectPublicationAction} from 'contracts/modules/act/collect/CollectPublicationAction.sol';
import {SimpleFeeCollectModule} from 'contracts/modules/act/collect/SimpleFeeCollectModule.sol';
import {MultirecipientFeeCollectModule} from 'contracts/modules/act/collect/MultirecipientFeeCollectModule.sol';
import {RevertFollowModule} from 'contracts/modules/follow/RevertFollowModule.sol';
import {DegreesOfSeparationReferenceModule} from 'contracts/modules/reference/DegreesOfSeparationReferenceModule.sol';
import {FollowerOnlyReferenceModule} from 'contracts/modules/reference/FollowerOnlyReferenceModule.sol';
import {TokenGatedReferenceModule} from 'contracts/modules/reference/TokenGatedReferenceModule.sol';
import {ModuleRegistry} from 'contracts/misc/ModuleRegistry.sol';
import {Governance} from 'contracts/misc/access/Governance.sol';
import {PublicActProxy} from 'contracts/misc/PublicActProxy.sol';
import {LitAccessControl} from 'contracts/misc/access/LitAccessControl.sol';
import {LibString} from 'solady/utils/LibString.sol';

import {ArrayHelpers} from 'script/helpers/ArrayHelpers.sol';

contract S02_DeployLensV2Periphery is Script, ForkManagement, ArrayHelpers {
    // add this to be excluded from coverage report
    function testLensV2DeployPeriphery() public {}

    using stdJson for string;

    string addressesFile = 'addressesV2.txt';

    string mnemonic;

    struct LensAccount {
        uint256 ownerPk;
        address owner;
        uint256 profileId;
    }

    LensAccount deployer;
    LensAccount governance;
    Governance governanceContract;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    address profileCreator;
    address governanceContractAdmin;
    address proxyAdminContractAdmin;

    ModuleRegistry moduleRegistryImpl;
    TransparentUpgradeableProxy moduleRegistryProxy;
    ModuleRegistry moduleRegistry;
    FollowNFT followNFT;
    LensHubInitializable lensHubImpl;
    TransparentUpgradeableProxy hubProxy;
    ILensHub hub;
    LensHandles handlesImpl;
    TransparentUpgradeableProxy handlesProxy;
    ILensHandles handles;
    TokenHandleRegistry tokenHandleRegistryImpl;
    TransparentUpgradeableProxy tokenHandleRegistryProxy;
    ITokenHandleRegistry tokenHandleRegistry;
    ProfileCreationProxy profileCreationProxy;
    CollectNFT collectNFT;
    CollectPublicationAction collectPublicationActionImpl;
    TransparentUpgradeableProxy collectPublicationActionProxy;
    CollectPublicationAction collectPublicationAction;
    SimpleFeeCollectModule simpleFeeCollectModule;
    MultirecipientFeeCollectModule multirecipientFeeCollectModule;
    RevertFollowModule revertFollowModule;
    DegreesOfSeparationReferenceModule degreesOfSeparationReferenceModule;
    FollowerOnlyReferenceModule followerOnlyReferenceModule;
    TokenGatedReferenceModule tokenGatedReferenceModule;
    PublicActProxy publicActProxy;
    address litAccessControl;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function saveContractAddress(string memory contractName, address deployedAddress) internal {
        // console.log('Saving %s (%s) into addresses under %s environment', contractName, deployedAddress, targetEnv);
        string[] memory inputs = new string[](5);
        inputs[0] = 'node';
        inputs[1] = 'script/helpers/saveAddress.js';
        inputs[2] = targetEnv;
        inputs[3] = contractName;
        inputs[4] = vm.toString(deployedAddress);
        // bytes memory res =
        vm.ffi(inputs);
        // string memory output = abi.decode(res, (string));
        // console.log(output);
    }

    function saveValue(string memory contractName, string memory str) internal {
        // console.log('Saving %s (%s) into addresses under %s environment', contractName, deployedAddress, targetEnv);
        string[] memory inputs = new string[](5);
        inputs[0] = 'node';
        inputs[1] = 'script/helpers/saveAddress.js';
        inputs[2] = targetEnv;
        inputs[3] = contractName;
        inputs[4] = str;
        // bytes memory res =
        vm.ffi(inputs);
        // string memory output = abi.decode(res, (string));
        // console.log(output);
    }

    function saveModule(
        string memory moduleName,
        address moduleAddress,
        string memory lensVersion,
        string memory moduleType
    ) internal {
        // console.log('Saving %s (%s) into addresses under %s environment', moduleName, moduleAddress, targetEnv);
        string[] memory inputs = new string[](7);
        inputs[0] = 'node';
        inputs[1] = 'script/helpers/saveAddress.js';
        inputs[2] = targetEnv;
        inputs[3] = moduleName;
        inputs[4] = vm.toString(moduleAddress);
        inputs[5] = lensVersion;
        inputs[6] = moduleType;
        // bytes memory res =
        vm.ffi(inputs);
        // string memory output = abi.decode(res, (string));
        // console.log(output);
    }

    function loadPrivateKeys() internal {
        if (isEnvSet('MNEMONIC')) {
            mnemonic = vm.envString('MNEMONIC');
        }

        if (bytes(mnemonic).length == 0) {
            revert('Missing mnemonic');
        }

        console.log('\n- - - CURRENT BLOCK: ', block.number);

        (deployer.owner, deployer.ownerPk) = deriveRememberKey(mnemonic, 0);
        console.log('\n- - - DEPLOYER: %s', deployer.owner);
        (governance.owner, governance.ownerPk) = deriveRememberKey(mnemonic, 1);
        console.log('\n- - - GOVERNANCE: %s', governance.owner);
    }

    function loadBaseAddresses() internal override {
        governanceContractAdmin = json.readAddress(
            string(abi.encodePacked('.', targetEnv, '.GovernanceContractAdmin'))
        );

        if (isEnvSet('DEPLOYMENT_ENVIRONMENT')) {
            if (LibString.eq(vm.envString('DEPLOYMENT_ENVIRONMENT'), 'production')) {} else {
                console.log('DEPLOYMENT_ENVIRONMENT is not production');
                revert();
            }
        } else {
            if (governance.owner != governanceContractAdmin) {
                console.log(
                    'Mock Governance %s != Governance contract admin %s',
                    governance.owner,
                    governanceContractAdmin
                );
                revert();
            }
        }

        profileCreator = json.readAddress(string(abi.encodePacked('.', targetEnv, '.ProfileCreator')));
        vm.label(profileCreator, 'ProfileCreator');
        console.log('ProfileCreator: %s', profileCreator);

        proxyAdminContractAdmin = json.readAddress(
            string(abi.encodePacked('.', targetEnv, '.ProxyAdminContractAdmin'))
        );
        vm.label(proxyAdminContractAdmin, 'ProxyAdminContractAdmin');
        console.log('ProxyAdminContractAdmin: %s', proxyAdminContractAdmin);

        hub = ILensHub(json.readAddress(string(abi.encodePacked('.', targetEnv, '.LensHub'))));
        vm.label(address(hub), 'LensHub');
        console.log('Lens Hub Proxy: %s', address(hub));

        handles = ILensHandles(json.readAddress(string(abi.encodePacked('.', targetEnv, '.LensHandles'))));
        vm.label(address(handles), 'LensHandles');
        console.log('Lens Handles: %s', address(handles));

        tokenHandleRegistry = ITokenHandleRegistry(
            json.readAddress(string(abi.encodePacked('.', targetEnv, '.TokenHandleRegistry')))
        );
        vm.label(address(tokenHandleRegistry), 'TokenHandleRegistry');
        console.log('Token Handle Registry: %s', address(tokenHandleRegistry));

        moduleRegistry = ModuleRegistry(json.readAddress(string(abi.encodePacked('.', targetEnv, '.ModuleRegistry'))));
        vm.label(address(moduleRegistry), 'ModuleRegistry');
        console.log('Module Registry: %s', address(moduleRegistry));

        governanceContract = Governance(
            json.readAddress(string(abi.encodePacked('.', targetEnv, '.GovernanceContract')))
        );
        vm.label(address(governanceContract), 'GovernanceContract');
        console.log('Governance Contract: %s', address(governanceContract));
    }

    function deploy() internal {
        vm.startBroadcast(deployer.ownerPk);

        if (governanceContractAdmin == address(0)) {
            console.log('GovernanceContractAdmin is not set');
            revert('GovernanceContractAdmin is not set');
        }

        profileCreationProxy = new ProfileCreationProxy({
            owner: profileCreator,
            hub: address(hub),
            lensHandles: address(handles),
            tokenHandleRegistry: address(tokenHandleRegistry)
        });
        console.log('\n+ + + ProfileCreationProxy: %s', address(profileCreationProxy));
        vm.writeLine(
            addressesFile,
            string.concat('ProfileCreationProxy: ', vm.toString(address(profileCreationProxy)))
        );
        vm.label(address(profileCreationProxy), 'ProfileCreationProxy');
        saveContractAddress('ProfileCreationProxy', address(profileCreationProxy));

        publicActProxy = new PublicActProxy({lensHub: address(hub)});
        console.log('\n+ + + PublicActProxy: %s', address(publicActProxy));
        vm.writeLine(addressesFile, string.concat('PublicActProxy: ', vm.toString(address(publicActProxy))));
        vm.label(address(publicActProxy), 'PublicActProxy');
        saveContractAddress('PublicActProxy', address(publicActProxy));

        uint256 currentDeployerNonce = vm.getNonce(deployer.owner);
        /**
         * CollectNFT (currentDeployerNonce)
         * CollectPublicationAction aka CollectPublicationActionImpl (currentDeployerNonce + 1)
         * TransparentUpgradeableProxy aka CollectPublicationActionProxy (currentDeployerNonce + 2)
         */
        uint256 collectPublicationActionProxyDeploymentNonce = currentDeployerNonce + 2;
        address expectedCollectPublicationActionProxyAddress = computeCreateAddress(
            deployer.owner,
            collectPublicationActionProxyDeploymentNonce
        );

        collectNFT = new CollectNFT({hub: address(hub), actionModule: expectedCollectPublicationActionProxyAddress});
        console.log('\n+ + + CollectNFT: %s', address(collectNFT));
        vm.writeLine(addressesFile, string.concat('CollectNFT: ', vm.toString(address(collectNFT))));
        vm.label(address(collectNFT), 'CollectNFT');
        saveContractAddress('CollectNFT', address(collectNFT));

        collectPublicationActionImpl = new CollectPublicationAction({
            hub: address(hub),
            collectNFTImpl: address(collectNFT),
            moduleOwner: governanceContractAdmin
        });
        console.log('\n+ + + CollectPublicationActionImpl: %s', address(collectPublicationActionImpl));
        vm.writeLine(
            addressesFile,
            string.concat('CollectPublicationActionImpl: ', vm.toString(address(collectPublicationActionImpl)))
        );
        vm.label(address(collectPublicationActionImpl), 'CollectPublicationActionImpl');
        saveContractAddress('CollectPublicationActionImpl', address(collectPublicationActionImpl));

        collectPublicationActionProxy = new TransparentUpgradeableProxy({
            _logic: address(collectPublicationActionImpl),
            admin_: proxyAdminContractAdmin,
            _data: abi.encodeWithSelector(collectPublicationActionImpl.initialize.selector, governanceContractAdmin)
        });

        if (CollectPublicationAction(address(collectPublicationActionProxy)).owner() != governanceContractAdmin) {
            console.log('ModuleOwner is not initialized for CollectPublicationAction');
            revert('ModuleOwner is not initialized for CollectPublicationAction');
        }

        console.log('\n+ + + CollectPublicationActionProxy: %s', address(collectPublicationActionProxy));
        vm.writeLine(
            addressesFile,
            string.concat('CollectPublicationActionProxy: ', vm.toString(address(collectPublicationActionProxy)))
        );
        vm.label(address(collectPublicationActionProxy), 'CollectPublicationAction');
        saveModule('CollectPublicationAction', address(collectPublicationActionProxy), 'v2', 'act');

        collectPublicationAction = CollectPublicationAction(address(collectPublicationActionProxy));

        simpleFeeCollectModule = new SimpleFeeCollectModule({
            hub: address(hub),
            actionModule: address(collectPublicationActionProxy),
            moduleRegistry: address(moduleRegistry),
            moduleOwner: governanceContractAdmin
        });
        console.log('\n+ + + SimpleFeeCollectModule: %s', address(simpleFeeCollectModule));
        vm.writeLine(
            addressesFile,
            string.concat('SimpleFeeCollectModule: ', vm.toString(address(simpleFeeCollectModule)))
        );
        vm.label(address(simpleFeeCollectModule), 'SimpleFeeCollectModule');
        saveModule('SimpleFeeCollectModule', address(simpleFeeCollectModule), 'v2', 'collect');

        multirecipientFeeCollectModule = new MultirecipientFeeCollectModule({
            hub: address(hub),
            actionModule: address(collectPublicationActionProxy),
            moduleRegistry: address(moduleRegistry),
            moduleOwner: governanceContractAdmin
        });
        console.log('\n+ + + MultirecipientFeeCollectModule: %s', address(multirecipientFeeCollectModule));
        vm.writeLine(
            addressesFile,
            string.concat('MultirecipientFeeCollectModule: ', vm.toString(address(multirecipientFeeCollectModule)))
        );
        vm.label(address(multirecipientFeeCollectModule), 'MultirecipientFeeCollectModule');
        saveModule('MultirecipientFeeCollectModule', address(multirecipientFeeCollectModule), 'v2', 'collect');

        revertFollowModule = new RevertFollowModule(governanceContractAdmin);
        console.log('\n+ + + RevertFollowModule: %s', address(revertFollowModule));
        vm.writeLine(addressesFile, string.concat('RevertFollowModule: ', vm.toString(address(revertFollowModule))));
        vm.label(address(revertFollowModule), 'RevertFollowModule');
        saveModule('RevertFollowModule', address(revertFollowModule), 'v2', 'follow');

        degreesOfSeparationReferenceModule = new DegreesOfSeparationReferenceModule({
            hub: address(hub),
            moduleOwner: governanceContractAdmin
        });
        console.log('\n+ + + DegreesOfSeparationReferenceModule: %s', address(degreesOfSeparationReferenceModule));
        vm.writeLine(
            addressesFile,
            string.concat(
                'DegreesOfSeparationReferenceModule: ',
                vm.toString(address(degreesOfSeparationReferenceModule))
            )
        );
        vm.label(address(degreesOfSeparationReferenceModule), 'DegreesOfSeparationReferenceModule');
        saveModule(
            'DegreesOfSeparationReferenceModule',
            address(degreesOfSeparationReferenceModule),
            'v2',
            'reference'
        );

        followerOnlyReferenceModule = new FollowerOnlyReferenceModule({
            hub: address(hub),
            moduleOwner: governanceContractAdmin
        });
        console.log('\n+ + + FollowerOnlyReferenceModule: %s', address(followerOnlyReferenceModule));
        vm.writeLine(
            addressesFile,
            string.concat('FollowerOnlyReferenceModule: ', vm.toString(address(followerOnlyReferenceModule)))
        );
        vm.label(address(followerOnlyReferenceModule), 'FollowerOnlyReferenceModule');
        saveModule('FollowerOnlyReferenceModule', address(followerOnlyReferenceModule), 'v2', 'reference');

        // TODO: TokenGatedReferenceModule temporarily removed from the deployment
        // tokenGatedReferenceModule = new TokenGatedReferenceModule({hub: address(hub)});
        // console.log('\n+ + + TokenGatedReferenceModule: %s', address(tokenGatedReferenceModule));
        // vm.writeLine(
        //     addressesFile,
        //     string.concat('TokenGatedReferenceModule: ', vm.toString(address(tokenGatedReferenceModule)))
        // );

        address litAccessControlImpl = address(new LitAccessControl(address(hub), address(collectPublicationAction)));
        console.log('\n+ + + LitAccessControlImpl: %s', litAccessControlImpl);
        vm.writeLine(addressesFile, string.concat('LitAccessControlImpl: ', vm.toString(litAccessControlImpl)));
        vm.label(litAccessControlImpl, 'LitAccessControlImpl');
        saveContractAddress('LitAccessControlImpl', litAccessControlImpl);

        litAccessControl = address(
            new TransparentUpgradeableProxy({_logic: litAccessControlImpl, admin_: proxyAdminContractAdmin, _data: ''})
        );
        console.log('\n+ + + LitAccessControl: %s', litAccessControl);
        vm.writeLine(addressesFile, string.concat('LitAccessControl: ', vm.toString(litAccessControl)));
        vm.label(litAccessControl, 'LitAccessControl');
        saveContractAddress('LitAccessControl', litAccessControl);

        vm.stopBroadcast();
    }

    function _writeBackendEnvFile() internal {
        string memory backendEnv = 'backendEnv.txt';
        vm.writeLine(backendEnv, '## Hub');
        vm.writeLine(backendEnv, string.concat('LENS_HUB_PROXY=', vm.toString(address(hub))));
        vm.writeLine(backendEnv, '## LensHandles');
        vm.writeLine(backendEnv, string.concat('LENS_HANDLE_PROXY=', vm.toString(address(handles))));
        vm.writeLine(backendEnv, '# TokenHandleRegistry');
        vm.writeLine(
            backendEnv,
            string.concat('LENS_TOKEN_HANDLE_REGISTRY_PROXY=', vm.toString(address(tokenHandleRegistry)))
        );
        vm.writeLine(backendEnv, '# Collection open actions');
        vm.writeLine(
            backendEnv,
            string.concat('LENS_COLLECT_PUBLICATION_ACTION_PROXY=', vm.toString(address(collectPublicationAction)))
        );
        vm.writeLine(backendEnv, '## Profile creation proxy');
        vm.writeLine(backendEnv, string.concat('PROFILE_CREATION_PROXY=', vm.toString(address(profileCreationProxy))));
        vm.writeLine(backendEnv, '## ModuleGlobals');
        vm.writeLine(backendEnv, string.concat('GLOBAL_MODULE=', vm.toString(address(moduleRegistry))));
        vm.writeLine(backendEnv, '# v2 modules');
        vm.writeLine(
            backendEnv,
            string.concat(
                'MULTIRECIPIENT_FEE_COLLECT_OPEN_ACTION_MODULE=',
                vm.toString(address(multirecipientFeeCollectModule))
            )
        );
        vm.writeLine(
            backendEnv,
            string.concat('SIMPLE_COLLECT_OPEN_ACTION_MODULE=', vm.toString(address(simpleFeeCollectModule)))
        );
        vm.writeLine(backendEnv, '### follow modules');
        vm.writeLine(backendEnv, string.concat('REVERT_FOLLOW_MODULE=', vm.toString(address(revertFollowModule))));
        vm.writeLine(backendEnv, '## REFERENCE MODULES');
        vm.writeLine(
            backendEnv,
            string.concat('FOLLOWER_ONLY_REFERENCE_MODULE=', vm.toString(address(followerOnlyReferenceModule)))
        );
        vm.writeLine(
            backendEnv,
            string.concat(
                'DEGREE_OF_SEPARATION_REFERENCE_MODULE=',
                vm.toString(address(degreesOfSeparationReferenceModule))
            )
        );
    }

    function run(string memory targetEnv_) external {
        targetEnv = targetEnv_;
        loadJson();
        checkNetworkParams();
        loadPrivateKeys();
        loadBaseAddresses();
        deploy();
        _writeBackendEnvFile();
    }
}
