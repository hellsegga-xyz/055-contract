async function main() {
    
    const SIZE_A = 48
    const SIZE_B = 4 
    const PACK = 24 
    const PACK2 = 24
    const CHANNELS = 3
    const UNROLL = 2
    const PACKED_LEN = SIZE_A / PACK
    const s = SIZE_A / SIZE_B

    const mimc7 = require('./mimc7.js');
    // Replace the key with your desired key
    const _key = BigInt(1);
    const secret_key_hash = mimc7.multiHash(_key, BigInt(0));

    function pack2int256(l, P) {
        let lc1 = BigInt(0)
        for (let i = 0; i < P; i++) {
            lc1 += BigInt(l[i]) * BigInt(256)**BigInt(i)
        }
        return lc1
    }

    function unpack2int8(n, P) {
        let out = []
        let e2 = BigInt(1)
        for (let i = 0; i < P; i++) {
            out.push((n >> i * 8) & 255)
            e2 = e2 * 256
        }
        return out
    }

    console.log(PACKED_LEN, s)

    const sharp = require('sharp');
    const fs = require('fs');

    const { data, info } = await sharp('hellsegga.jpg')
    .resize({ width: SIZE_A, height: SIZE_A })
    .raw()
    .toBuffer({ resolveWithObject: true });
  
    // create a more type safe way to work with the raw pixel data
    // this will not copy the data, instead it will change `data`s underlying ArrayBuffer
    // so `data` and `pixelArray` point to the same memory location
    const pixelArray = new Uint8ClampedArray(data.buffer);

    await sharp(pixelArray, { raw: info })
    .toFile('hellsegga-sharp-patch.jpg');

    // When you are done changing the pixelArray, sharp takes the `pixelArray` as an input
    const { width, height, channels } = info;

    console.log(pixelArray)
    console.log(width, height, )


    var r = new Uint16Array(s*s*channels);

    for (let i = 0; i < s; i ++) {
        for (let j = 0; j < s; j ++) {
            for (let c = 0; c < channels; c ++) {
                for (let k1 = 0; k1 < SIZE_B; k1 ++) {
                    for (let k2 = 0; k2 < SIZE_B; k2 ++) {
                            r[(i*s+j) * channels + c] += pixelArray[ ((i*SIZE_B + k1)*SIZE_A + (j*SIZE_B + k2)) * channels + c ]
                    }
                }
                r[(i*s+j) * channels + c] = r[(i*s+j) * channels + c] / (SIZE_B * SIZE_B)
            }
        }
    }

    console.log(r)
    await sharp(r, { raw: { width: s, height: s, channels } })
    .toFile('hellsegga-sharp-thumbnail.jpg');

    var thumbnail_size = s * s / PACK2;

    pack_out = []
    for (let i = 0; i < thumbnail_size; i++) {
        let pixel = []
        for (let c = 0; c < channels; c++) {
            pixel.push(BigInt(0))
        }
        pack_out.push(pixel)
    }
    
    for (let i = 0; i < thumbnail_size; i++) {
        for (let c = 0; c < channels; c++) {
            let l = []
            for (let k = 0; k < PACK2; k++) {
                l.push(BigInt(r[ (i*PACK2 + k) * channels + c ]))
            }
            let packed = pack2int256(l, PACK2)
            pack_out[i][c] = packed
        }
    }

    pack_in = []
    pack_in_correct_1 = []
    pack_in_incorrect_1 = []
    for (let i = 0; i < PACKED_LEN; i++) {
        let l = []
        let l2 = []
        let l3 = []
        for (let j = 0; j < SIZE_A; j++) {
            let pixel1 = []
            let pixel2 = []
            let pixel3 = []
            for (let c = 0; c < channels; c++) {
               pixel1.push(BigInt(0))
               pixel2.push(BigInt(0))
               pixel3.push(BigInt(0))
            }
            l.push(pixel1)
            l2.push(pixel2)
            l3.push(pixel3)
        }
        pack_in.push(l)
        pack_in_correct_1.push(l2)
        pack_in_incorrect_1.push(l3)
    }

    for (let i = 0; i < PACKED_LEN; i++) {
        for (let j = 0; j < SIZE_A; j++) {
            for (let c = 0; c < channels; c++) {
                let l = []
                for (let k = 0; k < PACK; k++) {
                    l.push(BigInt(pixelArray[ ((i*PACK + k)*SIZE_A + j) * channels + c ]))
                }
                let packed = pack2int256(l, PACK)
                pack_in[i][j][c] = packed
            }
        }
    }

    for (let i = 0; i < PACKED_LEN; i++) {
        for (let j = 0; j < SIZE_A; j++) {
            for (let c = 0; c < channels; c++) {
                let l = []
                for (let k = 0; k < PACK / UNROLL; k++) {
                    l.push(BigInt(pixelArray[ ((i*PACK + UNROLL*k + 1)*SIZE_A + j) * channels + c ]))
                    l.push(BigInt(pixelArray[ ((i*PACK + UNROLL*k + 0)*SIZE_A + j) * channels + c ]))
                }
                let packed = pack2int256(l, PACK)
                pack_in_correct_1[i][j][c] = packed
            }
        }
    }

    for (let i = 0; i < PACKED_LEN; i++) {
        for (let j = 0; j < SIZE_A; j++) {
            for (let c = 0; c < channels; c++) {
                let l = []
                for (let k = 0; k < PACK; k++) {
                    if (Math.random() < 0.1) {
                        l.push(BigInt(pixelArray[ ((i*PACK + k)*SIZE_A + j) * channels + c ]))
                    } 
                    else {
                        l.push(BigInt(0))
                    }
                }
                let packed = pack2int256(l, PACK)
                pack_in_incorrect_1[i][j][c] = packed
            }
        }
    }

    BigInt.prototype.toJSON = function() { return this.toString()  }

    let d = {
        'secret_key_hash': secret_key_hash,
        'secret_key': _monster_group_size,
        'image_compact': pack_in,
        'pooled_compact': pack_out,
        'image_compact_correct_1': pack_in_correct_1, 
        'image_compact_incorrect_1': pack_in_incorrect_1,    
        's_a': SIZE_A.toString(),
        's_b': SIZE_B.toString(), 
        'channels': CHANNELS.toString(),
        'pack': PACK.toString(),
        'pack2': PACK2.toString(),
        'packed_len': PACKED_LEN.toString(),
    }

    fs.writeFileSync(
        './sample.json',
        JSON.stringify(d, null, 2),
        () => {},
    );

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });