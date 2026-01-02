#!/usr/bin/env bash

# imports  
. scripts/envVar.sh

CHANNEL_NAME="$1"
DELAY="$2"
MAX_RETRY="$3"
VERBOSE="$4"
BFT="$5"
: ${CHANNEL_NAME:="mychannel"}
: ${DELAY:="3"}
: ${MAX_RETRY:="5"}
: ${VERBOSE:="false"}
: ${BFT:=0}

: ${CONTAINER_CLI:="docker"}
if command -v ${CONTAINER_CLI}-compose > /dev/null 2>&1; then
    : ${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI}-compose"}
else
    : ${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI} compose"}
fi
infoln "Using ${CONTAINER_CLI} and ${CONTAINER_CLI_COMPOSE}"

if [ ! -d "channel-artifacts" ]; then
	mkdir channel-artifacts
fi

createChannelGenesisBlock() {
  setGlobals 1
  which configtxgen
  if [ "$?" -ne 0 ]; then
    fatalln "configtxgen tool not found."
  fi

  local profileName=""
  if [ "${CHANNEL_NAME}" = "publicchannel" ]; then
    profileName="EDDACPublicChannel"
  elif [ "${CHANNEL_NAME}" = "attrchannel" ]; then
    profileName="EDDACAttrChannel"
  else
    fatalln "Unknown channel '${CHANNEL_NAME}'. Expected 'publicchannel' or 'attrchannel'"
  fi

  set -x
  configtxgen -profile "${profileName}" \
    -outputBlock ./channel-artifacts/${CHANNEL_NAME}.block \
    -channelID ${CHANNEL_NAME}
  res=$?
  { set +x; } 2>/dev/null
  verifyResult $res "Failed to generate channel configuration transaction for ${CHANNEL_NAME}"
}

. scripts/envVar.sh
createChannel() {
	# Poll in case the raft leader is not set yet
	local rc=1
	local COUNTER=1
	local bft_true=$1
	infoln "Adding orderers"
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
		sleep $DELAY
		set -x
    . scripts/orderer.sh ${CHANNEL_NAME}> /dev/null 2>&1
    if [ $bft_true -eq 1 ]; then
      . scripts/orderer2.sh ${CHANNEL_NAME}> /dev/null 2>&1
      . scripts/orderer3.sh ${CHANNEL_NAME}> /dev/null 2>&1
      . scripts/orderer4.sh ${CHANNEL_NAME}> /dev/null 2>&1
    fi
		res=$?
		{ set +x; } 2>/dev/null
		let rc=$res
		COUNTER=$(expr $COUNTER + 1)
	done
	cat log.txt
	verifyResult $res "Channel creation failed"
}

# joinChannel ORG
joinChannel() {
  ORG=$1
  PEER_IDX=${2:-0}

  setGlobals $ORG $PEER_IDX

  local rc=1
  local COUNTER=1

  ## Sometimes Join takes time, hence retry
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
    sleep $DELAY
    set -x
    peer channel join -b $BLOCKFILE >&log.txt
    res=$?
    { set +x; } 2>/dev/null
    let rc=$res
    COUNTER=$(expr $COUNTER + 1)
  done

  cat log.txt
  verifyResult $res "After $MAX_RETRY attempts, peer${PEER_IDX}.org${ORG} has failed to join channel '$CHANNEL_NAME' "
}

setAnchorPeer() {
  ORG=$1
  . scripts/setAnchorPeer.sh $ORG $CHANNEL_NAME
}

## Create channel genesis block
FABRIC_CFG_PATH=$PWD/../config/
BLOCKFILE="./channel-artifacts/${CHANNEL_NAME}.block"

infoln "Generating channel genesis block '${CHANNEL_NAME}.block'"
FABRIC_CFG_PATH=${PWD}/configtx
if [ $BFT -eq 1 ]; then
  FABRIC_CFG_PATH=${PWD}/bft-config
fi
createChannelGenesisBlock $BFT

. scripts/envVar.sh

## Create channel
infoln "Creating channel ${CHANNEL_NAME}"
createChannel $BFT
successln "Channel '$CHANNEL_NAME' created"

## Join all the peers to the channel
if [ "${CHANNEL_NAME}" = "publicchannel" ]; then
  infoln "Joining org1 (AA1) peer to channel '${CHANNEL_NAME}'..."
  joinChannel 1
  infoln "Joining org2 (AA2) peer to channel '${CHANNEL_NAME}'..."
  joinChannel 2
  infoln "Joining org3 (AA3) peer to channel '${CHANNEL_NAME}'..."
  joinChannel 3
  infoln "Joining org4 (DT) peer to channel '${CHANNEL_NAME}'..."
  for p in 0 1 2 3 4; do
    infoln "Joining org4 (DT) peer${p} to channel '${CHANNEL_NAME}'..."
    joinChannel 4 $p
  done

  ## Anchor peers
  infoln "Setting anchor peer for org1 (AA1) on '${CHANNEL_NAME}'..."
  setAnchorPeer 1
  infoln "Setting anchor peer for org2 (AA2) on '${CHANNEL_NAME}'..."
  setAnchorPeer 2
  infoln "Setting anchor peer for org3 (AA3) on '${CHANNEL_NAME}'..."
  setAnchorPeer 3
  infoln "Setting anchor peer for org4 (DT) on '${CHANNEL_NAME}'..."
  setAnchorPeer 4

elif [ "${CHANNEL_NAME}" = "attrchannel" ]; then
  infoln "Joining org1 (AA1) peer to channel '${CHANNEL_NAME}'..."
  joinChannel 1
  infoln "Joining org2 (AA2) peer to channel '${CHANNEL_NAME}'..."
  joinChannel 2
  infoln "Joining org3 (AA3) peer to channel '${CHANNEL_NAME}'..."
  joinChannel 3

  infoln "Setting anchor peer for org1 (AA1) on '${CHANNEL_NAME}'..."
  setAnchorPeer 1
  infoln "Setting anchor peer for org2 (AA2) on '${CHANNEL_NAME}'..."
  setAnchorPeer 2
  infoln "Setting anchor peer for org3 (AA3) on '${CHANNEL_NAME}'..."
  setAnchorPeer 3

else
  infoln "Joining org1 peer to the channel '${CHANNEL_NAME}'..."
  joinChannel 1
  infoln "Joining org2 peer to the channel '${CHANNEL_NAME}'..."
  joinChannel 2

  infoln "Setting anchor peer for org1 on '${CHANNEL_NAME}'..."
  setAnchorPeer 1
  infoln "Setting anchor peer for org2 on '${CHANNEL_NAME}'..."
  setAnchorPeer 2
fi

successln "Channel '${CHANNEL_NAME}' joined"
