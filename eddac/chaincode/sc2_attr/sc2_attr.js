// file: sc2_attr.js
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

class SC2 extends Contract {

    // --------------------------------------------------------------------
    // InitLedger on C2 – optional, no-op.
    // --------------------------------------------------------------------
    async InitLedger(ctx) {
        return;
    }

    // --------------------------------------------------------------------
    // CreateUser: create user record on L2.
    // --------------------------------------------------------------------
    async CreateUser(ctx, userId) {
        const key = ctx.stub.createCompositeKey('USER', [userId]);
        const exists = await ctx.stub.getState(key);
        if (exists && exists.length > 0) {
            throw new Error(`User ${userId} already exists`);
        }
        const rec = { userId };
        await ctx.stub.putState(key, Buffer.from(JSON.stringify(rec)));
        return JSON.stringify(rec);
    }

    // --------------------------------------------------------------------
    // CreateHidAtt: AAEN uploads hidden attribute CH(A_{i,j}) to L2.
    //
    // This is SetHidAttTx in Fig.5(c) and CreateHidAtt in Fig.8.
    // --------------------------------------------------------------------
    async CreateHidAtt(ctx, userId, category, chValue, rValue, aaenId) {
        const key = ctx.stub.createCompositeKey('ATTR', [userId, category]);

        const attr = {
            userId,
            category,
            chValue,   // decimal string CH(A_{i,j})
            rValue,    // decimal string r
            aaenId
        };

        await ctx.stub.putState(key, Buffer.from(JSON.stringify(attr)));
        return JSON.stringify(attr);
    }

    async GetHiddenAttributes(ctx, userId) {
        const iterator = await ctx.stub.getStateByPartialCompositeKey('ATTR', [userId]);
        const res = [];

        // NOTE: Some fabric-shim versions return iterators that are NOT async-iterable,
        // so we consume them with iterator.next() rather than `for await ... of`.
        while (true) {
            const r = await iterator.next();

            if (r.value) {
                // r.value is usually a KeyValue: { key, value: Buffer }
                const buf = r.value.value || r.value; // be defensive across shim versions
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
    // CreateUserVec: transform all hidden attributes of a user into
    // vector S, as described in the paper (TransAttToVecTx).
    //
    // For n attributes:
    //   S[0]        = ∏ CH_i
    //   S[1..C(n,2)] = CH_i * CH_j (i<j)
    //   S[...]      = CH_1,...,CH_n
    //   S[last]     = 1
    //
    // --------------------------------------------------------------------
    async CreateUserVec(ctx, userId) {
        const attrsJson = await this.GetHiddenAttributes(ctx, userId);
        const attrs = JSON.parse(attrsJson);
        if (attrs.length === 0) {
            throw new Error(`No hidden attributes for user ${userId}`);
        }

        attrs.sort((a, b) => a.category.localeCompare(b.category));
        const chValues = attrs.map(a => {
            let v = BigInt(a.chValue);
            v = modP(v);
            return v;
        });

        const n = chValues.length;

        // Product of all CH_i
        let prodAll = 1n;
        for (const v of chValues) {
            prodAll = modP(prodAll * v);
        }

        // Pairwise CH_i * CH_j (i<j)
        const pairwise = [];
        for (let i = 0; i < n; i++) {
            for (let j = i + 1; j < n; j++) {
                const val = modP(chValues[i] * chValues[j]);
                pairwise.push(val);
            }
        }

        const singles = chValues;
        const S = [prodAll, ...pairwise, ...singles, 1n];
        const Sstr = S.map(x => x.toString());

        // Optional: store S on C2
        const key = ctx.stub.createCompositeKey('USERVEC', [userId]);
        await ctx.stub.putState(key, Buffer.from(JSON.stringify({ userId, S: Sstr })));


        return JSON.stringify({
            userId,
            S: Sstr
        });
    }
    // --------------------------------------------------------------------
    // Fig.5 transaction-name aliases (so Caliper labels match the paper).
    // --------------------------------------------------------------------
    async SetHidAttTx(ctx, userId, category, chValue, rValue, aaenId) {
        return await this.CreateHidAtt(ctx, userId, category, chValue, rValue, aaenId);
    }

    async TransAttToVecTx(ctx, userId) {
        return await this.CreateUserVec(ctx, userId);
    }

}

module.exports = SC2;
