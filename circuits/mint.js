async function main() {
        
    const fs = require("fs");

    const mimc7 = require('./mimc7.js');
    const { Keypair } = require('maci-domainobjs');
    const key = new Keypair();
    const key2 = new Keypair();
    
    const sharedKey = Keypair.genEcdhSharedKey(key.privKey, key2.pubKey);
    const sharedKey2 = Keypair.genEcdhSharedKey(key2.privKey, key.pubKey);

    function tobigint(value) {
        return BigInt(value);
    }

    // Replace this with the intended address
    const address = BigInt("0x0");

    const data = JSON.parse(fs.readFileSync("./sample.json"));
    
    var im = data.image_compact;
    var s_a = parseInt(data.s_a);
    var c = parseInt(data.channels);
    var u = parseInt(data.packed_len);

    function hash(img) {
        var to_hash = [];
        var idx = 0;
        for (var i = 0; i < u; i++) {
            for (var j = 0; j < s_a; j++) {
                for (var k = 0; k < c; k++) {
                    to_hash.push(img[i][j][k]);
                    idx = idx + 1;
                }
            }
        }
        const image_hash = mimc7.multiHash(to_hash.map(tobigint), BigInt(0));
        return image_hash;    
    }

    image_hash = hash(data.image_compact);

    console.log("Image Hash: ");
    console.log(image_hash);
    console.log(hash(data.image_compact_correct_1));
    console.log(hash(data.image_compact_incorrect_1));
    
    console.log("Public Key1: ");
    console.log(key.pubKey.asCircuitInputs());
    console.log("Private Key1: ");
    console.log(key.privKey.asCircuitInputs());
    console.log("Public Key2: ");
    console.log(key2.pubKey.asCircuitInputs());
    console.log("Private Key2: ");
    console.log(key2.privKey.asCircuitInputs());
    console.log("Shared Key: ");
    console.log(sharedKey);
    console.log(sharedKey2);
        
    const Scalar = require("ffjavascript").Scalar;
    const ZqField = require("ffjavascript").ZqField;
    const F = new ZqField(Scalar.fromString("21888242871839275222246405745257275088548364400416034343698204186575808495617"));

    function encrypt(img, hash) {
        var enc = [];
        var compact = [];

        var idx = 0;
        for (var i = 0; i < u; i++) {
            for (var j = 0; j < s_a; j++) {
                for (var k = 0; k < c; k++) {
                    var val2 = mimc7.hash(sharedKey, F.add(F.e(hash), F.e(idx)));
                    idx = idx + 1;
                    enc.push(F.add(F.e(img[i][j][k]), F.e(val2)));
                    compact.push(img[i][j][k]);
                }
            }
        } 
        return enc;
    }

    BigInt.prototype.toJSON = function() { return this.toString()  }

    var input = {
        secret_key: data.secret_key,
        mint_address: address,
        private_address: address,
        hash_image: image_hash,
        private_key: key.privKey.asCircuitInputs(),
        public_key: key.pubKey.asCircuitInputs(),
        user_public_key: key2.pubKey.asCircuitInputs(),
        image_compact: data.image_compact,
        image_enc : encrypt(im, image_hash),
        pooled_compact: data.pooled_compact,
    };
  
    fs.writeFileSync(
        './mint/input.json',
        JSON.stringify(input, null, 2),
        () => {},
    );

    input = {
        secret_key: data.secret_key,
        mint_address: address,
        private_address: address,
        hash_image: hash(data.image_compact_correct_1),
        image_compact: data.image_compact_correct_1,
        private_key: key.privKey.asCircuitInputs(),
        public_key: key.pubKey.asCircuitInputs(),
        user_public_key: key2.pubKey.asCircuitInputs(),
        image_enc : encrypt(data.image_compact_correct_1, hash(data.image_compact_correct_1)),
        pooled_compact: data.pooled_compact,
    };
  
    fs.writeFileSync(
        './mint/input_correct_1.json',
        JSON.stringify(input, null, 2),
        () => {},
    );

    input = {
        secret_key: BigInt(420),
        mint_address: address,
        private_address: address,
        hash_image: hash(data.image_compact_incorrect_1),
        image_compact: data.image_compact_incorrect_1,
        private_key: key.privKey.asCircuitInputs(),
        public_key: key.pubKey.asCircuitInputs(),
        user_public_key: key2.pubKey.asCircuitInputs(),
        image_enc : encrypt(data.image_compact_incorrect_1, hash(data.image_compact_incorrect_1)),
        pooled_compact: data.pooled_compact,
    };
  
    fs.writeFileSync(
        './mint/input_incorrect_1.json',
        JSON.stringify(input, null, 2),
        () => {},
    );

    fs.writeFileSync(
        './keys/private_key2.json',
        JSON.stringify(key2.privKey, null, 2),
        () => {},
    );

    fs.writeFileSync(
        './keys/private_key1.json',
        JSON.stringify(key.privKey, null, 2),
        () => {},
    );

}


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });