#!/usr/bin/env bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This is a collection of bash functions used by different scripts

# imports
# test network home var targets to test-network folder
# the reason we use a var here is to accommodate scenarios
# where execution occurs from folders outside of default as $PWD, such as the test-network/addOrg3 folder.
# For setting environment variables, simple relative paths like ".." could lead to unintended references
# due to how they interact with FABRIC_CFG_PATH. It's advised to specify paths more explicitly,
# such as using "../${PWD}", to ensure that Fabric's environment variables are pointing to the correct paths.
TEST_NETWORK_HOME=${TEST_NETWORK_HOME:-${PWD}}
. ${TEST_NETWORK_HOME}/scripts/utils.sh
export FABRIC_CFG_PATH=${TEST_NETWORK_HOME}/compose/docker/peercfg

# TLS CAs
export CORE_PEER_TLS_ENABLED=true
export ORDERER_CA=${TEST_NETWORK_HOME}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

# Org1 = AA1
export PEER0_ORG1_CA=${TEST_NETWORK_HOME}/organizations/peerOrganizations/aa1.example.com/peers/peer0.aa1.example.com/tls/ca.crt

# Org2 = AA2
export PEER0_ORG2_CA=${TEST_NETWORK_HOME}/organizations/peerOrganizations/aa2.example.com/peers/peer0.aa2.example.com/tls/ca.crt

# Org3 = AA3
export PEER0_ORG3_CA=${TEST_NETWORK_HOME}/organizations/peerOrganizations/aa3.example.com/peers/peer0.aa3.example.com/tls/ca.crt

# Org4 = DT
export PEER0_ORG4_CA=${TEST_NETWORK_HOME}/organizations/peerOrganizations/dt.example.com/peers/peer0.dt.example.com/tls/ca.crt
export PEER1_ORG4_CA=${TEST_NETWORK_HOME}/organizations/peerOrganizations/dt.example.com/peers/peer1.dt.example.com/tls/ca.crt
export PEER2_ORG4_CA=${TEST_NETWORK_HOME}/organizations/peerOrganizations/dt.example.com/peers/peer2.dt.example.com/tls/ca.crt
export PEER3_ORG4_CA=${TEST_NETWORK_HOME}/organizations/peerOrganizations/dt.example.com/peers/peer3.dt.example.com/tls/ca.crt
export PEER4_ORG4_CA=${TEST_NETWORK_HOME}/organizations/peerOrganizations/dt.example.com/peers/peer4.dt.example.com/tls/ca.crt


# Set environment variables for the peer org
setGlobals() {
  local USING_ORG=""
  if [ -z "$OVERRIDE_ORG" ]; then
    USING_ORG=$1
  else
    USING_ORG="${OVERRIDE_ORG}"
  fi
  infoln "Using organization ${USING_ORG}"

  if [ $USING_ORG -eq 1 ]; then
    # Org1 = AA1
    export CORE_PEER_LOCALMSPID=AA1MSP
    export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG1_CA
    export CORE_PEER_MSPCONFIGPATH=${TEST_NETWORK_HOME}/organizations/peerOrganizations/aa1.example.com/users/Admin@aa1.example.com/msp
    export CORE_PEER_ADDRESS=localhost:7051

  elif [ $USING_ORG -eq 2 ]; then
    # Org2 = AA2
    export CORE_PEER_LOCALMSPID=AA2MSP
    export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG2_CA
    export CORE_PEER_MSPCONFIGPATH=${TEST_NETWORK_HOME}/organizations/peerOrganizations/aa2.example.com/users/Admin@aa2.example.com/msp
    export CORE_PEER_ADDRESS=localhost:8051

  elif [ $USING_ORG -eq 3 ]; then
    # Org3 = AA3
    export CORE_PEER_LOCALMSPID=AA3MSP
    export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG3_CA
    export CORE_PEER_MSPCONFIGPATH=${TEST_NETWORK_HOME}/organizations/peerOrganizations/aa3.example.com/users/Admin@aa3.example.com/msp
    export CORE_PEER_ADDRESS=localhost:9051

  elif [ $USING_ORG -eq 4 ]; then
    # Org4 = DT  (جدید)
    export CORE_PEER_LOCALMSPID=DTMSP
    export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG4_CA
    export CORE_PEER_MSPCONFIGPATH=${TEST_NETWORK_HOME}/organizations/peerOrganizations/dt.example.com/users/Admin@dt.example.com/msp
    export CORE_PEER_ADDRESS=localhost:10051

    case "$PEER_IDX" in
      0) export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG4_CA; export CORE_PEER_ADDRESS=localhost:10051 ;;
      1) export CORE_PEER_TLS_ROOTCERT_FILE=$PEER1_ORG4_CA; export CORE_PEER_ADDRESS=localhost:11051 ;;
      2) export CORE_PEER_TLS_ROOTCERT_FILE=$PEER2_ORG4_CA; export CORE_PEER_ADDRESS=localhost:12051 ;;
      3) export CORE_PEER_TLS_ROOTCERT_FILE=$PEER3_ORG4_CA; export CORE_PEER_ADDRESS=localhost:13051 ;;
      4) export CORE_PEER_TLS_ROOTCERT_FILE=$PEER4_ORG4_CA; export CORE_PEER_ADDRESS=localhost:14051 ;;
      *) fatalln "DT peer index must be 0..4 (got '${PEER_IDX}')" ;;
    esac

  else
    errorln "ORG Unknown"
  fi

  if [ "$VERBOSE" = "true" ]; then
    env | grep CORE_PEER
  fi
}

# parsePeerConnectionParameters $@
# Helper function that sets the peer connection parameters for a chaincode
# operation
parsePeerConnectionParameters() {
  PEER_CONN_PARMS=()
  PEERS=""
  while [ "$#" -gt 0 ]; do
    setGlobals $1
    PEER="peer0.org$1"
    ## Set peer addresses
    if [ -z "$PEERS" ]
    then
	PEERS="$PEER"
    else
	PEERS="$PEERS $PEER"
    fi
    PEER_CONN_PARMS=("${PEER_CONN_PARMS[@]}" --peerAddresses $CORE_PEER_ADDRESS)
    ## Set path to TLS certificate
    CA=PEER0_ORG$1_CA
    TLSINFO=(--tlsRootCertFiles "${!CA}")
    PEER_CONN_PARMS=("${PEER_CONN_PARMS[@]}" "${TLSINFO[@]}")
    # shift by one to get to the next organization
    shift
  done
}

verifyResult() {
  if [ $1 -ne 0 ]; then
    fatalln "$2"
  fi
}
