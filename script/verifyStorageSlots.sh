# This script compares the Storage Layout differences before/after the upgrade ("old"/"new" implementations).
# The addresses are taken from the addresses.json
# The address of previous implementation if fetched from TransparentProxy "implementation()" slot.
# The previous implementation source code is fetched from the block explorer.
# New implementation is assumed to be deployed and the new address is fetched from the addresses.json
# Storage Layouts are generated from both implementations and compared using diff
# (It is normal for the numbers in end of type names to be different)
source .env

set -e

if [[ $(colordiff --help 2>/dev/null) ]]
then
    shopt -s expand_aliases
    alias diff='colordiff'
    echo "Detected colordiff - using it"
fi

if [[ $1 == "" ]]
    then
        echo "This script compares the storage slot layout of two deployed contracts:"
        echo "  Proxy with OldImplementation and NewImplementation"
        echo "Used during upgrades to ensure no existing storage slots were affected by the upgrade"
        echo ""
        echo "Usage:"
        echo "  verifyStorageSlots.sh [targetDeployment] [contractName] [proxyNameInAddresses] [newImplNameInAddresses]"
        echo "    e.g. target (required): mainnet/testnet/sandbox"
        echo "    e.g. contractName (optional): LensHubInitializable (default)"
        echo "    e.g. proxyNameInAddresses (optional): LensHub (default)"
        echo "    e.g. newImplNameInAddresses (optional): LensHubV2Impl (default)"
        echo ""
        echo "Example:"
        echo "    verifyStorageSlots.sh mainnet LensHubInitializable LensHub LensHubV2Impl"
        exit 1
fi

# TransparentUpgradeableProxy implementation slot
IMPLEMENTATION_SLOT="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"

TARGET=$1

if [[ $2 == "" ]]
    then
        CONTRACT_NAME="LensHubInitializable"
    else
        CONTRACT_NAME=$2
fi

if [[ $3 == "" ]]
    then
        PROXY_NAME="LensHub"
    else
        PROXY_NAME=$3
fi

if [[ $4 == "" ]]
    then
        NEW_IMPL_NAME="LensHubV2Impl"
    else
        NEW_IMPL_NAME=$4
fi

NETWORK=$(node script/helpers/readNetwork.js $TARGET)
if [[ $NETWORK == "" ]]
    then
        echo "No network found for $TARGET environment target in addresses.json. Terminating"
        exit 1
fi

# if [[ $NETWORK == "mumbai" ]]
#     then
#         NETWORK="polygon-mumbai"
# fi

PROXY_ADDRESS=$(node script/helpers/readAddress.js $TARGET ${PROXY_NAME})
NEW_IMPLEMENTATION_ADDRESS=$(node script/helpers/readAddress.js $TARGET ${NEW_IMPL_NAME})

if [[ $PROXY_ADDRESS == "" ]]
    then
        echo "ERROR: CurrentDeployment address not found in addresses.json"
        exit 1
fi

echo "Network: $NETWORK $TARGET"
echo "Contract name:" $CONTRACT_NAME
echo ""
echo "Proxy address:" $PROXY_ADDRESS

# Fetching the old implementation address
RAW_OLD_IMPLEMENTATION_ADDRESS=$(cast storage $PROXY_ADDRESS $IMPLEMENTATION_SLOT --rpc-url $NETWORK)
OLD_IMPLEMENTATION_ADDRESS="0x${RAW_OLD_IMPLEMENTATION_ADDRESS:(-40)}"

echo "Old Implementation address: $OLD_IMPLEMENTATION_ADDRESS"
echo "New Implementation address: $NEW_IMPLEMENTATION_ADDRESS"

# Fetching the old implementation source code and saving it to oldImpl folder
rm -rf oldImpl
cast etherscan-source -d oldImpl $OLD_IMPLEMENTATION_ADDRESS --chain $NETWORK
echo "Old Implementation code saved to ./oldImpl/"

# Fetching the old implementation source code and saving it to oldImpl folder
rm -rf newImpl
cast etherscan-source -d newImpl $NEW_IMPLEMENTATION_ADDRESS --chain $NETWORK
echo "New Implementation code saved to ./newImpl/"

# Generating the Storage Layout JSON of the old implementation
echo "Generating the Storage Layout JSON of the old implementation..."

cp foundry.toml oldImpl/$CONTRACT_NAME
cp remappings.txt oldImpl/$CONTRACT_NAME
forge build --root oldImpl/$CONTRACT_NAME
cd oldImpl/$CONTRACT_NAME
forge inspect $CONTRACT_NAME storage > ../oldImplStorageLayout.json
cd ../..

# Generating the Storage Layout JSON of the new implementation
echo "Generating the Storage Layout JSON of the new implementation..."

cp foundry.toml newImpl/$CONTRACT_NAME
cp remappings.txt newImpl/$CONTRACT_NAME
forge build --root newImpl/$CONTRACT_NAME
cd newImpl/$CONTRACT_NAME
forge inspect $CONTRACT_NAME storage > ../newImplStorageLayout.json
cd ../..

diff <(awk '/astId/{next} /"types"/{found=0} {if(found) print} /"storage"/{found=1}' oldImpl/oldImplStorageLayout.json) <(awk '/astId/{next} /"types"/{found=0} {if(found) print} /"storage"/{found=1}' newImpl/newImplStorageLayout.json) -c

read -p "Delete fetched NewImpl/OldImpl sources? (y/n):" CONFIRMATION
if [[ "$CONFIRMATION" == "y" || "$CONFIRMATION" == "Y" ]]
    then
        rm -rf oldImpl
        rm -rf newImpl
fi
