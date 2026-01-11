import { readFileSync, existsSync } from "fs";

describe('Evaluate submission', () => {
    let txid: string;
    let tx: any;

    it('should check if out.txt exists and contains valid txid', () => {
        // Check if out.txt exists
        expect(existsSync('out.txt')).toBe(true);
        
        // read txid from out.txt
        const data = readFileSync('out.txt', 'utf8');
        txid = data.trim();
        expect(txid).toBeDefined();
        expect(txid.length).toBe(64);
        expect(txid).toMatch(/^[a-fA-F0-9]{64}$/);
    });

    it('should get transaction details from node', async () => {
        const RPC_USER="alice";
        const RPC_PASSWORD="password";
        const RPC_HOST="http://127.0.0.1:18443";

        let response;
        try {
            response = await fetch(RPC_HOST, {
                method: 'post',
                body: JSON.stringify({
                    jsonrpc: '1.0',
                    id: 'curltest',
                    method: 'gettransaction',
                    params: [txid, null, true]
                }),
                headers: {
                    'Content-Type': 'text/plain',
                    'Authorization': 'Basic ' + Buffer.from(`${RPC_USER}:${RPC_PASSWORD}`).toString('base64'),
                }
            });
        } catch (error) {
            throw new Error(`Failed to connect to Bitcoin node: ${error.message}. Make sure the Bitcoin node is running and accessible.`);
        }

        expect(response.ok).toBe(true);
        
        const json = await response.json();
        expect(json.error).toBeNull();
        expect(json.result).not.toBeNull();
        expect(json.result.txid).toBe(txid);

        tx = json.result;
    });

    it('should check if fee is exactly 21 sats/vByte', () => {
        expect(tx).toBeDefined();
        expect(tx.fee).toBeDefined();
        expect(tx.decoded).toBeDefined();
        expect(tx.decoded.vsize).toBeDefined();
        
        const fee = Math.abs(tx.fee * 1e8); // Convert to satoshis and make positive
        const expectedFee = tx.decoded.vsize * 21;
        expect(fee).toBe(expectedFee);
    });

    it('should validate 100 BTC output to correct address', () => {
        expect(tx).toBeDefined();
        expect(tx.decoded).toBeDefined();
        expect(tx.decoded.vout).toBeDefined();
        
        const output = tx.decoded.vout.find((vout: any) => vout.value === 100);
        expect(output).toBeDefined();
        expect(output.value).toBe(100);
        expect(output.scriptPubKey.address).toBe('bcrt1qq2yshcmzdlznnpxx258xswqlmqcxjs4dssfxt2');
    });

    it('should validate OP_RETURN output with correct message', () => {
        expect(tx).toBeDefined();
        expect(tx.decoded).toBeDefined();
        expect(tx.decoded.vout).toBeDefined();
        
        const output = tx.decoded.vout.find((vout: any) => vout.value === 0);
        expect(output).toBeDefined();
        expect(output.value).toBe(0);
        expect(output.scriptPubKey.hex).toBeDefined();
        expect(output.scriptPubKey.hex.slice(0, 4)).toBe('6a14'); // OP_RETURN with 20 bytes
        
        const messageHex = output.scriptPubKey.hex.slice(4);
        const message = Buffer.from(messageHex, 'hex').toString('utf8');
        expect(message).toBe('We are all Satoshi!!');
    });
});