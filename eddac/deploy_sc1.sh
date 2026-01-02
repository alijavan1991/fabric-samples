#!/usr/bin/bash

pushd /root/fabric-samples/eddac

export PATH=${PWD}/../bin:$PATH

export FABRIC_CFG_PATH=$PWD/compose/docker/peercfg

. scripts/envVar.sh
. scripts/ccutils.sh

./network.sh createChannel -c publicchannel
./network.sh createChannel -c attrchannel


export CHANNEL_NAME=publicchannel
export CC_NAME=sc1
export CC_SRC_PATH=chaincode/sc1_public
export CC_VERSION=1.0
export CC_SEQUENCE=1
export DELAY=3
export MAX_RETRY=5
export VERBOSE=false
export INIT_REQUIRED=""
export CC_END_POLICY=""
export CC_COLL_CONFIG=""

./scripts/packageCC.sh $CC_NAME $CC_SRC_PATH javascript $CC_VERSION
export PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ${CC_NAME}.tar.gz)


installChaincode 1
installChaincode 2
installChaincode 3
installChaincode 4 0
installChaincode 4 1
installChaincode 4 2
installChaincode 4 3
installChaincode 4 4

approveForMyOrg 1
approveForMyOrg 2
approveForMyOrg 3
approveForMyOrg 4


commitChaincodeDefinition 1 2 3 4


queryCommitted 1


