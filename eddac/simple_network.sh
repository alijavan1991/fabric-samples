#!/usr/bin/env bash
set -euo pipefail

########################################
# General settings
########################################

CHANNEL1_NAME="public"
CHANNEL2_NAME="attr"

PROFILE1="EDDACPublicChannel"
PROFILE2="EDDACAttrChannel"

# Name of the orderer system-channel profile in configtx.yaml
# Use an existing profile in your configtx.yaml
ORDERER_GENESIS_PROFILE="EDDACPublicChannel"

COMPOSE_FILE="compose-test-net.yaml"
ARTIFACTS_DIR="channel-artifacts"

# Fabric binaries path (adjust if needed)
export PATH="${PWD}/../bin:${PATH}"
export FABRIC_CFG_PATH="${PWD}"

# Orderer TLS CA (note ../organizations here)
ORDERER_CA="${PWD}/../organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"

# Cryptogen config files (adjust names/paths if needed)
CRYPTOGEN_CONFIGS=(
  "crypto-config-orderer.yaml"
  "crypto-config-aa1.yaml"
  "crypto-config-aa2.yaml"
  "crypto-config-aa3.yaml"
  "crypto-config-dt.yaml"
)

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

########################################
# Crypto generation with cryptogen
########################################

generateCryptoMaterial() {

  for cfg in "${CRYPTOGEN_CONFIGS[@]}"; do
    if [ ! -f "$cfg" ]; then
      echo "Missing cryptogen config file: $cfg" >&2
      exit 1
    fi
    log "Generating crypto material using $cfg ..."
    cryptogen generate --config="$cfg" --output="../organizations"
  done

  log "Crypto material generated under ../organizations/."
}

########################################
# Genesis block for the orderer
########################################

generateGenesisBlock() {
  mkdir -p system-genesis-block

  log "Generating orderer genesis block using profile $ORDERER_GENESIS_PROFILE ..."
  configtxgen \
    -profile "$ORDERER_GENESIS_PROFILE" \
    -channelID "system-channel" \
    -outputBlock "./system-genesis-block/genesis.block"

  log "Genesis block written to system-genesis-block/genesis.block."
}

########################################
# Channel artifacts (channel create tx)
########################################

generateChannelArtifacts() {
  log "Generating channel create transactions..."
  mkdir -p "$ARTIFACTS_DIR"

  configtxgen -profile "$PROFILE1" \
    -outputCreateChannelTx "$ARTIFACTS_DIR/$CHANNEL1_NAME.tx" \
    -channelID "$CHANNEL1_NAME"

  configtxgen -profile "$PROFILE2" \
    -outputCreateChannelTx "$ARTIFACTS_DIR/$CHANNEL2_NAME.tx" \
    -channelID "$CHANNEL2_NAME"

  log "Channel artifacts generated under $ARTIFACTS_DIR/."
}

########################################
# Set environment for each peer
# ORG: aa1 | aa2 | aa3 | dt
# PEER_INDEX: used only for dt (0..4)
########################################

setGlobals() {
  local ORG="$1"
  local PEER_INDEX="${2:-0}"

  if [ "$ORG" = "aa1" ]; then
    export CORE_PEER_LOCALMSPID="AA1MSP"
    export CORE_PEER_MSPCONFIGPATH="${PWD}/../organizations/peerOrganizations/aa1.example.com/users/Admin@aa1.example.com/msp"
    export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/../organizations/peerOrganizations/aa1.example.com/peers/peer0.aa1.example.com/tls/ca.crt"
    export CORE_PEER_ADDRESS="localhost:7051"

  elif [ "$ORG" = "aa2" ]; then
    export CORE_PEER_LOCALMSPID="AA2MSP"
    export CORE_PEER_MSPCONFIGPATH="${PWD}/../organizations/peerOrganizations/aa2.example.com/users/Admin@aa2.example.com/msp"
    export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/../organizations/peerOrganizations/aa2.example.com/peers/peer0.aa2.example.com/tls/ca.crt"
    export CORE_PEER_ADDRESS="localhost:8051"

  elif [ "$ORG" = "aa3" ]; then
    export CORE_PEER_LOCALMSPID="AA3MSP"
    export CORE_PEER_MSPCONFIGPATH="${PWD}/../organizations/peerOrganizations/aa3.example.com/users/Admin@aa3.example.com/msp"
    export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/../organizations/peerOrganizations/aa3.example.com/peers/peer0.aa3.example.com/tls/ca.crt"
    # Adjust external port if your compose file uses a different mapping
    export CORE_PEER_ADDRESS="localhost:9052"

  elif [ "$ORG" = "dt" ]; then
    export CORE_PEER_LOCALMSPID="DTMSP"
    export CORE_PEER_MSPCONFIGPATH="${PWD}/../organizations/peerOrganizations/dt.example.com/users/Admin@dt.example.com/msp"

    case "$PEER_INDEX" in
      0)
        export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/../organizations/peerOrganizations/dt.example.com/peers/peer0.dt.example.com/tls/ca.crt"
        export CORE_PEER_ADDRESS="localhost:10051"
        ;;
      1)
        export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/../organizations/peerOrganizations/dt.example.com/peers/peer1.dt.example.com/tls/ca.crt"
        export CORE_PEER_ADDRESS="localhost:11051"
        ;;
      2)
        export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/../organizations/peerOrganizations/dt.example.com/peers/peer2.dt.example.com/tls/ca.crt"
        export CORE_PEER_ADDRESS="localhost:12051"
        ;;
      3)
        export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/../organizations/peerOrganizations/dt.example.com/peers/peer3.dt.example.com/tls/ca.crt"
        export CORE_PEER_ADDRESS="localhost:13051"
        ;;
      4)
        export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/../organizations/peerOrganizations/dt.example.com/peers/peer4.dt.example.com/tls/ca.crt"
        export CORE_PEER_ADDRESS="localhost:14051"
        ;;
      *)
        echo "Invalid DT peer index: $PEER_INDEX" >&2
        exit 1
        ;;
    esac
  else
    echo "Unknown org: $ORG" >&2
    exit 1
  fi
}

########################################
# Create channels and join peers
########################################

createAndJoinChannels() {
  # Channel 1: public (AA1, AA2, AA3, DT[0..4])
  log "Creating channel $CHANNEL1_NAME..."
  setGlobals aa1
  peer channel create \
    -o localhost:7050 \
    --ordererTLSHostnameOverride orderer.example.com \
    -c "$CHANNEL1_NAME" \
    -f "$ARTIFACTS_DIR/$CHANNEL1_NAME.tx" \
    --outputBlock "$ARTIFACTS_DIR/$CHANNEL1_NAME.block" \
    --tls \
    --cafile "$ORDERER_CA"

  log "Joining peers to channel $CHANNEL1_NAME..."

  setGlobals aa1
  peer channel join -b "$ARTIFACTS_DIR/$CHANNEL1_NAME.block"

  setGlobals aa2
  peer channel join -b "$ARTIFACTS_DIR/$CHANNEL1_NAME.block"

  setGlobals aa3
  peer channel join -b "$ARTIFACTS_DIR/$CHANNEL1_NAME.block"

  for i in 0 1 2 3 4; do
    setGlobals dt "$i"
    peer channel join -b "$ARTIFACTS_DIR/$CHANNEL1_NAME.block"
  done

  # Channel 2: attr (AA1, AA2, AA3 only)
  log "Creating channel $CHANNEL2_NAME..."
  setGlobals aa1
  peer channel create \
    -o localhost:7050 \
    --ordererTLSHostnameOverride orderer.example.com \
    -c "$CHANNEL2_NAME" \
    -f "$ARTIFACTS_DIR/$CHANNEL2_NAME.tx" \
    --outputBlock "$ARTIFACTS_DIR/$CHANNEL2_NAME.block" \
    --tls \
    --cafile "$ORDERER_CA"

  log "Joining peers to channel $CHANNEL2_NAME..."

  setGlobals aa1
  peer channel join -b "$ARTIFACTS_DIR/$CHANNEL2_NAME.block"

  setGlobals aa2
  peer channel join -b "$ARTIFACTS_DIR/$CHANNEL2_NAME.block"

  setGlobals aa3
  peer channel join -b "$ARTIFACTS_DIR/$CHANNEL2_NAME.block"

  log "Both channels created and peers joined."
}

########################################
# Network up / down
########################################

networkUp() {
  log "Generating crypto material (if needed)..."
  generateCryptoMaterial

  log "Generating orderer genesis block..."
  generateGenesisBlock

  log "Generating channel artifacts..."
  generateChannelArtifacts

  log "Starting Docker network using $COMPOSE_FILE..."
  docker compose -f "$COMPOSE_FILE" up -d

  log "Waiting for containers to start..."
  sleep 5

  createAndJoinChannels
  log "Network is up."
}

networkDown() {
  log "Shutting down network..."
  docker compose -f "$COMPOSE_FILE" down --volumes --remove-orphans || true
  rm -rf "$ARTIFACTS_DIR"
  # If you also want to delete crypto material, uncomment the following line:
  # rm -rf ../organizations system-genesis-block
  log "Network is down."
}

########################################
# Main
########################################

CMD="${1:-}"

if [ "$CMD" = "up" ]; then
  networkUp
elif [ "$CMD" = "down" ]; then
  networkDown
else
  echo "Usage: $0 {up|down}"
  exit 1
fi
