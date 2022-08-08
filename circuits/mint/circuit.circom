pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/pedersen.circom";
include "../range_proof/circuit.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/switcher.circom";
include "../node_modules/circomlib/circuits/sign.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/mimcsponge.circom";
include "../crypto/encrypt.circom";
include "../crypto/ecdh.circom";
include "../math/circuit.circom";
include "../crypto/publickey_derivation.circom";

/*
s_a = SIZE_A
s_b = SIZE_B
c = CHANNELS
*/

/*
Public Input Signals:
- pooled_compact (thumbnail image)
- public_key
- user_public_key
- mint_address
- hash_image

Private Input Signals:
- image_compact (original image)
- secret_key
- private_key
- private_address
- image_enc
*/

// Note that this circuit has no output
template Mint(s_a, s_b, c, pack, pack2) {

    // Secret key
    signal input secret_key;
    component secret_key_hash[2];
    
    secret_key_hash[0] = MiMC7(91);
    secret_key_hash[1] = MiMC7(91);
    
    secret_key_hash[0].x_in <== secret_key;
    secret_key_hash[0].k <== 0;
    secret_key_hash[1].x_in <== 808017424794512849313485887658987330265356840558657536;
    secret_key_hash[1].k <== 0;
    
    // Ensures hash of secret_key is hash of the really large number
    secret_key_hash[0].out === secret_key_hash[1].out;

    // Preventing mint-squatting: proof is address bound
    component hash_addr[2]; 
    signal input mint_address;
    signal input private_address;

    hash_addr[0] = MiMC7(91);
    hash_addr[1] = MiMC7(91);

    // Ensures hash of mint_address is hash of private_address
    hash_addr[0].x_in <== mint_address;
    hash_addr[0].k <== 0;
    hash_addr[1].x_in <== private_address;
    hash_addr[1].k <== 0;
    hash_addr[0].out === hash_addr[1].out;

    // Un-packing image_compact to image
    var u = s_a \ pack;
    signal input image_compact[u][s_a][c];
    component unpack[u][s_a][c];
    signal image[s_a][s_a][c];
    for (var i = 0; i < u; i++) {
        for (var j = 0; j < s_a; j++) {
            for (var c0 = 0; c0 < c; c0++){
                unpack[i][j][c0] = Num2Uint8(pack);
                //log(image_compact[i][j][c0]);
                unpack[i][j][c0].in <== image_compact[i][j][c0];
                
                for (var k = 0; k < pack; k++){
                    unpack[i][j][c0].out[k] ==> image[i*pack+k][j][c0];
                    //log(unpack[i][j][c0].out[k]);
                }
            }
        }
    }
    
    // ECDH Encryption & prventing down-sample attack: 
    // cryptographic hash of entire image
    signal input hash_image;
    signal input private_key;
    signal input user_public_key[2];
    signal input public_key[2];
    signal input image_enc[u*s_a*c];

    // Component that derives the public key using private key as input
    component pubkey = PublicKey();

    // Ensures the private key (private input) matches the public key (public input)
    pubkey.private_key <== private_key;
    pubkey.public_key[0] === public_key[0];
    pubkey.public_key[1] === public_key[1];
    log(public_key[0]);
    log(public_key[1]);

    // Component that derives the shared key with public key and private key as input
    component ecdh = Ecdh();
    // Computes shared key using user_public_key and private_key
    ecdh.private_key <== private_key;
    ecdh.public_key[0] <== user_public_key[0];
    ecdh.public_key[1] <== user_public_key[1];

    // Component that encrypts data using a shared key as input
    // out[0] is a hash (using MultiMiMC7) of the entire image into a constant sized string
    // out[1] to out[N] are hashes of individual pixels (using MiMC7)
    component enc = EncryptBits(u*s_a*c);

    enc.shared_key <== ecdh.shared_key;

    // Encrypts image_compact
    var h = 0;
    for (var i = 0; i < u; i++){
        for (var j = 0; j < s_a; j++){
            for (var c0 = 0; c0 < c; c0++){
                enc.plaintext[h] <== image_compact[i][j][c0];
                h += 1;
           }
        }
    }

    // Ensures the hash_image matches the hash of image_compact
    enc.out[0] === hash_image;

    // Ensures the encrypted image is image_enc
    for (var i = 1; i < u*s_a*c + 1; i ++) {
        enc.out[i] === image_enc[i-1];
    }
      
    // Down-sampling
    // Computes the size of the thumbnail
    var d = s_a \ s_b;
    signal r[d][d][c][s_b*s_b+1];
    signal pooled[d*d][c];

    // Computes the thumbnail from image (which came from image_compact)
    for (var i = 0; i < d; i++) {
        for (var j = 0; j < d; j++) {
            for (var c0 = 0; c0 < c; c0++) {
                var idx = 0;
                r[i][j][c0][0] <== 0;
                for (var k1 = 0; k1 < s_b; k1++) {
                    for (var k2 =0; k2 < s_b; k2 ++) {
                        r[i][j][c0][idx+1] <== r[i][j][c0][idx] + image[i*s_b + k1][j*s_b + k2][c0];
                        idx+=1;
                    }
                }
            }
        }
    }

    component div[d][d][c];

    // Takes the average of s_b by s_b pixels, which results in the thumbnail (set to variable pooled)
    for (var i = 0; i < d; i++) {
        for (var j = 0; j < d; j++) {
           for (var c0 = 0; c0 < c; c0++) {
                div[i][j][c0] = PositiveModulo(14);
                div[i][j][c0].dividend <== r[i][j][c0][s_b*s_b];
                div[i][j][c0].divisor <== s_b * s_b;
                pooled[i*d+j][c0] <== div[i][j][c0].quotient;
                //log(pooled[i][j][c0]);
            }
        }
    } 
    
 
    var thumbnail_size = d * d \ pack2;
    signal input pooled_compact[thumbnail_size][c];
    component unpack2[thumbnail_size][c];

    // Unpacks pooled_compact
    for (var i = 0; i < thumbnail_size; i++) {
        for (var c0 = 0; c0 < c; c0++){
            unpack2[i][c0] = Num2Uint8(pack2);
            unpack2[i][c0].in <== pooled_compact[i][c0];

            for (var k = 0; k < pack2; k++) {
                // Ensures pooled_compact is pooled
                unpack2[i][c0].out[k] === pooled[i*pack2 + k][c0];
            }
        }
    }
    
}

component main {public [pooled_compact, public_key, user_public_key, mint_address, hash_image]} = Mint(48,4,3,24,24);