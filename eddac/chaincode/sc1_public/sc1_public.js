// file: sc1_public.js
'use strict';

const { Contract } = require('fabric-contract-api');

// Large prime modulus for vector arithmetic (testing only).
// Must be identical in SC1 + SC2 and in any off-chain vector generation.
const PRIME_P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

// Ensure non-negative modulo for BigInt.
function modP(x) {
    const r = x % PRIME_P;
    return r >= 0n ? r : r + PRIME_P;
}

function innerProductMod(S, P) {
    if (S.length !== P.length) {
        throw new Error(`Inner product length mismatch: S=${S.length}, P=${P.length}`);
    }
    let sum = 0n;
    for (let i = 0; i < S.length; i++) {
        const s = modP(S[i]);
        const p = modP(P[i]);
        sum = modP(sum + modP(s * p));
    }
    return sum;
}

class SC1 extends Contract {

    // --------------------------------------------------------------------
    // InitLedger: record PK_ABE and Shamir config on L1.
    // This is what the paper calls "CreatePKABETx" and "InitLedger" on SC1.
    // --------------------------------------------------------------------
    async InitLedger(ctx, pkABEJson, shamirConfigJson) {
        const pkABE = JSON.parse(pkABEJson);
        const shamir = JSON.parse(shamirConfigJson);

        await ctx.stub.putState('SYS#PKABE', Buffer.from(JSON.stringify(pkABE)));
        await ctx.stub.putState('SYS#SHAMIR', Buffer.from(JSON.stringify(shamir)));
        return JSON.stringify({ pkABE, shamir });
    }

    // ReadPKABE: support GetPKABETx benchmark
    async ReadPKABE(ctx) {
        const data = await ctx.stub.getState('SYS#PKABE');
        if (!data || data.length === 0) {
            throw new Error('PKABE not initialized');
        }
        return data.toString('utf8');
    }

    // --------------------------------------------------------------------
    // CH public keys: CreatePKCH / ReadPKCH / GetAllPKCH
    // These correspond to CreatePKCHTx, GetPKCHTx, GetAllPKCHTx in Fig.5(b).
    // --------------------------------------------------------------------
    async CreatePKCH(ctx, index, pkCHJson) {
        const key = ctx.stub.createCompositeKey('PKCH', [index]);
        await ctx.stub.putState(key, Buffer.from(pkCHJson));
        return pkCHJson;
    }

    async ReadPKCH(ctx, index) {
        const key = ctx.stub.createCompositeKey('PKCH', [index]);
        const data = await ctx.stub.getState(key);
        if (!data || data.length === 0) {
            throw new Error(`No PKCH at index ${index}`);
        }
        return data.toString('utf8');
    }

    async GetAllPKCH(ctx) {
        const iterator = await ctx.stub.getStateByPartialCompositeKey('PKCH', []);
        const res = [];

        // NOTE: Some fabric-shim versions return iterators that are NOT async-iterable.
        while (true) {
            const r = await iterator.next();

            if (r.value) {
                const buf = r.value.value || r.value;
                res.push(JSON.parse(buf.toString('utf8')));
            }

            if (r.done) {
                await iterator.close();
                break;
            }
        }
        return JSON.stringify(res);
    }

    // --------------------------------------------------------------------
    // CreateVec: set policy vector P on L1.
    //
    // This is SetPolicyVecTx in Fig.5(c).
    // It stores:
    //   - P (as vector of decimal strings mod p)
    //   - C0 (from ABE ciphertext)
    //   - encrypted address of ciphertext, etc.
    // --------------------------------------------------------------------
    async CreateVec(ctx,
                    objectId,
                    ownerId,
                    policyVectorJson,
                    c0Base64,
                    addressCipherBase64,
                    ctKeyPartBase64) {

        const P_str = JSON.parse(policyVectorJson);
        const P_norm = P_str.map(x => {
            let v = BigInt(x);
            v = modP(v);
            return v.toString();
        });

        const meta = {
            objectId,
            ownerId,
            policyVector: P_norm,
            c0: c0Base64,
            addressCipher: addressCipherBase64,
            ctKeyPart: ctKeyPartBase64
        };

        const key = ctx.stub.createCompositeKey('DATA', [objectId]);
        await ctx.stub.putState(key, Buffer.from(JSON.stringify(meta)));
        return JSON.stringify(meta);
    }

    async GetDataMeta(ctx, objectId) {
        const key = ctx.stub.createCompositeKey('DATA', [objectId]);
        const data = await ctx.stub.getState(key);
        if (!data || data.length === 0) {
            throw new Error(`No DATA meta for object ${objectId}`);
        }
        return data.toString('utf8');
    }

    // --------------------------------------------------------------------
    // Helper: store user vector S on L1 (called by client after CreateUserVec
    // on SC2).
    // --------------------------------------------------------------------
    async StoreUserVec(ctx, userId, sVectorJson) {
        const S_str = JSON.parse(sVectorJson);
        const S_norm = S_str.map(x => {
            let v = BigInt(x);
            v = modP(v);
            return v.toString();
        });
        const rec = { userId, S: S_norm };
        const key = ctx.stub.createCompositeKey('S', [userId]);
        await ctx.stub.putState(key, Buffer.from(JSON.stringify(rec)));
        return JSON.stringify(rec);
    }

    async ReadUserVec(ctx, userId) {
        const key = ctx.stub.createCompositeKey('S', [userId]);
        const data = await ctx.stub.getState(key);
        if (!data || data.length === 0) {
            throw new Error(`No S vector for user ${userId}`);
        }
        return data.toString('utf8');
    }

    // --------------------------------------------------------------------
    // DecTest: decryption test transaction on L1.
    //
    // This is DecTestTx in Fig.5(c) and corresponds to decryption_test_phase()
    // in main.py. It reads S(userId) and P(objectId) and computes <S,P> mod p.
    // --------------------------------------------------------------------
    async DecTest(ctx, objectId, requesterId) {
        // Read S vector for requester from L1
        const SrecJson = await this.ReadUserVec(ctx, requesterId);
        const Srec = JSON.parse(SrecJson);
        const S = Srec.S.map(x => BigInt(x));

        // Read policy vector P for object from L1
        const metaJson = await this.GetDataMeta(ctx, objectId);
        const meta = JSON.parse(metaJson);
        const P = meta.policyVector.map(x => BigInt(x));

        // Compute inner product <S,P> mod p
        const ip = innerProductMod(S, P);
        const allowed = (ip === 0n);

        // Deterministic timestamp from transaction proposal (same for all endorsers)
        const txTs = ctx.stub.getTxTimestamp(); // { seconds: Long, nanos: number }
        // Some environments expose seconds as Long with toNumber()
        const sec =
            (txTs && txTs.seconds && typeof txTs.seconds.toNumber === 'function')
                ? txTs.seconds.toNumber()
                : Number(txTs.seconds || 0);
        const nanos = Number(txTs.nanos || 0);
        const millis = (sec * 1000) + Math.floor(nanos / 1e6);
        const tsISO = new Date(millis).toISOString();

        // Deterministic unique transaction id
        const txId = ctx.stub.getTxID();

        // Access decision record (deterministic content)
        const access = {
            objectId,
            requesterId,
            allowed,
            innerProduct: ip.toString(),
            txId,
            timestamp: tsISO
        };

        // Store an immutable access log entry (no overwrite)
        // Key: ACCESS~objectId~requesterId~txId
        const histKey = ctx.stub.createCompositeKey('ACCESS', [objectId, requesterId, txId]);
        await ctx.stub.putState(histKey, Buffer.from(JSON.stringify(access)));
    
        // (Optional but useful) Store the latest decision for quick lookup/benchmarking
        // Key: ACCESS_LAST~objectId~requesterId  (overwrites each time deterministically)
        const lastKey = ctx.stub.createCompositeKey('ACCESS_LAST', [objectId, requesterId]);
        await ctx.stub.putState(lastKey, Buffer.from(JSON.stringify(access)));

        return JSON.stringify(access);
    }
    // --------------------------------------------------------------------
    // Fig.5 transaction-name aliases (so Caliper labels match the paper).
    // --------------------------------------------------------------------
    async GetPKABETx(ctx) {
        return await this.ReadPKABE(ctx);
    }

    async CreatePKCHTx(ctx, index, pkCHJson) {
        return await this.CreatePKCH(ctx, index, pkCHJson);
    }

    async GetAllPKCHTx(ctx) {
        return await this.GetAllPKCH(ctx);
    }

    async SetPolicyVecTx(ctx, objectId, ownerId, policyVectorJson, c0Base64, addressCipherBase64, ctKeyPartBase64) {
        return await this.CreateVec(ctx, objectId, ownerId, policyVectorJson, c0Base64, addressCipherBase64, ctKeyPartBase64);
    }

    async DecTestTx(ctx, objectId, requesterId) {
        return await this.DecTest(ctx, objectId, requesterId);
    }

}

module.exports = SC1;
