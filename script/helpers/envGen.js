// This is a script that transforms addresses.json into backendEnv.txt

const path = require('path');

const findModule = (moduleType, moduleName, version) => {
  const module = addresses['Modules'][version][moduleType].find(
    (module) => module.name === moduleName
  );
  if (!module) {
    return '0x0000000000000000000000000000000000000000';
  } else {
    return module.addy;
  }
};

const addressOrZero = (addressKey) => {
  return addresses[addressKey] || '0x0000000000000000000000000000000000000000';
};

const addressesPath = '../../addresses.json';

const addressesJson = require(path.join(__dirname, addressesPath));
const [targetEnv] = process.argv.slice(2);

if (!addressesJson[targetEnv]) {
  console.error(`ERROR: Target environment "${targetEnv}" not found in addresses.json`);
  process.exit(1);
}

const addresses = addressesJson[targetEnv];

// Let's make sure to clear the backendEnv.txt first
const fs = require('fs');
fs.writeFileSync(`./backendEnv_${targetEnv}.txt`, '');

// And then write to backendEnv.txt line by line
const str = fs.createWriteStream(`./backendEnv_${targetEnv}.txt`, { flags: 'a' });

str.write(`# Hub\n`);
str.write(`LENS_HUB_PROXY=${addresses['LensHub']}\n`);

str.write(`\n# LensHandles\n`);
str.write(`LENS_HANDLE_PROXY=${addresses['LensHandles']}\n`);

str.write(`\n# TokenHandleRegistry\n`);
str.write(`LENS_TOKEN_HANDLE_REGISTRY_PROXY=${addresses['TokenHandleRegistry']}\n`);

str.write(`\n# Public Act Proxy\n`);
str.write(`LENS_PUBLIC_ACT_PROXY=${addresses['PublicActProxy']}\n`);

str.write(`\n# Profile creation proxy\n`);
str.write(`PROFILE_CREATION_PROXY=${addressOrZero('ProfileCreationProxy')}\n`);

str.write(`\n# Permissionless creator\n`);
str.write(`PERMISSIONLESS_CREATOR=${addresses['PermissionlessCreator']}\n`);

str.write(`\n# Credits faucet\n`);
str.write(`CREDITS_FAUCET=${addressOrZero('CreditsFaucet')}\n`);

str.write(`\n# Legacy ModuleGlobals for V1 (deprecated and removed in v2)\n`);
str.write(`LEGACY_MODULE_GLOBALS=${addressOrZero('ModuleGlobals')}\n`);

str.write(`\n# ModuleRegistry (for V2)\n`);
str.write(`GLOBAL_MODULE_REGISTRY=${addresses['ModuleRegistry']}\n`);

str.write(`\n# Legacy metadata updates\n`);
str.write(`LEGACY_PERIPHERY_DATA_PROVIDER=${addressOrZero('LensPeriphery')}\n`);

// LEGACY COLLECT MODULES

str.write(`\n# legacy modules\n`);
str.write(`## legacy collect modules\n`);
str.write(`LEGACY_FEE_COLLECT_MODULE=${findModule('collect', 'FeeCollectModule', 'v1')}\n`);
str.write(
  `LEGACY_LIMITED_FEE_COLLECT_MODULE=${findModule('collect', 'LimitedFeeCollectModule', 'v1')}\n`
);
str.write(
  `LEGACY_TIMED_FEE_COLLECT_MODULE=${findModule('collect', 'TimedFeeCollectModule', 'v1')}\n`
);
str.write(
  `LEGACY_LIMITED_TIMED_FEE_COLLECT_MODULE=${findModule(
    'collect',
    'LimitedTimedFeeCollectModule',
    'v1'
  )}\n`
);
str.write(`LEGACY_REVERT_COLLECT_MODULE=${findModule('collect', 'RevertCollectModule', 'v1')}\n`);
str.write(`LEGACY_FREE_COLLECT_MODULE=${findModule('collect', 'FreeCollectModule', 'v1')}\n`);
str.write(
  `LEGACY_SIMPLE_COLLECT_MODULE=${findModule('collect', 'SimpleFeeCollectModule', 'v1')}\n`
);
str.write(
  `LEGACY_MULTIRECIPIENT_FEE_COLLECT_MODULE=${findModule(
    'collect',
    'MultirecipientFeeCollectModule',
    'v1'
  )}\n`
);

// LEGACY FOLLOW MODULES
str.write(`\n## legacy follow modules\n`);
str.write(`LEGACY_FEE_FOLLOW_MODULE=${findModule('follow', 'FeeFollowModule', 'v1')}\n`);
str.write(`LEGACY_REVERT_FOLLOW_MODULE=${findModule('follow', 'RevertFollowModule', 'v1')}\n`);
str.write(`LEGACY_PROFILE_FOLLOW_MODULE=${findModule('follow', 'ProfileFollowModule', 'v1')}\n`);

// LEGACY REFERENCE MODULES
str.write(`\n## legacy reference modules\n`);
str.write(
  `LEGACY_TOKEN_GATED_REFERENCE_MODULE=${findModule(
    'reference',
    'TokenGatedReferenceModule',
    'v1'
  )}\n`
);
str.write(
  `LEGACY_FOLLOWER_ONLY_REFERENCE_MODULE=${findModule(
    'reference',
    'FollowerOnlyReferenceModule',
    'v1'
  )}\n`
);
str.write(
  `LEGACY_DEGREE_OF_SEPARATION_REFERENCE_MODULE=${findModule(
    'reference',
    'DegreesOfSeparationReferenceModule',
    'v1'
  )}\n`
);

str.write(`\n# v2 modules\n`);
// V2 ACT MODULES
str.write(`## v2 act modules\n`);
str.write(`### Collect open action\n`);
// We need to find the CollectPublicationAction inside Modules/V2/act[] array {name, addy}
str.write(
  `LENS_COLLECT_PUBLICATION_ACTION_PROXY=${findModule('act', 'CollectPublicationAction', 'v2')}\n`
);

// V2 COLLECT MODULES
str.write(`\n## v2 collect modules\n`);
str.write(
  `MULTIRECIPIENT_FEE_COLLECT_OPEN_ACTION_MODULE=${findModule(
    'collect',
    'MultirecipientFeeCollectModule',
    'v2'
  )}\n`
);
str.write(
  `SIMPLE_COLLECT_OPEN_ACTION_MODULE=${findModule('collect', 'SimpleFeeCollectModule', 'v2')}\n`
);

// V2 FOLLOW MODULES
str.write(`\n## v2 follow modules\n`);
str.write(`FEE_FOLLOW_MODULE=${findModule('follow', 'FeeFollowModule', 'v2')}\n`);
str.write(`REVERT_FOLLOW_MODULE=${findModule('follow', 'RevertFollowModule', 'v2')}\n`);

// V2 REFERENCE MODULES
str.write(`\n## v2 reference modules\n`);
str.write(
  `DEGREE_OF_SEPARATION_REFERENCE_MODULE=${findModule(
    'reference',
    'DegreesOfSeparationReferenceModule',
    'v2'
  )}\n`
);
str.write(
  `FOLLOWER_ONLY_REFERENCE_MODULE=${findModule('reference', 'FollowerOnlyReferenceModule', 'v2')}\n`
);

// PublicActProxy ProfileId
str.write(`\n# PublicActProxy ProfileId\n`);
str.write(`LENS_PUBLIC_ACT_PROXY_PROFILE_ID=${addresses['AnonymousProfileId']}\n`);

// LitAccessControl
str.write(`\n# LitAccessControl\n`);
str.write(`LIT_ACCESS_CONTROL=${addresses['LitAccessControl']}\n`);

// Finished writing. Now we can close the stream
str.end();
