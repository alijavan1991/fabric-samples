#!/usr/bin/env bash
set -euo pipefail

indent10() { sed 's/^/          /' "$1"; }  # 10 spaces

emit_yaml() {
  local ORGDOMAIN="$1" ORGNAME="$2" MSPID="$3" P0PORT="$4" CAHOST="$5" CAPORT="$6" CANAME="$7"

  local PEERHOST="peer0.${ORGDOMAIN}"
  local OUTDIR="organizations/peerOrganizations/${ORGDOMAIN}"
  local OUTFILE="${OUTDIR}/connection-$(echo "$ORGNAME" | tr '[:upper:]' '[:lower:]').yaml"

  local PEERPEM="${OUTDIR}/tlsca/tlsca.${ORGDOMAIN}-cert.pem"
  local CAPEM="${OUTDIR}/ca/ca.${ORGDOMAIN}-cert.pem"

  # Read & indent certs properly (NO backslashes)
  local PEERPEM_I CAPEM_I
  PEERPEM_I="$(indent10 "$PEERPEM")"
  CAPEM_I="$(indent10 "$CAPEM")"

  cat > "$OUTFILE" <<EOF
---
name: eddac-$(echo "$ORGNAME" | tr '[:upper:]' '[:lower:]')
version: 1.0.0
client:
  organization: ${ORGNAME}
  connection:
    timeout:
      peer:
        endorser: '300'

organizations:
  ${ORGNAME}:
    mspid: ${MSPID}
    peers:
      - ${PEERHOST}
    certificateAuthorities:
      - ${CAHOST}

peers:
  ${PEERHOST}:
    url: grpcs://${PEERHOST}:${P0PORT}
    tlsCACerts:
      pem: |
${PEERPEM_I}
    grpcOptions:
      ssl-target-name-override: ${PEERHOST}
      hostnameOverride: ${PEERHOST}

certificateAuthorities:
  ${CAHOST}:
    url: https://${CAHOST}:${CAPORT}
    caName: ${CANAME}
    tlsCACerts:
      pem: |
${CAPEM_I}
    httpOptions:
      verify: false
EOF

  echo "[ok] wrote ${OUTFILE}"
}

cd /root/fabric-samples/eddac

emit_yaml "aa1.example.com" "AA1" "AA1MSP" 7051 "ca_org1" 7054 "ca-org1"
emit_yaml "aa2.example.com" "AA2" "AA2MSP" 8051 "ca_org2" 8054 "ca-org2"

emit_yaml "aa3.example.com" "AA3" "AA3MSP" 9051 "ca_org3" 11054 "ca-org3"

emit_yaml "dt.example.com"  "DT"  "DTMSP"  10051 "ca_org4" 10054 "ca-org4"
