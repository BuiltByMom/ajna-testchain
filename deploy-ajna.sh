#!/bin/bash
set -e

# terminate with message upon error
function fail {
    echo Deployment failed.
    exit 1
}

# set up environment for the ganache container
export ETH_RPC_URL=http://0.0.0.0:8555
export DEPLOY_ADDRESS=0xeeDC2EE00730314b7d7ddBf7d19e81FB7E5176CA
export DEPLOY_RAWKEY=0xd332a346e8211513373b7ddcf94b2b513b934b901258a9465c76d0d9a2b676d8

./getBlockTime.sh $ETH_RPC_URL
echo Deploying AJNA to ${ETH_RPC_URL:?}

# regular expressions to pluck addresses from deployment logs
regex_ajna_token_address=".*AJNA[[:space:]]token[[:space:]]deployed[[:space:]]to[[:space:]]([0-9xa-fA-F]+)*."
regex_burnwrapper_address=".*Created[[:space:]]BurnWrapper[[:space:]]at[[:space:]]([0-9xa-fA-F]+)*."
regex_grantfund_address=".*GrantFund[[:space:]]deployed[[:space:]]to[[:space:]]([0-9xa-fA-F]+)*."
regex_erc20_factory_address=".*ERC20PoolFactory[[:space:]]+([0-9xa-fA-F]+)*."
regex_erc721_factory_address=".*ERC721PoolFactory[[:space:]]+([0-9xa-fA-F]+)*."
regex_poolinfoutils_address=".*PoolInfoUtils[[:space:]]+([0-9xa-fA-F]+)*."
regex_multicallutils_address=".*PoolInfoUtilsMulticall[[:space:]]+([0-9xa-fA-F]+)*."
regex_positionmanager_address=".*PositionManager[[:space:]]+([0-9xa-fA-F]+)*."
regex_tokensfactory_address=".*TokensFactory[[:space:]]+deployed[[:space:]]+to[[:space:]]+([0-9xa-fA-F]+)*."
regex_lenderhelper_address=".*Deployed[[:space:]]+to[[:space:]]+([0-9xa-fA-F]+)*."

# Test to ensure user cloned repositories into expected locations.
pushd ../ajna-grants && popd || fail
pushd ../ajna-core && popd || fail
pushd ../tokens-factory && popd || fail

# "forge script" cannot use the forked AJNA token, so deploy a new one to the fork
pushd ../ajna-grants
export MINT_TO_ADDRESS=${DEPLOY_ADDRESS}
deploy_cmd="forge script script/AjnaToken.s.sol:DeployAjnaToken \
		    --rpc-url ${ETH_RPC_URL} --froms ${DEPLOY_ADDRESS} --private-key ${DEPLOY_RAWKEY} --broadcast -vvv"
output=$(${deploy_cmd})
if [[ $output =~ $regex_ajna_token_address ]]
then
    export AJNA_TOKEN=${BASH_REMATCH[1]}
else
    echo $output
    echo Could not determine AJNA token address.
    popd && fail
fi
# since we minted 2bbn, burn half the tokens
cast send ${AJNA_TOKEN} "burn(uint256)" 1000000000ether --from $DEPLOY_ADDRESS --private-key $DEPLOY_RAWKEY > /dev/null

# deploy BurnWrapper
# modify source to set correct AJNA_TOKEN address
sed -i "" -E "s#(AJNA_TOKEN_ADDRESS = )0x[0-9A-Fa-f]+#\1${AJNA_TOKEN}#" src/token/BurnWrapper.sol || fail
deploy_cmd="forge script script/BurnWrapper.s.sol:DeployBurnWrapper \
		    --rpc-url ${ETH_RPC_URL} --froms ${DEPLOY_ADDRESS} --private-key ${DEPLOY_RAWKEY} --broadcast -vvv"
output=$(${deploy_cmd})

if [[ $output =~ $regex_burnwrapper_address ]]
then
    export BURNWRAPPER=${BASH_REMATCH[1]}
else
    echo "$output"
    echo Could not determine BurnWrapper address.
    popd && fail
fi

# deploy GrantFund
deploy_cmd="forge script script/GrantFund.s.sol:DeployGrantFund \
	            --rpc-url ${ETH_RPC_URL} --froms ${DEPLOY_ADDRESS} --private-key ${DEPLOY_RAWKEY} --broadcast -vvv"
output=$(${deploy_cmd})
if [[ $output =~ $regex_grantfund_address ]]
then
    export GRANTFUND=${BASH_REMATCH[1]}
else
    echo "$output"
    echo Could not determine GrantFund address.
    popd && fail
fi

# fund GrantFund with 300mm AJNA
cast send ${AJNA_TOKEN} "approve(address,uint256)" ${GRANTFUND} 300000000ether --from $DEPLOY_ADDRESS --private-key $DEPLOY_RAWKEY > /dev/null
cast send ${GRANTFUND} "fundTreasury(uint256)" 300000000ether --from $DEPLOY_ADDRESS --private-key $DEPLOY_RAWKEY > /dev/null
popd

# deploy everything in the ajna-core repository
pushd ../ajna-core
deploy_cmd="forge script ./script/deploy.s.sol \
		    --rpc-url ${ETH_RPC_URL} --froms ${DEPLOY_ADDRESS} --private-key ${DEPLOY_RAWKEY} --broadcast -vvv"
output=$(${deploy_cmd})

if [[ $output =~ $regex_erc20_factory_address ]]
then
    export ERC20FACTORY=${BASH_REMATCH[1]}
else
    echo "$output"
    echo Could not determine ERC20 factory address.
    popd && fail
fi
if [[ $output =~ $regex_erc721_factory_address ]]
then
    export ERC721FACTORY=${BASH_REMATCH[1]}
else
    echo "$output"
    echo Could not determine ERC721 factory address.
    popd && fail
fi
if [[ $output =~ $regex_poolinfoutils_address ]]
then
    export POOLINFOUTILS=${BASH_REMATCH[1]}
else
    echo "$output"
    echo Could not determine PoolInfoUtils address.
    popd && fail
fi
if [[ $output =~ $regex_multicallutils_address ]]
then
    export MULTICALLUTILS=${BASH_REMATCH[1]}
else
    echo "$output"
    echo Could not determine PoolInfoUtilsMulticall address.
    popd && fail
fi
if [[ $output =~ $regex_positionmanager_address ]]
then
    export POSITIONMANAGER=${BASH_REMATCH[1]}
else
    echo "$output"
    echo Could not determine PositionManager address.
    popd && fail
fi
popd

# deploy test token factory
pushd ../tokens-factory
deploy_cmd="forge script script/DeployTokensFactory.s.sol:DeployTokensFactory \
            --rpc-url ${ETH_RPC_URL} --froms ${DEPLOY_ADDRESS} --private-key ${DEPLOY_RAWKEY} --broadcast -vvv"
output=$(${deploy_cmd})
if [[ $output =~ $regex_tokensfactory_address ]]
then
    export TOKENSFACTORY=${BASH_REMATCH[1]}
else
    echo "$output"
    echo Could not determine TokensFactory address.
    popd && fail
fi
popd

# deploy lender helper
pushd ../ajna-wrapper
deploy_cmd="forge script script/deploy.s.sol \
            --rpc-url ${ETH_RPC_URL} --froms ${DEPLOY_ADDRESS} --private-key ${DEPLOY_RAWKEY} --broadcast -vvv"
output=$(${deploy_cmd})
if [[ $output =~ $regex_lenderhelper_address ]]
then
    export LENDERHELPER=${BASH_REMATCH[1]}
else
    echo "$output"
    echo Could not determine LenderHelper address.
    popd && fail
fi
popd

# print all the addresses
echo === Local Testchain Addresses ===
echo "AJNA token             ${AJNA_TOKEN}"
echo "BurnWrapper            ${BURNWRAPPER}"
echo "GrantFund              ${GRANTFUND}"
echo "ERC20 factory          ${ERC20FACTORY}"
echo "ERC721 factory         ${ERC721FACTORY}"
echo "PoolInfoUtils          ${POOLINFOUTILS}"
echo "PoolInfoUtilsMulticall ${MULTICALLUTILS}"
echo "PositionManager        ${POSITIONMANAGER}"
echo "TokensFactory          ${TOKENSFACTORY}"
echo "LenderHelper          ${LENDERHELPER}"

# Define the output file name
output_file="ganache.json"

# Write the variables to the output file in JSON format
echo "{" > "$output_file"
echo '  "AJNA token": "'${AJNA_TOKEN}'", ' >> "$output_file"
echo '  "GrantFund": "'${GRANTFUND}'", ' >> "$output_file"
echo '  "ERC20 factory": "'${ERC20FACTORY}'", ' >> "$output_file"
echo '  "ERC721 factory": "'${ERC721FACTORY}'", ' >> "$output_file"
echo '  "PoolInfoUtils": "'${POOLINFOUTILS}'", ' >> "$output_file"
echo '  "PoolInfoUtilsMulticall": "'${MULTICALLUTILS}'", ' >> "$output_file"
echo '  "PositionManager": "'${POSITIONMANAGER}'", ' >> "$output_file"
echo '  "TokensFactory": "'${TOKENSFACTORY}'", ' >> "$output_file"
echo '  "LenderHelper": "'${LENDERHELPER}'"' >> "$output_file"
echo "}" >> "$output_file"

echo "Variables have been written to $output_file."