async function main() {
        
    const fs = require("fs");

    const mimc7 = require('./mimc7.js');
    const { Keypair } = require('maci-domainobjs');
    const { genPubKey, formatPrivKeyForBabyJub, genEcdhSharedKey } = require('maci-crypto');
    
    const data = JSON.parse(fs.readFileSync("./sample.json"));
    var k1 = JSON.parse(fs.readFileSync("./keys/private_key1.json"));
    var k2 = JSON.parse(fs.readFileSync("./keys/private_key2.json"));
    k1.rawPrivKey = BigInt(k1.rawPrivKey);
    k2.rawPrivKey = BigInt(k2.rawPrivKey);

    const key = new Keypair(privKey=k1);
    const key2 = new Keypair(privKey=k2);

    const sharedKey2 = Keypair.genEcdhSharedKey(key.privKey, key2.pubKey);
    const sharedKey = Keypair.genEcdhSharedKey(key2.privKey, key.pubKey);

    function tobigint(value) {
        return BigInt(value);
    }

    var im = data.image_compact

    var to_hash = [];
    var s_a = parseInt(data.s_a);
    var c = parseInt(data.channels);
    var u = parseInt(data.packed_len);

    console.log(c);

    var idx = 0;
    for (var i = 0; i < u; i++) {
        for (var j = 0; j < s_a; j++) {
            for (var k = 0; k < c; k++) {
                to_hash.push(im[i][j][k]);
                idx = idx + 1;
            }
        }
    }
    const image_hash = mimc7.multiHash(to_hash.map(tobigint), BigInt(0));
    console.log(image_hash);

    console.log("Image Hash: ");
    console.log(image_hash);
    console.log("Public Key1: ");
    console.log(key.pubKey.asCircuitInputs());
    console.log("Private Key1: ");
    console.log(key.privKey);
    console.log("Public Key2: ");
    console.log(key2.pubKey.asCircuitInputs());
    console.log("Private Key2: ");
    console.log(key2.privKey);
    console.log("Shared Key: ");
    console.log(sharedKey);
    console.log(sharedKey2);
    
    const Scalar = require("ffjavascript").Scalar;
    const ZqField = require("ffjavascript").ZqField;
    const F = new ZqField(Scalar.fromString("21888242871839275222246405745257275088548364400416034343698204186575808495617"));

    var enc = [];
    var compact = [];
    var dec = [];

    var idx = 0;
    for (var i = 0; i < u; i++) {
        for (var j = 0; j < s_a; j++) {
            for (var k = 0; k < c; k++) {
                var val2 = mimc7.hash(sharedKey, F.add(F.e(image_hash), F.e(idx)));
                idx = idx + 1;
                var res = F.add(F.e(im[i][j][k]), F.e(val2));
                enc.push(res);
                compact.push(im[i][j][k]);
            }
        }
    }

    idx = 0;
    for (var i = 0; i < u; i++) {
        for (var j = 0; j < s_a; j++) {
            for (var k = 0; k < c; k++) {
                var val2 = mimc7.hash(sharedKey, F.add(F.e(image_hash), F.e(idx)));
                dec.push( enc[idx] - val2 );
                idx = idx + 1;
            }
        }
    }

    BigInt.prototype.toJSON = function() { return this.toString()  }

    console.log(key2.privKey.rawPrivKey.toString());
    console.log( formatPrivKeyForBabyJub(key2.privKey.rawPrivKey).toString() );

    var input = {
        secret_key: data.secret_key,
        hash_image: image_hash,
        user_private_key: formatPrivKeyForBabyJub(key2.privKey.rawPrivKey).toString(),
        public_key: key.pubKey.asCircuitInputs(),
        user_public_key: key2.pubKey.asCircuitInputs(),
        image_enc : enc,
        image_compact: compact
    };

    fs.writeFileSync(
        './reveal/input.json',
        JSON.stringify(input, null, 2),
        () => {},
    );

}


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });