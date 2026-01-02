'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

/**
 * Caliper workload for reproducing the EDDAC Fig.5-style "transaction volume" sweep:
 * - Keep ~50 concurrent workers (benchmark.yaml: test.workers.number = 50)
 * - Sweep offered load (TPS) from 250..2500 by using fixed-rate rateControl
 *
 * This module supports the paper's transaction names:
 *   SC1 (publicchannel, contractId=sc1): InitLedger, GetPKABETx, CreatePKCHTx, GetAllPKCHTx, SetPolicyVecTx, DecTestTx, StoreUserVec
 *   SC2 (attrchannel,   contractId=sc2): SetHidAttTx, TransAttToVecTx
 */
class EddacVolumeWorkload extends WorkloadModuleBase {
  constructor() {
    super();
    this.txIndex = 0;
  }

  _nowId() {
    return `${Date.now()}_${Math.floor(Math.random() * 1e9)}`;
  }

  _randB64(bytes) {
    return crypto.randomBytes(bytes).toString('base64');
  }

  async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
    await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);

    this.workerIndex = workerIndex;
    this.roundIndex = roundIndex;
    this.args = roundArguments || {};
    this.txType = this.args.txType;

    // Round-unique prefix so different rounds do not interfere with each other.
    this.prefix = `${this.txType}_r${roundIndex}_w${workerIndex}_${this._nowId()}`;

    // Default IDs used by some tx types
    this.userId = `${this.prefix}_user`;
    this.objectId = `${this.prefix}_obj`;

    // fixed AAEN ids (paper uses 3 AAENs)
    this.aaenIds = this.args.aaenIds || ['AA1', 'AA2', 'AA3'];
    
    
    // Pre-setup that MUST happen before measured txs for some tx types.
    if (this.txType === 'TransAttToVecTx') {
      // Ensure user has some hidden attributes on SC2.
      const attrCount = Number(this.args.attrCount || 10);
      for (let i = 0; i < attrCount; i++) {
        const category = `c${i}`;                // part of composite key ATTR~userId~category
        const chValue = String(1000 + i);        // decimal strings, chaincode normalizes mod p
        const rValue = String(2000 + i);
        const aaenId = `aaen_${this.prefix}`;

        await this.sutAdapter.sendRequests({
          contractId: 'sc2',
          channel: 'attrchannel',
          contractFunction: 'SetHidAttTx',
          contractArguments: [this.userId, category, chValue, rValue, aaenId],
          readOnly: false
        });
      }
    }

    if (this.txType === 'DecTestTx') {
      // SC1.DecTestTx reads S(userId) from SC1 world state and P(objectId) from object meta.
      // Prepare them once per worker.
      const S = ['11', '22', '33', '44', '55', '66', '77', '88']; // length must match P
      const P = ['1', '2', '3', '4', '5', '6', '7', '8'];

      await this.sutAdapter.sendRequests({
        contractId: 'sc1',
        channel: 'publicchannel',
        contractFunction: 'StoreUserVec',
        contractArguments: [this.userId, JSON.stringify(S)],
        readOnly: false
      });

      await this.sutAdapter.sendRequests({
        contractId: 'sc1',
        channel: 'publicchannel',
        contractFunction: 'SetPolicyVecTx',
        contractArguments: [
          this.objectId,
          'owner1',
          JSON.stringify(P),
          this._randB64(16),
          this._randB64(32),
          this._randB64(32)
        ],
        readOnly: false
      });
    }
  }

  async submitTransaction() {
    const i = this.txIndex++;
    const txType = this.txType;

    // Allow per-round override, otherwise use sensible defaults.
    const readOnlyOverride = this.args.readOnly;
    const isReadOnly = (readOnlyOverride !== undefined)
      ? Boolean(readOnlyOverride)
      : (txType === 'GetPKABETx' || txType === 'GetAllPKCHTx');

    if (txType === 'InitLedger') {
      // Only needs to exist so GetPKABETx won't fail with "PKABE not initialized".
      const pkABE = { scheme: 'PKABE', createdAt: new Date().toISOString() };
      const shamir = { t: 2, n: 3 };
      return this.sutAdapter.sendRequests({
        contractId: 'sc1',
        channel: 'publicchannel',
        contractFunction: 'InitLedger',
        contractArguments: [JSON.stringify(pkABE), JSON.stringify(shamir)],
        readOnly: false
      });
    }

    if (txType === 'GetPKABETx') {
      return this.sutAdapter.sendRequests({
        contractId: 'sc1',
        channel: 'publicchannel',
        contractFunction: 'GetPKABETx',
        contractArguments: [],
        readOnly: true
      });
    }

    if (txType === 'CreatePKCHTx') {
      // Overwrite-style design:
      //   - Only a small fixed set of PKCH entries on L1 (e.g., AA1, AA2, AA3)
      //   - Each worker always writes to one of these AAEN ids
      //
      // This keeps #PKCH bounded (~3) even when we sweep TPS up to 2500.

      // Pick AAEN id from a fixed small set, e.g. ['AA1','AA2','AA3'].
      // Distribute workers across them using workerIndex modulo length.
      const aaenIds = this.aaenIds || ['AA1', 'AA2', 'AA3'];
      const aaenId = aaenIds[this.workerIndex % aaenIds.length];

      const index = aaenId;                      // this is the key-part for PKCH
      const pkCH = {
        aaenId,
        pk: this._randB64(24),
        ts: Date.now()
      };

      return this.sutAdapter.sendRequests({
        contractId: 'sc1',
        channel: 'publicchannel',
        contractFunction: 'CreatePKCHTx',
        contractArguments: [index, JSON.stringify(pkCH)],
        readOnly: false
      });
    }

    if (txType === 'GetAllPKCHTx') {
      return this.sutAdapter.sendRequests({
        contractId: 'sc1',
        channel: 'publicchannel',
        contractFunction: 'GetAllPKCHTx',
        contractArguments: [],
        readOnly: true
      });
    }

    if (txType === 'SetPolicyVecTx') {
      const objectId = `${this.prefix}_obj_${i}`;
      const P = ['1', '2', '3', '4', '5', '6', '7', '8'];
      return this.sutAdapter.sendRequests({
        contractId: 'sc1',
        channel: 'publicchannel',
        contractFunction: 'SetPolicyVecTx',
        contractArguments: [
          objectId,
          'owner1',
          JSON.stringify(P),
          this._randB64(16),
          this._randB64(32),
          this._randB64(32)
        ],
        readOnly: false
      });
    }

    if (txType === 'DecTestTx') {
      // Reuse prepared (objectId, userId) per worker: no write-contention across workers.
      return this.sutAdapter.sendRequests({
        contractId: 'sc1',
        channel: 'publicchannel',
        contractFunction: 'DecTestTx',
        contractArguments: [this.objectId, this.userId],
        readOnly: false
      });
    }

    if (txType === 'SetHidAttTx') {
      // Create an attribute under a round-unique user, each tx uses unique category to avoid MVCC conflicts.
      const userId = this.userId; // fixed per worker/round
      const category = `c${i}`;
      const chValue = String(1000 + (i % 1000));
      const rValue = String(2000 + (i % 1000));
      const aaenId = `aaen_${this.prefix}`;
      return this.sutAdapter.sendRequests({
        contractId: 'sc2',
        channel: 'attrchannel',
        contractFunction: 'SetHidAttTx',
        contractArguments: [userId, category, chValue, rValue, aaenId],
        readOnly: false
      });
    }

    if (txType === 'TransAttToVecTx') {
      // Recompute vector for the pre-seeded user.
      return this.sutAdapter.sendRequests({
        contractId: 'sc2',
        channel: 'attrchannel',
        contractFunction: 'TransAttToVecTx',
        contractArguments: [this.userId],
        readOnly: false
      });
    }

    throw new Error(`Unknown txType: ${txType}`);
  }
}

function createWorkloadModule() {
  return new EddacVolumeWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
